# One student, institution or batch allowed to see a "selected" test or question
class AudienceGrant < ApplicationRecord
  GRANTEE_TYPES = %w[User Institution Batch].freeze

  belongs_to :item, polymorphic: true
  belongs_to :grantee, polymorphic: true

  validates :grantee_type, inclusion: { in: GRANTEE_TYPES }
end
