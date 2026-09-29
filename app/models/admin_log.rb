# What admins changed, when and why (shown at /admin/logs)
class AdminLog < ApplicationRecord
  belongs_to :admin, class_name: "User", optional: true

  validates :admin_email, :action, presence: true

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  LABELS = {
    "create_user" => "Created account", "update_user" => "Changed account", "delete_user" => "Deleted account",
    "create_question" => "Added question", "update_question" => "Changed question", "delete_question" => "Deleted question",
    "create_test" => "Created test", "update_test" => "Changed test", "update_locked_test" => "Changed a locked test",
    "delete_test" => "Deleted test", "approve_teacher" => "Approved teacher",
    "create_institution" => "Added institution", "update_institution" => "Changed institution",
    "delete_institution" => "Deleted institution", "merge_institution" => "Merged institutions",
    "update_mail_settings" => "Changed email settings"
  }.freeze

  def self.record!(admin:, action:, record: nil, label: nil, reason: nil, details: {})
    create!(admin: admin, admin_email: admin.email_address, action: action,
            record_type: record&.class&.name, record_id: record&.id,
            record_label: label.to_s.truncate(200).presence, reason: reason.presence, details: details)
  end

  def action_label = LABELS.fetch(action, action.humanize)
end
