# Paying for a plan.
#   GET  /payments                       -> teachers: their schools' plans and payments (students go to Membership)
#   GET  /payments/new?plan_id=&period=  -> the Pay page (&institution_id= for a school plan)
#   POST /payments                       -> UPI QR: the transaction ID (UTR), checked later by an admin
#   POST /payments/razorpay_order        -> Razorpay (when on): makes an order for the checkout window (JSON)
#   POST /payments/:id/razorpay_verify   -> Razorpay: checks the signature and activates the plan at once
class PaymentsController < ApplicationController
  rate_limit to: 10, within: 10.minutes, only: [:create, :razorpay_order],
             with: -> { redirect_to membership_path, alert: "Too many payment attempts. Please wait a few minutes." }

  before_action :set_setting

  def index
    return redirect_to(membership_path) unless Current.user.faculty?

    @schools = Current.user.admin? ? Institution.none : Current.user.institutions.includes(:plan).ordered.to_a
    @plans = Plan.active.for_schools.ordered.to_a
    @payments = Current.user.payments.submitted.includes(:plan, :institution).newest_first.limit(20)
  end

  def new
    @payment = build_payment
    return if performed?
    @pending = Current.user.payments.pending.where(plan: @payment.plan, institution: @payment.institution).newest_first.first
  end

  # UPI QR: the payer has paid and gives the transaction ID
  def create
    @payment = build_payment(utr: params.dig(:payment, :utr), pay_method: "upi_qr", status: "pending")
    return if performed?
    unless @setting.qr_ready?
      return redirect_to(membership_path, alert: "UPI payment is not set up yet. Please contact the Lakshyank team.")
    end

    if @payment.save
      PaymentMailer.submitted(@payment).deliver_later
      redirect_to after_payment_path(@payment),
                  notice: "Thank you! We received transaction ID #{@payment.utr} for ₹#{@payment.amount_inr}. " \
                          "Your #{@payment.what} starts as soon as we confirm the payment, usually within a day."
    else
      @pending = nil
      render :new, status: :unprocessable_entity
    end
  end

  # Razorpay: make an order; the page then opens Razorpay's checkout with it
  def razorpay_order
    return render(json: { error: "Online payment is switched off." }, status: :unprocessable_entity) unless @setting.gateway_ready?

    payment = build_payment(pay_method: "razorpay", status: "created")
    return if performed?
    return render(json: { error: payment.errors.full_messages.to_sentence }, status: :unprocessable_entity) unless payment.save

    order = RazorpayClient.create_order(amount_paise: payment.amount_inr * 100, receipt: "lakshyank_#{payment.id}",
                                        notes: { payment_id: payment.id, user: Current.user.email_address, plan: payment.plan.name })
    payment.update!(razorpay_order_id: order.fetch("id"))
    render json: {
      key: @setting.razorpay_key_id, order_id: payment.razorpay_order_id, amount: payment.amount_inr * 100, currency: "INR",
      name: "Lakshyank", description: "#{payment.what} · #{payment.period_label}",
      prefill: { name: Current.user.display_name, email: Current.user.email_address },
      verify_url: razorpay_verify_payment_path(payment)
    }
  rescue RazorpayClient::Error => e
    payment&.destroy if payment&.persisted? && payment.razorpay_order_id.nil?
    render json: { error: "Could not start the payment: #{e.message}" }, status: :bad_gateway
  end

  # Razorpay: the checkout window returns these three values after a successful payment
  def razorpay_verify
    payment = Current.user.payments.find(params[:id])
    return redirect_to(after_payment_path(payment), notice: "This payment is already confirmed.") if payment.approved?

    valid = payment.razorpay? && payment.status == "created" && payment.razorpay_order_id == params[:razorpay_order_id] &&
            RazorpayClient.valid_signature?(order_id: payment.razorpay_order_id, payment_id: params[:razorpay_payment_id],
                                            signature: params[:razorpay_signature], setting: @setting)
    unless valid
      return redirect_to(membership_path, alert: "We could not confirm this payment. If money was taken, contact the Lakshyank team with your Razorpay payment ID.")
    end

    payment.update!(razorpay_payment_id: params[:razorpay_payment_id])
    payment.approve!
    PaymentMailer.decided(payment).deliver_later
    redirect_to after_payment_path(payment), notice: "Payment received. Your #{payment.what} is active until #{I18n.l(payment.paid_until, format: :long)}."
  end

  private

  def set_setting
    @setting = PaymentSetting.current
  end

  def build_payment(extra = {})
    plan = Plan.active.find_by(id: params[:plan_id] || params.dig(:payment, :plan_id))
    return redirect_to(membership_path, alert: "That plan is not offered right now.") unless plan

    period = (params[:period] || params.dig(:payment, :period)).presence_in(Payment::PERIODS.keys) || "month"
    institution_id = params[:institution_id] || params.dig(:payment, :institution_id)
    institution = plan.school? ? Current.user.institutions.find_by(id: institution_id) || (Current.user.admin? ? Institution.find_by(id: institution_id) : nil) : nil
    institution ||= Current.user.institutions.first if plan.school? && institution_id.blank?

    Current.user.payments.new({ plan: plan, period: period, institution: institution,
                                     amount_inr: Payment.amount_for(plan, period, Current.user) }.merge(extra))
  end

  def after_payment_path(payment) = payment.school? ? payments_path : membership_path
end
