# Admin → Messages: what visitors sent from the home page contact form. Admins only.
class Admin::ContactMessagesController < Admin::BaseController
  self.admin_area = :admin_only

  def index
    @status = params[:status].presence_in(ContactMessage::STATUSES.keys + ["all"]) || "new"
    scope = ContactMessage.includes(:handled_by).newest_first
    scope = scope.where(status: @status) unless @status == "all"
    @counts = ContactMessage.group(:status).count
    @messages = paginate(scope)
  end

  # Mark a message done (answered) or new again
  def update
    message = ContactMessage.find(params[:id])
    done = params[:status] == "done"
    message.update!(status: done ? "done" : "new", handled_by: done ? Current.user : nil, handled_at: done ? Time.current : nil)
    log!("update_contact_message", record: message, label: "#{message.name} <#{message.email}>", details: { "status" => message.status })
    redirect_back_or_to admin_contact_messages_path, notice: done ? "Marked as done." : "Moved back to new."
  end
end
