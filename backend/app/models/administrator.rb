require "openssl"

# A singleton provisioned once from configuration. Rotation never reads the
# initial password again, so restarting with old environment cannot undo it.
class Administrator < ApplicationRecord
  ITERATIONS = 600_000

  def self.configured
    find_by(id: 1) || begin
      username = ENV["ADMIN_USERNAME"]
      password = ENV["ADMIN_PASSWORD"]
      return if username.blank? || password.blank?
      create_or_find_by!(id: 1) do |admin|
        admin.username = username
        admin.password_digest = digest(password)
      end
    end
  end

  def self.digest(password, salt = SecureRandom.hex(16))
    hash = OpenSSL::KDF.pbkdf2_hmac(password, salt: salt, iterations: ITERATIONS, length: 32, hash: "SHA256")
    "#{salt}:#{hash.unpack1('H*')}"
  end

  def authenticates?(username, password)
    # Always run the expensive password comparison, even for an unknown name.
    valid_password = ActiveSupport::SecurityUtils.secure_compare(password_digest, self.class.digest(password, password_digest.split(":").first))
    valid_password & ActiveSupport::SecurityUtils.secure_compare(self.username, username)
  end

  def rotate_password!(password)
    raise ArgumentError, "Password must contain at least 12 characters" if password.length < 12
    with_lock do
      update!(password_digest: self.class.digest(password))
      AdminSession.delete_all
    end
  end
end
