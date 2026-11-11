root = File.expand_path("..", __dir__)
gates = %w[contracts:check backend:lint frontend:lint frontend:format frontend:typecheck backend:test frontend:test smoke frontend:build]
gates.each do |gate|
  puts "CHECK_GATE #{gate}"
  $stdout.flush
  abort "Check failed: #{gate}" unless system("mise", "run", gate, chdir: root)
end
puts "All mandatory checks passed"
