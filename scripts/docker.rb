# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "securerandom"
require "socket"

root = File.realpath(File.join(__dir__, ".."))
project = "calendar-#{Digest::SHA256.hexdigest(root)[0, 20]}"
directory = File.join(root, ".services")
config = File.join(directory, "docker.env")
command = ARGV.shift

if command == "setup"
  port = Integer(ENV.fetch("HTTPS_PORT"))
  abort "HTTPS_PORT must be in 1024..65535" unless (1024..65535).cover?(port)
  TCPServer.new("127.0.0.1", port).close
  FileUtils.mkdir_p(directory, mode: 0o700)
  File.open(config, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
    file.puts "HTTPS_PORT=#{port}"
    file.puts "POSTGRES_PASSWORD=#{SecureRandom.hex(32)}"
    file.puts "SECRET_KEY_BASE=#{SecureRandom.hex(64)}"
    file.puts "ADMIN_USERNAME=owner"
    file.puts "ADMIN_PASSWORD=#{SecureRandom.hex(24)}"
  end
  puts "Created private .services/docker.env; keep it and database storage together."
  exit
end

abort "Run HTTPS_PORT=<free port> ruby scripts/docker.rb setup first" unless File.file?(config)
abort "Private Docker configuration must not be group/world accessible" unless (File.stat(config).mode & 0o077).zero?
File.readlines(config, chomp: true).each do |line|
  key, value = line.split("=", 2)
  abort "Invalid private Docker configuration" unless %w[HTTPS_PORT POSTGRES_PASSWORD SECRET_KEY_BASE ADMIN_USERNAME ADMIN_PASSWORD].include?(key) && value && !value.empty?
  ENV[key] = value
end
ENV["CALENDAR_CHECKOUT"] = root

# Refuse to reuse any project resource owned by another checkout. Never prune,
# remove volumes, or touch the development Compose project.
{ "container" => "ps", "volume" => "ls", "network" => "ls" }.each do |type, list|
  listing = type == "container" ? [ list, "-a", "-q" ] : [ list, "-q" ]
  output, status = Open3.capture2("docker", type, *listing, "--filter", "label=com.docker.compose.project=#{project}")
  abort "Cannot inspect Docker #{type} ownership" unless status.success?
  output.split.each do |id|
    raw, inspected = Open3.capture2("docker", type, "inspect", id)
    abort "Cannot inspect Docker resource" unless inspected.success?
    resource = JSON.parse(raw).first
    labels = type == "container" ? resource.fetch("Config").fetch("Labels") : resource.fetch("Labels")
    abort "Refusing resource with conflicting checkout ownership" unless labels["dev.calendar.checkout"] == root
  end
end

args = case command
when "build" then [ "build", "--pull" ]
when "up" then [ "up", "-d", "--wait", "--wait-timeout", "180" ]
when "restart"
  base = [ "docker", "compose", "--project-name", project, "--env-file", config, "-f", File.join(root, "compose.application.yml") ]
  system(*base, "restart", "app", exception: true)
  [ "up", "-d", "--wait", "--wait-timeout", "180" ]
when "recreate" then [ "up", "-d", "--force-recreate", "--no-deps", "--wait", "--wait-timeout", "180", "app" ]
when "stop" then [ "stop" ]
when "status" then [ "ps" ]
when "logs" then [ "logs", "--tail", "100" ]
when "exec" then [ "exec", "-T", *ARGV ]
else abort "Usage: ruby scripts/docker.rb setup|build|up|restart|recreate|stop|status|logs|exec ..."
end
exec("docker", "compose", "--project-name", project, "--env-file", config,
     "-f", File.join(root, "compose.application.yml"), *args)
