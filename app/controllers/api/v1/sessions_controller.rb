# POST   /api/v1/session  email_address, password -> { token, user }
# DELETE /api/v1/session  -> signs this device out
module Api
  module V1
    class SessionsController < BaseController
      skip_before_action :authenticate!, only: :create
      rate_limit to: 10, within: 3.minutes, only: :create,
                 with: -> { render_error("rate_limited", "Too many tries. Wait a few minutes and try again.", status: :too_many_requests) }

      def create
        user = User.authenticate_by(email_address: params[:email_address].to_s.strip, password: params[:password].to_s)
        return render_error("invalid_login", "Try another email address or password.", status: :unauthorized) unless user

        api_session = user.sessions.create!(user_agent: "Rankwise app · #{request.user_agent}".truncate(250), ip_address: request.remote_ip)
        render json: { token: api_session.signed_id(purpose: TOKEN_PURPOSE), user: user_json(user) }, status: :created
      end

      def destroy
        Current.session.destroy
        head :no_content
      end
    end
  end
end
