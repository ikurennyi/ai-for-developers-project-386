# Dedicated checkout only: requires no previous lifecycle state or volume.
require "open3"
require "json"
require "socket"

root = File.expand_path("..", __dir__)
state = File.join(root, ".services/environment.json")
abort "use a fresh dedicated checkout without lifecycle state" if File.exist?(state)

def capture(root, env, *command)
  output, status = Open3.capture2e(env, *command, chdir: root)
  raise output unless status.success?
  output
end

template = capture(root, {}, "ruby", "scripts/services.rb", "dev:env")
env = template.scan(/^([A-Z_]+) = "([^"]+)"$/).to_h
sockets = 3.times.map { TCPServer.new("127.0.0.1", 0) }
ports = sockets.map { |socket| socket.addr[1].to_s }
sockets.each(&:close)
env["BACKEND_PORT"], env["FRONTEND_PORT"], env["POSTGRES_PORT"] = ports
%w[DATABASE_URL TEST_DATABASE_URL].each { |key| env[key] = env.fetch(key).sub(":5501/", ":#{ports.last}/") }
volume = "#{env.fetch('COMPOSE_PROJECT_NAME')}_postgres-data"
_, status = Open3.capture2e("docker", "volume", "inspect", volume)
abort "fresh-volume probe refuses an existing volume" if status.success?

begin
  puts capture(root, env, "mise", "run", "db:up")
  # No retry: the first connection after db:up must reach the final TCP server.
  puts capture(File.join(root, "backend"), env, "bundle", "exec", "ruby", "-rpg", "-e",
    '25.times { PG.connect(ENV.fetch("DATABASE_URL"), connect_timeout: 2) { |db| raise "SQL failed" unless db.exec("SELECT 1").getvalue(0, 0) == "1" }; sleep 0.05 }; puts "Fresh-volume immediate TCP SQL verified"')
  puts capture(root, env, "mise", "run", "db:prepare")
ensure
  puts capture(root, env, "mise", "run", "dev:stop") if File.exist?(state)
end
info = JSON.parse(capture(root, env, "docker", "inspect", "#{env.fetch('COMPOSE_PROJECT_NAME')}-postgres-1")).first
raise "PostgreSQL survived stop" if info.fetch("State").fetch("Running")
capture(root, env, "docker", "volume", "inspect", volume)
puts "Fresh-volume readiness, immediate preparation and data-preserving stop passed"
