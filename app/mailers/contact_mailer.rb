# A message from the home page contact form, sent to every admin. "Reply" goes to the visitor.
class ContactMailer < ApplicationMailer
  def new_message(contact_message)
    @message = contact_message
    @url = admin_contact_messages_url
    admins = User.admin.pluck(:email_address)
    return if admins.empty?

    mail to: admins, reply_to: @message.email,
         subject: "Lakshyank contact: #{@message.topic_label} from #{@message.name}"
  end
end
