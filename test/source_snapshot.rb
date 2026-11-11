require "open3"
require "digest"

def snapshot
  paths, status = Open3.capture2("git", "ls-files", "--cached", "--others", "--exclude-standard", "-z", chdir: ROOT)
  assert(status.success?, "cannot enumerate source files")
  files = paths.split("\0").to_h { |path| [path, Digest::SHA256.file(File.join(ROOT, path)).hexdigest] }
  index, status = Open3.capture2("git", "ls-files", "--stage", "-z", chdir: ROOT)
  assert(status.success?, "cannot inspect index")
  [files, index]
end
