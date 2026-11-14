# frozen_string_literal: true

require "net/http"
require "open3"
require "securerandom"
require "socket"
require "timeout"

root = File.expand_path("..", __dir__)
suffix = SecureRandom.hex(6)
image = "calendar-no-database-test:#{suffix}"
container = "calendar-no-database-test-#{suffix}"
container_created = false

run = lambda do |*command|
  stdout, stderr, status = Open3.capture3(*command, chdir: root)
  abort "#{command.join(" ")} failed:\n#{stdout}\n#{stderr}" unless status.success?
  stdout.strip
end

port = TCPServer.open("127.0.0.1", 0) { |server| server.addr[1] }
begin
  run.call("docker", "build", "--tag", image, ".")
  run.call("docker", "run", "--detach", "--name", container, "--publish", "127.0.0.1:#{port}:8080",
           "--env", "PORT=8080", image)
  container_created = true

  http = Net::HTTP.new("127.0.0.1", port)
  http.open_timeout = 2
  http.read_timeout = 2
  response = Timeout.timeout(90) do
    loop do
      begin
        response = http.get("/")
        break response
      rescue Errno::ECONNREFUSED, IOError, Net::OpenTimeout, Net::ReadTimeout
        sleep 0.5
      end
    end
  end

  abort "Root did not return HTTP 200" unless response.code == "200"
  abort "Root did not explain the missing PostgreSQL configuration" unless
    response.body.include?("PostgreSQL is required") && response.body.include?("DATABASE_URL")

  not_found = http.get("/api")
  abort "An API-looking path was not rejected in diagnostic mode" unless not_found.code == "404"

  puts "Docker image starts on PORT without DATABASE_URL, shows the database notice at /, and returns 404 for /api"
ensure
  if container_created
    Open3.capture3("docker", "rm", "--force", container, chdir: root)
  end
  Open3.capture3("docker", "image", "rm", image, chdir: root)
end
