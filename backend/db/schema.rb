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

ActiveRecord::Schema[8.1].define(version: 2026_11_13_140000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "admin_login_limits", primary_key: "key", id: :string, force: :cascade do |t|
    t.datetime "started_at", null: false
    t.integer "attempts", default: 0, null: false
  end

  create_table "admin_sessions", force: :cascade do |t|
    t.string "token_digest", null: false
    t.datetime "expires_at", null: false
    t.index ["token_digest"], name: "index_admin_sessions_on_token_digest", unique: true
  end

  create_table "administrators", force: :cascade do |t|
    t.string "username", null: false
    t.string "password_digest", null: false
    t.check_constraint "id = 1", name: "single_administrator"
  end
end
