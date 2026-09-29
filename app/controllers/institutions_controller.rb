# Teachers: their schools/coachings, join codes and students' requests
class InstitutionsController < ApplicationController
  before_action :require_faculty
  before_action :set_institution, only: :regenerate_code

  def index
    @institutions = Current.user.institutions.ordered.includes(memberships: :user)
    @new_institution = Institution.new(kind: "coaching")
  end

  # POST /institutions -> the teacher adds a school/coaching and becomes its first member
  def create
    @new_institution = Institution.new(params.require(:institution).permit(:name, :kind, :city).merge(created_by: Current.user))
    if @new_institution.save
      Current.user.memberships.create!(institution: @new_institution).approve!(by: Current.user)
      redirect_to institutions_path, notice: "#{@new_institution.name} added. Share its join code with your students."
    else
      @institutions = Current.user.institutions.ordered.includes(memberships: :user)
      render :index, status: :unprocessable_entity
    end
  end

  def regenerate_code
    @institution.regenerate_join_code!
    redirect_to institutions_path, notice: "New join code for #{@institution.name}: #{@institution.join_code}. The old code no longer works."
  end

  private

  def require_faculty
    redirect_to profile_path, alert: "Only teachers manage schools and coachings here." unless Current.user.faculty?
  end

  def set_institution
    @institution = Current.user.institutions.find_by(id: params[:id])
    redirect_to institutions_path, alert: "You are not a teacher at that institution." unless @institution
  end
end
