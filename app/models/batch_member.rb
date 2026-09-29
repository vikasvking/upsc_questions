class BatchMember < ApplicationRecord
  belongs_to :batch
  belongs_to :user
  validates :user_id, uniqueness: { scope: :batch_id }
end
