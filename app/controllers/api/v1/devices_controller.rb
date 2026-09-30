# Phones that receive push notifications (Firebase Cloud Messaging tokens, see PushNotifier).
#   POST   /api/v1/devices  token=..., platform=android|ios -> { push_topics: [...] } to subscribe the phone to
#   DELETE /api/v1/devices  token=...                       -> on sign-out, so the phone stops getting this user's notifications
module Api
  module V1
    class DevicesController < BaseController
      def create
        token = params[:token].to_s.strip
        return render_error("invalid", "Missing device token.") if token.blank? || token.length > 4096

        DeviceToken.register!(current_user, token, platform: params[:platform])
        render json: { registered: true, push_topics: current_user.push_topics }, status: :created
      end

      def destroy
        current_user.device_tokens.where(token: params[:token].to_s.strip).delete_all
        head :no_content
      end
    end
  end
end
