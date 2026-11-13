class CreateAdminAuthentication < ActiveRecord::Migration[8.1]
  def change
    create_table :administrators do |t|
      t.string :username, null: false
      t.string :password_digest, null: false
    end
    add_check_constraint :administrators, "id = 1", name: "single_administrator"

    create_table :admin_sessions do |t|
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
    end
    add_index :admin_sessions, :token_digest, unique: true

    create_table :admin_login_limits, id: false do |t|
      t.string :key, null: false, primary_key: true
      t.datetime :started_at, null: false
      t.integer :attempts, null: false, default: 0
    end
  end
end
