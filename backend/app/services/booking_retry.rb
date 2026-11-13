class BookingRetry
  def self.valid?(token)
    token.is_a?(String) && token.match?(/\A[0-9a-f]{64}\z/)
  end

  def self.lock(token)
    return unless valid?(token)
    digest = Digest::SHA256.hexdigest(token)
    # A transaction-scoped PostgreSQL lock serializes the same capability even
    # before any record exists, across processes. Hash collisions only wait.
    key = digest[0, 16].to_i(16) - (2**63)
    Booking.connection.execute("SELECT pg_advisory_xact_lock(#{key})")
    digest
  end
end
