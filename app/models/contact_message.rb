# A message sent from the contact form on the home page (custom plans, questions...).
# Saved here for Admin → Messages and emailed to every admin (ContactMailer).
class ContactMessage < ApplicationRecord
  TOPICS = {
    "custom_plan" => "Custom plan",
    "school_plan" => "School or coaching plan",
    "question"    => "Question",
    "other"       => "Something else"
  }.freeze
  STATUSES = { "new" => "New", "done" => "Done" }.freeze

  belongs_to :handled_by, class_name: "User", optional: true

  normalizes :name, :organisation, with: ->(v) { v.to_s.squish.presence }
  normalizes :email, with: ->(v) { v.to_s.strip.downcase }
  normalizes :message, with: ->(v) { v.to_s.strip }
  normalizes :phone, with: ->(v) { v.to_s.gsub(/[^\d+\- ]/, "").squish.presence }

  validates :name, presence: true, length: { maximum: 100 }
  validates :email, presence: true, length: { maximum: 254 }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :phone, length: { maximum: 20 }, allow_blank: true
  validates :organisation, length: { maximum: 150 }, allow_blank: true
  validates :topic, inclusion: { in: TOPICS.keys }
  validates :message, presence: true, length: { maximum: 3000 }
  validates :status, inclusion: { in: STATUSES.keys }

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }
  scope :unread, -> { where(status: "new") }

  def topic_label = TOPICS.fetch(topic, topic.to_s.humanize)
  def done? = status == "done"
end
