root = File.expand_path("..", __dir__)
def install(*command, directory:, env: {})
  abort "Install failed: #{command.join(' ')}" unless system(env, *command, chdir: directory)
end

install("bundle", "_4.0.22_", "install", directory: File.join(root, "backend"), env: { "BUNDLE_FROZEN" => "true" })
%w[contracts frontend].each do |name|
  install("npm", "ci", directory: File.join(root, name))
end
# T9 owns tooling; once present it is an independent locked npm project too.
if File.directory?(File.join(root, "tooling"))
  install("npm", "ci", directory: File.join(root, "tooling"))
end
install("node", "node_modules/playwright/cli.js", "install", "chromium", directory: File.join(root, "frontend"))
