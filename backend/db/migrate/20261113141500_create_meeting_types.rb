class CreateMeetingTypes < ActiveRecord::Migration[8.1]
  def change
    create_table :meeting_types, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :name, null: false, limit: 100
      t.text :description, null: false, default: ""
      t.integer :duration_minutes, null: false
      t.string :slug, null: false, limit: 80
      t.boolean :published, null: false, default: false
      t.string :initial_key
      t.timestamps
    end
    add_index :meeting_types, :slug, unique: true
    add_index :meeting_types, :initial_key, unique: true
    add_check_constraint :meeting_types, "duration_minutes BETWEEN 1 AND 540", name: "meeting_duration_range"
  end
end
