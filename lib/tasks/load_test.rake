# Load test helpers for script/load_test.js (k6). Run them on a COPY of the site (staging), never on the live one.
#
#   bin/rails "load_test:setup[500,12]"   # 500 test students (all Warrior, UPSC Prelims) for test id 12;
#                                          # writes their API tokens to tmp/load_test_tokens.json
#   bin/rails load_test:cleanup            # deletes those students and everything they did
#
# Signing in 500 times from one machine would hit the login rate limit, so the tokens are made here instead.
namespace :load_test do
  LOAD_TEST_EMAIL = "loadtest%d@example.com".freeze

  desc "Create N load-test students and their API tokens for one test"
  task :setup, [:count, :test_id] => :environment do |_, args|
    abort "Refusing to run on production. Use a staging copy (or set LOAD_TEST_OK=1 if you are sure)." if Rails.env.production? && ENV["LOAD_TEST_OK"] != "1"
    count = (args[:count] || 500).to_i
    test = TestSession.find(args[:test_id] || abort("Give the test id: bin/rails \"load_test:setup[500,TEST_ID]\""))

    tokens = (1..count).map do |i|
      user = User.find_or_initialize_by(email_address: format(LOAD_TEST_EMAIL, i))
      user.assign_attributes(name: "Load Test #{i}", role: :student, date_of_birth: Date.new(2000, 1, 1),
                             membership_tier: "warrior", email_confirmed_at: Time.current)
      user.password = "#{SecureRandom.alphanumeric(20)}9a" if user.new_record?
      user.save!
      user.replace_exams!([test.exam_type]) if user.exam_codes.empty?
      TestPinEntry.find_or_create_by!(test_session: test, user: user) if test.pin_required?
      user.sessions.create!(user_agent: "load test", ip_address: "127.0.0.1").signed_id(purpose: Api::V1::BaseController::TOKEN_PURPOSE)
    end

    path = Rails.root.join("tmp/load_test_tokens.json")
    File.write(path, JSON.pretty_generate(test_id: test.id, tokens: tokens))
    puts "#{count} students ready for test ##{test.id} (#{test.title}). Tokens: #{path}"
  end

  desc "Delete the load-test students and everything they did"
  task cleanup: :environment do
    abort "Refusing to run on production without LOAD_TEST_OK=1" if Rails.env.production? && ENV["LOAD_TEST_OK"] != "1"
    users = User.where("email_address LIKE ?", "loadtest%@example.com")
    n = users.count
    users.find_each(&:destroy!)
    TestSession.clear_shared!
    puts "Deleted #{n} load-test students."
  end
end
