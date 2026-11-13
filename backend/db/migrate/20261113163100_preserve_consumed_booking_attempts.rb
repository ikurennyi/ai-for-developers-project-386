class PreserveConsumedBookingAttempts < ActiveRecord::Migration[8.1]
  def up
    create_table :booking_attempts, primary_key: :token_digest, id: :string do |t|
      t.references :booking, type: :uuid, foreign_key: { on_delete: :nullify }
    end
    execute <<~SQL
      INSERT INTO booking_attempts (token_digest, booking_id)
      SELECT attempt_digest, id FROM bookings WHERE attempt_digest IS NOT NULL
    SQL
    remove_column :bookings, :attempt_digest
  end

  def down
    add_column :bookings, :attempt_digest, :string
    add_index :bookings, :attempt_digest, unique: true
    execute <<~SQL
      UPDATE bookings SET attempt_digest = booking_attempts.token_digest
      FROM booking_attempts WHERE booking_attempts.booking_id = bookings.id
    SQL
    drop_table :booking_attempts
  end
end
