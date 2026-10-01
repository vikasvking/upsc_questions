# Admin → Payments → Settings: Razorpay keys with an on/off switch, and the UPI ID for the QR. Admins only.
class Admin::PaymentSettingsController < Admin::BaseController
  self.admin_area = :admin_only

  before_action :set_setting

  def edit
  end

  def update
    before = @setting.attributes.slice(*LOGGED)
    @setting.assign_attributes(setting_params)
    if @setting.save
      changes = @setting.attributes.slice(*LOGGED).filter_map { |k, v| [k, { "from" => before[k], "to" => v }] unless before[k] == v }.to_h
      changes["razorpay_key_secret"] = "changed" if setting_params[:razorpay_key_secret].present?
      log!("update_payment_settings", record: @setting, label: "Payments", details: changes)
      redirect_to edit_admin_payment_settings_path,
                  notice: @setting.gateway_ready? ? "Saved. Online payment (Razorpay) is ON." : "Saved. Payers see the UPI QR and send their transaction ID."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  LOGGED = %w[gateway_enabled razorpay_key_id upi_id payee_name instructions].freeze

  def set_setting
    @setting = PaymentSetting.current
  end

  def setting_params
    params.require(:payment_setting).permit(:gateway_enabled, :razorpay_key_id, :razorpay_key_secret, :upi_id, :payee_name, :instructions)
  end
end
