# Everything the signup page collects. Adults get an account straight away;
# under-18 students get a PendingSignup and the account is created once the parent's code is entered.
class SignupForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  ROLES = %w[student teacher].freeze

  attribute :role, :string, default: "student"
  attribute :name, :string
  attribute :email_address, :string
  attribute :password, :string
  attribute :password_confirmation, :string
  attribute :date_of_birth, :date
  attribute :parent_email, :string
  attribute :parent_phone, :string
  attribute :bio, :string
  attribute :subjects, :string
  attribute :institution_id, :string # an id, "new" (teacher adds one) or blank
  attribute :join_code, :string
  attribute :new_institution_name, :string
  attribute :new_institution_kind, :string, default: "coaching"
  attribute :new_institution_city, :string
  attr_accessor :exam_codes

  attr_reader :user, :pending_signup, :parent_code

  validates :role, inclusion: { in: ROLES }
  validates :name, presence: true
  validate  :user_is_valid
  validate  :student_details, if: :student?
  validate  :teacher_details, if: :teacher?
  validate  :institution_choice

  def student? = role == "student"
  def teacher? = role == "teacher"
  def exam_codes = Array(@exam_codes).filter_map { |c| Exam.normalize(c) }.uniq
  def subject_list = subjects.to_s.split(",").map(&:squish).compact_blank.uniq(&:downcase)
  def minor? = student? && build_user.minor?

  # Adult: creates and returns the user. Minor: creates a PendingSignup (see #pending_signup) and returns nil.
  def save
    return false unless valid?

    if minor?
      @pending_signup, @parent_code = PendingSignup.start!(email_address: email_address, data: pending_data)
      true
    else
      User.transaction do
        @user = build_user
        @user.save!
        self.class.finish_setup!(@user, exam_codes: exam_codes, subjects: subject_list, institution: institution_data)
      end
      true
    end
  end

  # Shared with ConsentsController, which creates the account once the parent's code is entered
  def self.finish_setup!(user, exam_codes: [], subjects: [], institution: {})
    user.replace_exams!(exam_codes) if user.student? && exam_codes.any?
    user.replace_subjects!(subjects) if user.teacher? && subjects.any?
    join_institution!(user, institution.with_indifferent_access) if institution.present?
  end

  # With the right join code (or when a teacher registers a new institution) the membership is approved at once;
  # otherwise it waits for a teacher of that institution to approve it.
  def self.join_institution!(user, data)
    if data[:id].present?
      inst = Institution.find(data[:id])
      approved = data[:join_code].present? && data[:join_code].to_s.strip.upcase == inst.join_code
      m = user.memberships.find_or_create_by!(institution: inst)
      m.approve! if approved && m.pending?
    elsif data[:new_name].present?
      inst = Institution.create!(name: data[:new_name], kind: data[:new_kind], city: data[:new_city], created_by: user)
      user.memberships.create!(institution: inst).approve!
    end
  end

  private

  def build_user
    @built_user ||= User.new(role: ROLES.include?(role) ? role : "student", name: name, email_address: email_address,
                             password: password, password_confirmation: password_confirmation,
                             date_of_birth: student? ? date_of_birth : nil, bio: teacher? ? bio : nil)
  end

  def existing_institution? = institution_id.present? && institution_id != "new"

  def institution_data
    if existing_institution?
      { id: institution_id, join_code: join_code }
    elsif institution_id == "new" && teacher? && new_institution_name.present?
      { new_name: new_institution_name, new_kind: new_institution_kind, new_city: new_institution_city }
    else
      {}
    end
  end

  # Everything needed to create the account later; the password is kept only as a bcrypt digest
  def pending_data
    {
      "name" => name, "role" => "student", "date_of_birth" => date_of_birth.iso8601,
      "password_digest" => BCrypt::Password.create(password).to_s,
      "exam_codes" => exam_codes, "institution" => institution_data.transform_keys(&:to_s),
      "parent_email" => parent_email.to_s.strip.downcase, "parent_phone" => parent_phone
    }
  end

  def user_is_valid
    u = build_user
    return if u.valid?
    u.errors.each { |e| errors.add(e.attribute == :base ? :base : e.attribute, e.message) }
  end

  def student_details
    errors.add(:date_of_birth, "is required") if date_of_birth.blank?
    errors.add(:base, "Pick at least one exam you are preparing for") if exam_codes.empty?
    return unless date_of_birth.present? && build_user.minor?

    consent = GuardianConsent.new(parent_email: parent_email, parent_phone: parent_phone,
                                  consent_version: GuardianConsent::VERSION, consented_at: Time.current)
    consent.valid?
    %i[parent_email parent_phone].each { |f| consent.errors[f].each { |m| errors.add(f, m) } }
    if parent_email.to_s.strip.casecmp?(email_address.to_s.strip)
      errors.add(:parent_email, "must be your parent's email, not yours")
    end
    unless Mailing.enabled? || Rails.env.development?
      errors.add(:base, "Sign-up for students under 18 is paused until email sending is set up, because we must email your parent a consent code. Please try again later.")
    end
  end

  def teacher_details
    errors.add(:base, "Add at least one subject you teach") if subject_list.empty?
  end

  def institution_choice
    if existing_institution?
      inst = Institution.find_by(id: institution_id)
      return errors.add(:institution_id, "was not found") unless inst
      if join_code.present? && join_code.to_s.strip.upcase != inst.join_code
        errors.add(:join_code, "does not match #{inst.name}. Leave it empty to ask a teacher there to approve you.")
      end
    elsif institution_id == "new" && teacher?
      return errors.add(:new_institution_name, "is required") if new_institution_name.blank?
      inst = Institution.new(name: new_institution_name, kind: new_institution_kind, city: new_institution_city, join_code: "TEMPCODE")
      inst.valid?
      inst.errors.each { |e| errors.add(:"new_institution_#{e.attribute}", e.message) unless e.attribute == :join_code }
    end
  end
end
