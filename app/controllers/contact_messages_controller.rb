# The contact form in the home page footer. It is open only while email is on (Admin → Email):
# each message is saved for Admin → Messages and emailed to every admin.
class ContactMessagesController < ApplicationController
  include HomePage
  allow_unauthenticated_access only: :create

  rate_limit to: 5, within: 10.minutes, only: :create,
             with: -> { redirect_to root_path(anchor: "contact"), alert: "Too many messages. Please try again in a few minutes." }

  def create
    unless Mailing.enabled?
      return redirect_to(root_path(anchor: "contact"), alert: "The contact form is closed right now. Please try again later.")
    end

    # Bots fill in the hidden "website" field; real visitors never see it
    if params[:website].present?
      return redirect_to(root_path(anchor: "contact"), notice: "Thank you! We will reply by email soon.")
    end

    @contact_message = ContactMessage.new(message_params.merge(ip_address: request.remote_ip))
    if @contact_message.save
      ContactMailer.new_message(@contact_message).deliver_later
      redirect_to root_path(anchor: "contact"), notice: "Thank you, #{@contact_message.name}! We will reply to #{@contact_message.email} soon."
    else
      load_home_page # show the home page again with the visitor's text and the mistakes
      render "homes/index", status: :unprocessable_entity
    end
  end

  private

  def message_params
    params.require(:contact_message).permit(:name, :email, :phone, :organisation, :topic, :message)
  end
end
