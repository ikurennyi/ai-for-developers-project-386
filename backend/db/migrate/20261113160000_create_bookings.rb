class CreateBookings < ActiveRecord::Migration[8.1]
  def change
    create_table :bookings, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :meeting_type, type: :uuid, null: false, foreign_key: true
      t.references :occupancy, type: :uuid, null: false, foreign_key: true, index: { unique: true }
      t.string :guest_name, limit: 100, null: false
      t.string :guest_email, limit: 254, null: false
      t.text :notes, null: false, default: ""
      t.string :meeting_name, null: false
      t.text :meeting_description, null: false
      t.integer :duration_minutes, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.timestamps
    end
  end
end
