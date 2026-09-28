# Creates the first admin and teacher accounts.
# Run:  ADMIN_EMAIL=you@site.com ADMIN_PASSWORD=secret123 TEACHER_EMAIL=t@site.com TEACHER_PASSWORD=secret123 bin/rails db:seed
# Safe to run more than once: it only updates the role of existing accounts.

{ "ADMIN" => :admin, "TEACHER" => :teacher }.each do |prefix, role|
  email    = ENV["#{prefix}_EMAIL"]
  password = ENV["#{prefix}_PASSWORD"]
  next if email.blank?

  user = User.find_or_initialize_by(email_address: email.strip.downcase)
  if user.new_record?
    raise "#{prefix}_PASSWORD is required to create #{email}" if password.blank?
    user.password = password
  end
  user.role = role
  user.save!
  puts "#{role}: #{user.email_address}"
end
