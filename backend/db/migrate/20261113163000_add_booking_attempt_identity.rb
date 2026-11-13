class AddBookingAttemptIdentity < ActiveRecord::Migration[8.1]
  def change
    add_column :bookings, :attempt_digest, :string
    add_index :bookings, :attempt_digest, unique: true
  end
end
