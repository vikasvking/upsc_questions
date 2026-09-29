# A teacher's saved groups of students, used when a test or question is visible to "selected" students
class BatchesController < ApplicationController
  before_action :require_faculty
  before_action :set_batch, only: [:edit, :update, :destroy]

  def index
    @batches = Current.user.batches.ordered.includes(:institution, :students)
  end

  def new
    @batch = Current.user.batches.new
    load_students
  end

  def create
    @batch = Current.user.batches.new(batch_params)
    if valid_institution? && @batch.save
      @batch.replace_students!(student_ids)
      redirect_to batches_path, notice: "Batch “#{@batch.name}” saved with #{@batch.students.count} students.#{missing_note}"
    else
      load_students
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    load_students
  end

  def update
    @batch.assign_attributes(batch_params)
    if valid_institution? && @batch.save
      @batch.replace_students!(student_ids)
      redirect_to batches_path, notice: "Batch “#{@batch.name}” saved with #{@batch.students.count} students.#{missing_note}"
    else
      load_students
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @batch.destroy!
    redirect_to batches_path, notice: "Batch “#{@batch.name}” deleted. Tests shared with it are no longer visible to its students (unless shared another way)."
  end

  private

  def require_faculty
    redirect_to profile_path, alert: "Only teachers can make batches." unless Current.user.faculty?
  end

  def set_batch
    @batch = Current.user.batches.find(params[:id])
  end

  def batch_params
    params.require(:batch).permit(:name, :institution_id)
  end

  def valid_institution?
    return true if @batch.institution_id.blank? || Current.user.approved_memberships.exists?(institution_id: @batch.institution_id)
    @batch.errors.add(:institution, "must be one of your schools or coachings")
    false
  end

  # Picked students (only those at the teacher's institutions or already in the batch) plus students added by email
  def student_ids
    picked = Array(params.dig(:batch, :student_ids)).compact_blank.map(&:to_i)
    allowed = Current.user.reachable_students.where(id: picked).pluck(:id) | (@batch.persisted? ? @batch.batch_members.pluck(:user_id) : [])
    (picked & allowed) + by_email.values
  end

  def emails
    params.dig(:batch, :emails).to_s.split(/[\s,;]+/).map { |e| e.strip.downcase }.compact_blank.uniq
  end

  def by_email
    @by_email ||= User.student.where(email_address: emails).pluck(:email_address, :id).to_h
  end

  def missing_note
    missing = emails - by_email.keys
    missing.any? ? " No student account for: #{missing.join(", ")}." : ""
  end

  def load_students
    in_batch = @batch.persisted? ? @batch.students.to_a : []
    @students = (Current.user.reachable_students.order(:name, :email_address).limit(500).to_a | in_batch)
    @member_ids = params.dig(:batch, :student_ids) ? Array(params.dig(:batch, :student_ids)).map(&:to_i) : in_batch.map(&:id)
  end
end
