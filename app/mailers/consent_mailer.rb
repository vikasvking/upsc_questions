# Sends the parent the consent text and the code that creates (or unlocks) an under-18 account
class ConsentMailer < ApplicationMailer
  def parent_code(pending_signup, code)
    @code = code
    @student_name = pending_signup.data["name"].presence || "your child"
    @student_email = pending_signup.email_address
    @minutes = PendingSignup::CODE_TTL.in_minutes.to_i
    mail subject: "Consent code for #{@student_name}'s Lakshyank account", to: pending_signup.parent_email
  end
end
