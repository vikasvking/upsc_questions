class User < ApplicationRecord
  # A sub-admin is an approved teacher to whom an admin gave some of these areas.
  # Never delegated: people's accounts, email settings, deleting anything, parents' consent details, the full log.
  ADMIN_AREAS = {
    "approvals"    => "Approve new teachers and join requests at their own schools/coachings",
    "questions"    => "Change any question (no deleting)",
    "tests"        => "Change any test, including locked tests on request (no deleting)",
    "institutions" => "Edit and merge schools/coachings (no deleting)",
    "ratings"      => "Answer reports and hide abusive rating comments"
  }.freeze
  ADULT_AGE = 18

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :user_responses, dependent: :destroy
  has_many :test_attempts, dependent: :destroy
  # A deleted teacher's tests and questions stay (shown under the exam's name)
  has_many :test_sessions, dependent: :nullify
  has_many :questions, dependent: :nullify
  has_many :test_pin_entries, dependent: :delete_all
  has_many :user_exams, dependent: :delete_all
  has_many :teacher_subjects, dependent: :delete_all
  has_many :memberships, dependent: :delete_all
  has_many :approved_memberships, -> { approved }, class_name: "Membership"
  has_many :institutions, through: :approved_memberships
  has_many :guardian_consents, dependent: :delete_all
  has_many :batches, dependent: :destroy                 # a teacher's saved groups
  has_many :batch_members, dependent: :delete_all        # a student's places in batches
  has_many :audience_grants, as: :grantee, dependent: :delete_all
  has_many :ratings, dependent: :delete_all                                   # ratings this student gave
  has_many :received_ratings, as: :rateable, class_name: "Rating", dependent: :delete_all # a teacher's ratings
  has_many :question_reports, dependent: :delete_all

  has_many :attempted_questions, -> { distinct }, through: :user_responses, source: :question
  enum :role, { student: 0, teacher: 1, admin: 2 }, default: :student

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :name, with: ->(v) { v.to_s.squish.presence }
  normalizes :target_exam, with: ->(v) { Exam.normalize(v) }

  validates :email_address, presence: true, uniqueness: true
  validates :name, length: { maximum: 80 }
  validates :bio, length: { maximum: 1000 }
  validates :target_exam, inclusion: { in: Exam.codes }, allow_nil: true
  validates :membership_tier, inclusion: { in: Tiers::NAMES.keys }
  validate  :only_teachers_have_admin_areas
  validate  :password_is_strong, if: -> { password.present? }
  validate  :email_can_receive_mail, if: :will_save_change_to_email_address?
  validate  :birth_date_is_sensible, if: -> { date_of_birth.present? }

  generates_token_for :email_confirmation, expires_in: 3.days do
    email_address
  end

  # ---------- roles ----------

  def approved? = approved_at.present?
  def pending_teacher? = teacher? && !approved?
  def faculty? = (teacher? && approved?) || admin? # can create tests and questions
  def sub_admin? = teacher? && approved? && Array(permissions).any? # a teacher with admin areas
  def staff? = admin? || sub_admin?                                  # can open the admin pages

  # Admins can do everything; sub-admins only the areas they were given
  def can_manage?(area)
    admin? || (sub_admin? && Array(permissions).include?(area.to_s))
  end

  # Institutions whose teachers and join requests this person may approve (nil = all, for admins)
  def approvable_institution_ids
    return nil if admin?
    can_manage?(:approvals) ? approved_memberships.pluck(:institution_id) : []
  end

  def can_approve_at?(institution)
    ids = approvable_institution_ids
    ids.nil? || ids.include?(institution.id)
  end

  def display_name = name.presence || email_address.split("@").first.capitalize

  # ---------- membership tier (students) ----------

  # The student's own tier (paid or set by an admin), until its end date
  def own_tier
    tier_until.nil? || tier_until >= Date.current ? membership_tier : "free"
  end

  def subscribed_institutions = institutions.includes(:plan).select(&:subscribed?)

  # What the student's schools give them while their plans are active
  def school_tier
    subscribed_institutions.map(&:member_tier).compact.max_by { |t| Tiers::RANK[t].to_i }
  end

  # Teachers and admins are never limited
  def tier
    return "warrior" unless student?
    @tier ||= Tiers.higher(own_tier, school_tier || "free")
  end

  def free_tier? = tier == "free"

  # Exams whose public tests and practice this student can use (school tests are always open to them)
  def allowed_exam_codes
    case tier
    when "warrior" then Exam.codes
    when "plus"
      limit = subscribed_institutions.filter_map { |i| i.plan.member_max_exams }.max || Tiers::DEFAULT_PLUS_EXAMS
      exam_codes.first(limit)
    else []
    end
  end

  def reload(*)
    @tier = nil
    super
  end

  # Students a teacher can pick for "selected" tests and batches: those at the teacher's institutions
  def reachable_students
    return User.student if admin?
    User.student.where(id: Membership.approved.where(institution_id: approved_memberships.select(:institution_id)).select(:user_id))
  end

  # ---------- age and parent consent ----------

  def age(on = Date.current)
    return nil unless date_of_birth
    years = on.year - date_of_birth.year
    years -= 1 if on < date_of_birth + years.years
    years
  end

  def minor? = age.present? && age < ADULT_AGE
  def parent_consent? = guardian_consents.exists?
  def needs_parent_consent? = student? && minor? && !parent_consent?

  # ---------- email ----------

  def email_confirmed? = email_confirmed_at.present?

  # Rating needs a confirmed email once email sending is switched on
  def can_rate? = email_confirmed? || !Mailing.enabled?

  # ---------- exams and subjects ----------

  def exam_codes = user_exams.map(&:exam_type) & Exam.codes

  # Replaces a saved student's exams; the first becomes the default for ranks unless the old default is kept
  def replace_exams!(codes)
    codes = Array(codes).filter_map { |c| Exam.normalize(c) }.uniq
    transaction do
      user_exams.where.not(exam_type: codes).delete_all
      (codes - user_exams.reload.map(&:exam_type)).each { |c| user_exams.create!(exam_type: c) }
      update_column(:target_exam, codes.first) unless codes.include?(target_exam)
    end
    user_exams.reset
  end

  def subject_names = teacher_subjects.map(&:name).sort

  # Replaces a saved teacher's subjects ("Physics, Chemistry" or a list)
  def replace_subjects!(names)
    names = Array(names).flat_map { |n| n.to_s.split(",") }.map(&:squish).compact_blank.uniq(&:downcase).first(20)
    transaction do
      teacher_subjects.where.not("lower(name) IN (?)", names.map(&:downcase).presence || [""]).delete_all
      existing = teacher_subjects.reload.map { |s| s.name.downcase }
      names.reject { |n| existing.include?(n.downcase) }.each { |n| teacher_subjects.create!(name: n) }
    end
    teacher_subjects.reset
  end

  # Exams this student has answered questions from, most answered first
  def practised_exam_codes
    user_responses.joins(:question).where.not(questions: { exam_type: [nil, ""] })
                  .group("questions.exam_type").order(Arel.sql("COUNT(*) DESC")).count.keys & Exam.codes
  end

  # The exam used for ranks when none is picked: the first chosen exam, else the most practised, else UPSC Prelims
  def ranking_exam_code
    target_exam.presence || exam_codes.first || practised_exam_codes.first || Exam::DEFAULT.code
  end

  # ---------- profile completeness (checked after login) ----------

  # What is still missing before this account can be used (empty = complete)
  def missing_profile_items
    return [] if admin?

    items = []
    items << "your full name" if name.blank?
    if student?
      items << "your date of birth" if date_of_birth.blank?
      items << "the exams you are preparing for" if exam_codes.empty?
    elsif teacher?
      items << "the subjects you teach" if subject_names.empty?
    end
    items
  end

  private

  def password_is_strong
    PasswordPolicy.problems(password, email: email_address).each { |p| errors.add(:password, p) }
  end

  def email_can_receive_mail
    problem = EmailCheck.problem(email_address)
    errors.add(:email_address, problem) if problem
  end

  def only_teachers_have_admin_areas
    errors.add(:permissions, "can only be given to teachers") if Array(permissions).any? && !teacher?
  end

  def birth_date_is_sensible
    if date_of_birth > Date.current - 5.years
      errors.add(:date_of_birth, "does not look right")
    elsif date_of_birth < Date.current - 100.years
      errors.add(:date_of_birth, "does not look right")
    end
  end
end
