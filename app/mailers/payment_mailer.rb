# Payment emails (sent only while email is on, like every Rankwise email)
class PaymentMailer < ApplicationMailer
  helper :payments

  # To every admin: a transaction ID to check
  def submitted(payment)
    @payment = payment
    @url = admin_payments_url
    admins = User.admin.pluck(:email_address)
    return if admins.empty?
    mail to: admins, subject: "Rankwise payment to check: ₹#{payment.amount_inr} from #{payment.user.display_name}"
  end

  # To the payer: approved (plan is on) or rejected (with the admin's reason)
  def decided(payment)
    @payment = payment
    @url = payment.school? ? payments_url : membership_url
    mail to: payment.user.email_address,
         subject: payment.approved? ? "Your Rankwise payment is confirmed" : "We could not confirm your Rankwise payment"
  end
end
