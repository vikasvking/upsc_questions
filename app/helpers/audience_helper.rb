module AudienceHelper
  Choices = Struct.new(:own_institutions, :all_institutions, :students, :batches, keyword_init: true)

  # What the current teacher (or admin) can pick on a "Visible to" section
  def audience_choices(record)
    user = Current.user
    own = user.staff? ? Institution.ordered.to_a : user.institutions.ordered.to_a
    own |= [record.institution] if record.institution

    granted_students = record.persisted? ? User.where(id: record.granted_ids("User")).to_a : []
    students = (user.reachable_students.order(:name, :email_address).limit(300).to_a | granted_students)

    batches = user.staff? ? Batch.ordered.includes(:user).to_a : user.batches.ordered.to_a
    batches |= Batch.where(id: record.granted_ids("Batch")).to_a if record.persisted?

    Choices.new(own_institutions: own, all_institutions: Institution.ordered.to_a, students: students, batches: batches)
  end

  # Small chip for cards and lists when something is not visible to everyone
  def audience_chip(record)
    return if record.everyone?
    tag.span("#{record.visibility == "institution" ? "🏫" : "👥"} #{record.audience_label}",
             class: "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium bg-violet-50 text-violet-700 dark:bg-violet-950/40 dark:text-violet-300")
  end
end
