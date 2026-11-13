class AdminLoginLimit < ApplicationRecord
  self.primary_key = "key"

  # PostgreSQL row locking makes the threshold shared across threads/processes.
  def self.consume(ip)
    key = Digest::SHA256.hexdigest(ip)
    limit = create_or_find_by!(key: key) { |row| row.started_at = Time.current }
    limit.with_lock do
      limit.update!(started_at: Time.current, attempts: 0) if limit.started_at <= 15.minutes.ago
      return [ (limit.started_at + 15.minutes - Time.current).ceil, 1 ].max if limit.attempts >= 10
      limit.increment!(:attempts)
      nil
    end
  end
end
