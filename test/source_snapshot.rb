require "open3"
require "digest"

def snapshot
  paths, status = Open3.capture2("git", "ls-files", "--cached", "--others", "--exclude-standard", "-z", chdir: ROOT)
  assert(status.success?, "cannot enumerate source files")
  files = paths.split("\0").to_h do |path|
    absolute = File.join(ROOT, path)
    # Snapshot the link itself, not a directory (or out-of-checkout target).
    digest = File.symlink?(absolute) ? Digest::SHA256.hexdigest(File.readlink(absolute)) : Digest::SHA256.file(absolute).hexdigest
    [path, digest]
  end
  index, status = Open3.capture2("git", "ls-files", "--stage", "-z", chdir: ROOT)
  assert(status.success?, "cannot inspect index")
  [files, index]
end
