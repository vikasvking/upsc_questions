# Preview at http://localhost:3000/rails/mailers/contact_mailer/new_message
class ContactMailerPreview < ActionMailer::Preview
  def new_message
    ContactMailer.new_message(ContactMessage.new(name: "Ritu Sharma", email: "ritu@example.com", phone: "98765 43210",
                                                 organisation: "Sunrise Academy", topic: "custom_plan",
                                                 message: "We have 1,500 students in 3 branches and need JEE and NEET.", created_at: Time.current))
  end
end
