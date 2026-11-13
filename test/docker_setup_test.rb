# frozen_string_literal: true

require "fileutils"
require "open3"
require "socket"
require "tmpdir"

# CLI seam: no fake Docker commands, only the actual setup boundary in a private
# checkout-shaped directory. Runtime persistence uses the real Docker acceptance.
root = File.expand_path("..", __dir__)
FileUtils.mkdir_p(File.join(root, ".services"), mode: 0o700)
Dir.mktmpdir("docker-setup-", File.join(root, ".services")) do |directory|
  FileUtils.mkdir_p(File.join(directory, "scripts"))
  FileUtils.cp(File.join(root, "scripts/docker.rb"), File.join(directory, "scripts/docker.rb"))
  run = lambda do |port|
    Open3.capture3({ "HTTPS_PORT" => port.to_s }, "ruby", "scripts/docker.rb", "setup", chdir: directory)
  end
  _, _, invalid = run.call(80)
  abort "Privileged port unexpectedly accepted" if invalid.success?
  TCPServer.open("127.0.0.1", 0) do |server|
    _, _, occupied = run.call(server.addr[1])
    abort "Occupied port unexpectedly accepted" if occupied.success?
  end
  abort "Failed setup wrote credentials" if File.exist?(File.join(directory, ".services/docker.env"))
  port = TCPServer.open("127.0.0.1", 0) { |server| server.addr[1] }
  _, _, success = run.call(port)
  abort "Setup failed" unless success.success?
  config = File.join(directory, ".services/docker.env")
  contents = File.read(config)
  abort "Credentials are not private" unless (File.stat(config).mode & 0o777) == 0o600
  abort "Setup omitted unique credentials" unless contents.match?(/^ADMIN_PASSWORD=[0-9a-f]{48}$/) &&
    contents.match?(/^POSTGRES_PASSWORD=[0-9a-f]{64}$/) &&
    contents.match?(/^SECRET_KEY_BASE=[0-9a-f]{128}$/)
  _, _, repeated = run.call(port)
  abort "Repeated setup overwrote configuration" if repeated.success? || File.read(config) != contents
  puts "Setup rejects invalid/occupied ports, creates private random credentials, and never overwrites configuration"
end
