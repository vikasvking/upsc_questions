# Admin → Email: SMTP details and the on/off switch. Admins only.
class Admin::MailSettingsController < Admin::BaseController
  self.admin_area = :admin_only

  before_action :set_setting

  def edit
  end

  def update
    before = @setting.attributes.slice(*LOGGED)
    @setting.assign_attributes(setting_params)
    if @setting.save
      changes = @setting.attributes.slice(*LOGGED).filter_map { |k, v| [k, { "from" => before[k], "to" => v }] unless before[k] == v }.to_h
      changes["password"] = "changed" if setting_params[:password].present?
      log!("update_mail_settings", record: @setting, label: @setting.address, details: changes)
      redirect_to edit_admin_mail_settings_path, notice: @setting.active? ? "Saved. Email sending is ON." : "Saved. Email sending is OFF."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # POST /admin/mail_settings/send_test -> sends a test email to the admin
  def send_test
    unless @setting.active?
      return redirect_to(edit_admin_mail_settings_path, alert: "Switch email sending on (and save) before sending a test.")
    end
    MailSettingsMailer.test_email(Current.user.email_address).deliver_now
    redirect_to edit_admin_mail_settings_path, notice: "Test email sent to #{Current.user.email_address}. Check your inbox (and spam)."
  rescue StandardError => e
    redirect_to edit_admin_mail_settings_path, alert: "Sending failed: #{e.message.truncate(200)}"
  end

  private

  LOGGED = %w[enabled address port domain user_name authentication enable_starttls from_address].freeze

  def set_setting
    @setting = MailSetting.current
  end

  def setting_params
    params.require(:mail_setting).permit(:enabled, :address, :port, :domain, :user_name, :password, :authentication, :enable_starttls, :from_address)
  end
end
