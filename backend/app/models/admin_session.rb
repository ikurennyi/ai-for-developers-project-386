class AdminSession < ApplicationRecord
  def self.token_digest(token)
    Digest::SHA256.hexdigest(token)
  end
end
