# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_13_150000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "meeting_types", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", limit: 100, null: false
    t.text "description", default: "", null: false
    t.integer "duration_minutes", null: false
    t.string "slug", limit: 80, null: false
    t.boolean "published", default: false, null: false
    t.string "initial_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["initial_key"], name: "index_meeting_types_on_initial_key", unique: true
    t.index ["slug"], name: "index_meeting_types_on_slug", unique: true
    t.check_constraint "duration_minutes >= 1 AND duration_minutes <= 540", name: "meeting_duration_range"
  end

  create_table "occupancies", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false

    t.check_constraint "ends_at > starts_at", name: "occupancy_positive_interval"
    t.exclusion_constraint "tsrange(starts_at, ends_at, '[)'::text) WITH &&", using: :gist, name: "occupancies_do_not_overlap"
  end
end
