# Password rules for new and changed passwords
module PasswordPolicy
  MIN_LENGTH = 10

  # Very common passwords (and their obvious variants) are refused outright
  COMMON = %w[
    password password1 password12 password123 password1234 passw0rd p@ssw0rd p@ssword
    1234567890 0123456789 123456789 12345678 1234567 123456 qwerty qwerty123 qwertyuiop
    asdfghjkl zxcvbnm abc123 abcd1234 abcdef123 iloveyou iloveyou1 welcome welcome1 welcome123
    admin admin123 administrator letmein monkey dragon sunshine princess football cricket
    india india123 india@123 bharat123 hello123 test1234 test12345 changeme secret123
    upsc12345 upsc@1234 rankwise rankwise123 student123 teacher123
  ].to_set.freeze

  # Messages explaining what is wrong (empty when the password is fine)
  def self.problems(password, email: nil)
    pw = password.to_s
    problems = []
    problems << "must be at least #{MIN_LENGTH} characters" if pw.length < MIN_LENGTH
    problems << "must contain at least one letter and one number" unless pw.match?(/[A-Za-z]/) && pw.match?(/\d/)
    problems << "is too common; choose something harder to guess" if COMMON.include?(pw.downcase)

    local = email.to_s.split("@").first.to_s.downcase
    problems << "must not contain your email name" if local.length >= 4 && pw.downcase.include?(local)
    problems
  end
end
