# frozen_string_literal: true

require "fileutils"
require "securerandom"

root = File.expand_path("..", __dir__)
destination = File.join(root, ".services", "docker-clean-#{SecureRandom.hex(6)}")
FileUtils.mkdir_p(destination, mode: 0o700)
archive = "#{destination}.tar"
system("git", "-C", root, "archive", "--format=tar", "--output=#{archive}", "HEAD", exception: true)
system("tar", "-xf", archive, "-C", destination, exception: true)
File.delete(archive)
abort "Export unexpectedly contains local dependencies/configuration" if
  %w[mise.local.toml .services frontend/node_modules backend/.bundle].any? { |entry| File.exist?(File.join(destination, entry)) }
puts "Clean tracked-files-only checkout: #{destination}"
begin
  Dir.chdir(destination) do
    system("ruby", "scripts/docker.rb", "setup", exception: true)
    system("ruby", "scripts/docker.rb", "build", exception: true)
    system("ruby", "scripts/docker.rb", "up", exception: true)
  end
  system({ "CALENDAR_DOCKER_CHECKOUT" => destination }, "node", File.join(root, "test/docker_acceptance.mjs"), exception: true)
ensure
  Dir.chdir(destination) do
    system("ruby", "scripts/docker.rb", "stop", exception: true) if File.file?(".services/docker.env")
  end
  puts "Retained checkout, private configuration and persistent Docker volumes: #{destination}"
end
