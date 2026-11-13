namespace :admin do
  desc "Rotate the administrator password from ADMIN_NEW_PASSWORD and revoke all sessions"
  task change_password: :environment do
    password = ENV.delete("ADMIN_NEW_PASSWORD").to_s
    abort "Set ADMIN_NEW_PASSWORD (at least 12 characters)" if password.length < 12
    admin = Administrator.configured
    abort "Configure ADMIN_USERNAME and ADMIN_PASSWORD first" unless admin
    admin.rotate_password!(password)
    puts "Administrator password changed; all sessions revoked."
  end
end
