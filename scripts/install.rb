root = File.expand_path("..", __dir__)
def install(*command, directory:, env: {})
  abort "Install failed: #{command.join(' ')}" unless system(env, *command, chdir: directory)
end

install("bundle", "_4.0.22_", "install", directory: File.join(root, "backend"), env: { "BUNDLE_FROZEN" => "true" })
%w[contracts frontend tooling].each do |name|
  install("npm", "ci", directory: File.join(root, name))
end
install("node", "node_modules/playwright/cli.js", "install", "chromium", directory: File.join(root, "frontend"))
