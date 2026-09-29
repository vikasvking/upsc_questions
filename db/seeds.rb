# Creates the first admin and teacher accounts, and the default price plans.
# Run:  ADMIN_EMAIL=you@site.com ADMIN_PASSWORD='Strong-pass-2026' ADMIN_NAME='Your Name' \
#       TEACHER_EMAIL=t@site.com TEACHER_PASSWORD='Another-pass-2026' TEACHER_NAME='Teacher Name' bin/rails db:seed
# Safe to run more than once: existing accounts only get their role updated, existing plans are left alone.

{ "ADMIN" => :admin, "TEACHER" => :teacher }.each do |prefix, role|
  email    = ENV["#{prefix}_EMAIL"]
  password = ENV["#{prefix}_PASSWORD"]
  next if email.blank?

  user = User.find_or_initialize_by(email_address: email.strip.downcase)
  if user.new_record?
    raise "#{prefix}_PASSWORD is required to create #{email}" if password.blank?
    user.password = password
    user.name = ENV["#{prefix}_NAME"].presence || prefix.capitalize
  end
  user.role = role
  user.approved_at ||= Time.current if role == :teacher
  user.save!
  user.replace_subjects!(["General"]) if role == :teacher && user.subject_names.empty?
  puts "#{role}: #{user.email_address}"
end

# Starting prices (change them any time in Admin → Plans)
[
  { name: "Starter",  kind: "school", price_month_inr: 1_999,  price_year_inr: 19_990,  max_students: 100,   max_teachers: 5,  max_tests_per_month: 8,  member_tier: "plus", member_max_exams: 2, position: 1 },
  { name: "Standard", kind: "school", price_month_inr: 4_999,  price_year_inr: 49_990,  max_students: 300,   max_teachers: 15, max_tests_per_month: 20, member_tier: "plus", member_max_exams: 2, position: 2 },
  { name: "Premium",  kind: "school", price_month_inr: 12_999, price_year_inr: 129_990, max_students: 1_000, max_teachers: 40, max_tests_per_month: 60, member_tier: "plus", member_max_exams: 3, position: 3 },
  { name: "Warrior",  kind: "student", price_month_inr: 49, price_year_inr: 399, price_month_upgrade_inr: 29, member_tier: "warrior", position: 1 }
].each do |attrs|
  plan = Plan.find_or_create_by!(name: attrs[:name]) { |p| p.assign_attributes(attrs) }
  puts "plan: #{plan.name} (₹#{plan.price_month_inr}/month)"
end
