# Admin → Payments: UPI transaction IDs to check against the bank (approve switches the plan on),
# plus every Razorpay payment. Admins only.
class Admin::PaymentsController < Admin::BaseController
  self.admin_area = :admin_only

  before_action :set_payment, only: [:approve, :reject]

  def index
    @status = params[:status].presence_in(%w[pending approved rejected all]) || "pending"
    scope = Payment.submitted.includes(:user, :plan, :institution, :reviewed_by).newest_first
    scope = scope.where(status: @status) unless @status == "all"
    if params[:q].present?
      like = "%#{Payment.sanitize_sql_like(params[:q].strip)}%"
      scope = scope.left_joins(:user).where("payments.utr ILIKE :q OR payments.razorpay_payment_id ILIKE :q OR users.email_address ILIKE :q", q: like)
    end
    @counts = Payment.submitted.group(:status).count
    @setting = PaymentSetting.current
    @payments = paginate(scope)
  end

  # The money is in the bank: switch the plan on
  def approve
    @payment.approve!(Current.user, note: params[:note])
    log!("approve_payment", record: @payment, label: "#{@payment.user.email_address} · #{@payment.what}",
         details: { amount_inr: @payment.amount_inr, utr: @payment.utr, period: @payment.period, paid_until: @payment.paid_until })
    PaymentMailer.decided(@payment).deliver_later
    redirect_back_or_to admin_payments_path, notice: "Approved. #{@payment.what.capitalize} is active until #{I18n.l(@payment.paid_until, format: :long)}."
  rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
    redirect_back_or_to admin_payments_path, alert: "Could not approve: #{e.message}"
  end

  # Not found in the bank (or wrong amount): tell the payer why
  def reject
    note = params[:note].to_s.squish
    return redirect_back_or_to(admin_payments_path, alert: "Write a reason so the payer knows what to do.") if note.blank?

    @payment.reject!(Current.user, note: note)
    log!("reject_payment", record: @payment, label: "#{@payment.user.email_address} · #{@payment.what}", reason: note,
         details: { amount_inr: @payment.amount_inr, utr: @payment.utr })
    PaymentMailer.decided(@payment).deliver_later
    redirect_back_or_to admin_payments_path, notice: "Rejected. #{@payment.user.display_name} can see your reason on their page."
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_back_or_to admin_payments_path, alert: "Could not reject: #{e.message}"
  end

  private

  def set_payment
    @payment = Payment.find(params[:id])
  end
end
