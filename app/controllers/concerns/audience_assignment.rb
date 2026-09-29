# Reads a "Visible to" section (see shared/_audience_fields) and applies it to a test or question
module AudienceAssignment
  extend ActiveSupport::Concern

  private

  # Adds errors to the record; returns true when the audience is acceptable
  def audience_valid?(record)
    user = Current.user
    if record.visibility == "institution"
      allowed = user.admin? || user.approved_memberships.exists?(institution_id: record.institution_id)
      record.errors.add(:base, "Pick one of your own schools or coachings for \"my school or coaching\"") unless record.institution_id && allowed
    elsif record.visibility == "selected"
      sel = audience_selection(record)
      if sel.values_at(:user_ids, :institution_ids, :batch_ids).all?(&:empty?)
        record.errors.add(:base, "Pick at least one student, school/coaching or batch (or add students by email)")
      end
      school_for_selected_test(record) if record.is_a?(TestSession)
    end
    keep_school = record.visibility == "institution" || (record.visibility == "selected" && record.is_a?(TestSession))
    record.institution_id = nil unless keep_school
    check_test_quota(record) if record.is_a?(TestSession) && record.errors.none?
    record.errors.none?
  end

  # A "selected" test by a teacher of a paying school says which school it is for (it counts toward that school's tests)
  def school_for_selected_test(record)
    user = Current.user
    if record.institution_id.present?
      unless user.admin? || user.approved_memberships.exists?(institution_id: record.institution_id)
        record.errors.add(:base, "Pick one of your own schools or coachings as the school this test is for")
      end
    elsif !user.admin? && user.subscribed_institutions.any?
      record.errors.add(:base, "Pick which of your schools this test is for; it counts toward that school's monthly tests")
    end
  end

  # School tests count toward the school's monthly limit (admins are not limited)
  def check_test_quota(record)
    return if Current.user.admin? || record.visibility == "public" || record.institution_id.blank?
    return unless record.new_record? || record.institution_id_changed?
    problem = Institution.find(record.institution_id).test_quota_problem
    record.errors.add(:base, problem) if problem
  end

  # Saves the selected audience (or clears it when the test/question is no longer "selected")
  def apply_audience!(record)
    sel = record.visibility == "selected" ? audience_selection(record) : { user_ids: [], institution_ids: [], batch_ids: [] }
    record.replace_audience!(**sel.slice(:user_ids, :institution_ids, :batch_ids))
    if sel[:missing_emails].present?
      flash[:alert] = "No student account found for: #{sel[:missing_emails].join(", ")}"
    end
  end

  def audience_selection(record)
    @audience_selection ||= begin
      a = params[:audience] || {}
      user = Current.user
      emails = a[:emails].to_s.split(/[\s,;]+/).map { |e| e.strip.downcase }.compact_blank.uniq
      by_email = User.student.where(email_address: emails).pluck(:email_address, :id).to_h

      picked = Array(a[:user_ids]).compact_blank.map(&:to_i)
      unless user.admin?
        allowed = user.reachable_students.where(id: picked).pluck(:id) | (record.persisted? ? record.granted_ids("User") : [])
        picked &= allowed
      end
      batches = Array(a[:batch_ids]).compact_blank.map(&:to_i)
      batches &= (user.admin? ? Batch.where(id: batches) : user.batches.where(id: batches)).pluck(:id) | (record.persisted? ? record.granted_ids("Batch") : [])

      { user_ids: (picked + by_email.values).uniq,
        institution_ids: Institution.where(id: Array(a[:institution_ids]).compact_blank).pluck(:id),
        batch_ids: batches,
        missing_emails: emails - by_email.keys }
    end
  end
end
