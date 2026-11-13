class CreateOccupancies < ActiveRecord::Migration[8.1]
  def change
    create_table :occupancies, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      # Rails stores these exact instants as UTC, irrespective of the display zone.
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.timestamps
      t.check_constraint "ends_at > starts_at", name: "occupancy_positive_interval"
      t.exclusion_constraint "tsrange(starts_at, ends_at, '[)') WITH &&",
        using: :gist, name: "occupancies_do_not_overlap"
    end
  end
end
