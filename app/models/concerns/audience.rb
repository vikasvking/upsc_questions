# Who can see a test or a question:
#   public      -> everyone
#   institution -> approved members of one school/coaching (the teacher's)
#   selected    -> students, institutions and batches the teacher picked (AudienceGrant)
# The owner and admins/sub-admins always see it.
module Audience
  extend ActiveSupport::Concern

  VISIBILITIES = {
    "public"      => "🌐 Everyone",
    "institution" => "🏫 My school or coaching",
    "selected"    => "👥 Selected students, institutions or batches"
  }.freeze

  included do
    belongs_to :institution, optional: true
    has_many :audience_grants, as: :item, dependent: :delete_all

    validates :visibility, inclusion: { in: VISIBILITIES.keys }
    validates :institution, presence: { message: "must be chosen for \"my school or coaching\"" }, if: -> { visibility == "institution" }
  end

  class_methods do
    def visible_to(user)
      return where(visibility: "public") if user.nil?
      return all if user.staff?

      institution_ids = user.approved_memberships.pluck(:institution_id)
      batch_ids = BatchMember.where(user_id: user.id).pluck(:batch_id)
      granted = AudienceGrant.where(item_type: name).where(
        "(grantee_type = 'User' AND grantee_id = :user) OR (grantee_type = 'Institution' AND grantee_id IN (:institutions)) OR (grantee_type = 'Batch' AND grantee_id IN (:batches))",
        user: user.id, institutions: institution_ids.presence || [0], batches: batch_ids.presence || [0]
      )

      where(visibility: "public")
        .or(where(visibility: "institution", institution_id: institution_ids))
        .or(where(visibility: "selected", id: granted.select(:item_id)))
        .or(where(user_id: user.id))
    end
  end

  def everyone? = visibility == "public"

  def visible_to?(user)
    self.class.visible_to(user).exists?(id)
  end

  def granted_ids(type) = audience_grants.select { |g| g.grantee_type == type }.map(&:grantee_id)

  # Replaces the "selected" audience
  def replace_audience!(user_ids: [], institution_ids: [], batch_ids: [])
    wanted = { "User" => user_ids, "Institution" => institution_ids, "Batch" => batch_ids }
               .flat_map { |type, ids| Array(ids).compact_blank.map(&:to_i).uniq.map { |id| [type, id] } }
    transaction do
      audience_grants.each { |g| g.delete unless wanted.include?([g.grantee_type, g.grantee_id]) }
      existing = audience_grants.reload.map { |g| [g.grantee_type, g.grantee_id] }
      (wanted - existing).each { |type, id| audience_grants.create!(grantee_type: type, grantee_id: id) }
    end
    audience_grants.reset
  end

  # "Everyone", "Sunrise Academy", or "3 students, 1 batch"
  def audience_label
    case visibility
    when "public" then "Everyone"
    when "institution" then institution ? "#{institution.name} only" : "One institution"
    else
      counts = audience_grants.group_by(&:grantee_type).transform_values(&:size)
      parts = [["User", "student"], ["Institution", "institution"], ["Batch", "batch"]].filter_map do |type, word|
        n = counts[type].to_i
        "#{n} #{n == 1 ? word : word.pluralize}" if n.positive?
      end
      parts.any? ? "Only #{parts.to_sentence}" : "Nobody selected yet"
    end
  end
end
