# Invoked under the backend bundle so CI needs no PostgreSQL CLI or Docker daemon.
require "pg"

action, database = ARGV
abort "invalid temporary database name" unless database&.match?(/\Asmoke_[a-f0-9]{20}\z/)
PG.connect(ENV.fetch("SMOKE_SERVICE_URL"), connect_timeout: 5) do |connection|
  connection.exec("SET statement_timeout = '10s'")
  case action
  when "create"
    connection.exec("CREATE DATABASE #{connection.quote_ident(database)}")
  when "drop"
    connection.exec("DROP DATABASE #{connection.quote_ident(database)} WITH (FORCE)")
  when "assert-absent"
    abort "temporary database survived" unless connection.exec_params("SELECT 1 FROM pg_database WHERE datname = $1", [database]).ntuples.zero?
  else
    abort "unknown database operation"
  end
end
