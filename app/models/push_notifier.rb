require "net/http"

# Sends push notifications to the mobile app through Firebase Cloud Messaging (the FCM HTTP v1 API).
#
# Setup: in Firebase -> Project settings -> Service accounts -> "Generate new private key", then put the
# whole JSON file into the FIREBASE_CREDENTIALS environment variable on the server. Without it nothing
# is sent (and nothing breaks), so development and tests need no Firebase account.
#
# Two ways to reach students:
#   * topics, for public tests: every phone subscribes to "all_<EXAM>" for the exams the student prepares
#     for, and "tests_<EXAM>" for the ones whose public tests their tier includes (see User#push_topics).
#     One request reaches everyone, however many students there are.
#   * device tokens, for school / selected tests, results and reminders (see #to_users).
#
# In tests nothing is sent: messages are collected in PushNotifier.deliveries instead.
class PushNotifier
  FCM_HOST   = "fcm.googleapis.com"
  SCOPE      = "https://www.googleapis.com/auth/firebase.messaging"
  TOKEN_URI  = "https://oauth2.googleapis.com/token"

  Delivery = Struct.new(:token, :topic, :title, :body, :data, keyword_init: true)

  class Error < StandardError; end

  @mutex = Mutex.new
  @deliveries = []
  @fake = Rails.env.test?

  class << self
    attr_accessor :fake
    attr_reader :deliveries

    def enabled? = fake || credentials.present?

    # Sends one message to every phone of these users who have left the switch `pref`
    # (:push_new_tests, :push_results or :push_reminders) on. `message` may be a Hash, or a
    # block that builds one per user (for a personal line such as their rank).
    def to_users(user_ids, pref:, title: nil, body: nil, data: {}, &message)
      return 0 unless enabled?

      tokens = DeviceToken.joins(:user).where(user_id: user_ids, users: { pref => true }).includes(:user).to_a
      return 0 if tokens.empty?

      sent = 0
      with_connection do |http|
        tokens.each do |device|
          m = message ? message.call(device.user) : { title: title, body: body, data: data }
          next unless m
          sent += 1 if send_message(http, { token: device.token }, **m) == :ok
        rescue => e
          Rails.logger.warn("[push] #{e.class}: #{e.message}")
        end
      end
      sent
    end

    # One message to every phone subscribed to a topic (see User#push_topics)
    def to_topic(topic, title:, body:, data: {})
      return false unless enabled?
      with_connection { |http| send_message(http, { topic: topic }, title: title, body: body, data: data) == :ok }
    rescue => e
      Rails.logger.warn("[push] #{e.class}: #{e.message}")
      false
    end

    private

    def credentials
      raw = ENV["FIREBASE_CREDENTIALS"].presence
      @credentials = nil unless raw == @credentials_raw
      @credentials_raw = raw
      @credentials ||= raw && JSON.parse(raw)
    rescue JSON::ParserError
      Rails.logger.error("[push] FIREBASE_CREDENTIALS is not valid JSON; paste the whole service-account file")
      nil
    end

    def with_connection(&block)
      return yield(nil) if fake
      Net::HTTP.start(FCM_HOST, 443, use_ssl: true, open_timeout: 10, read_timeout: 15, &block)
    end

    # :ok, :gone (the app was uninstalled or the token expired; the token is deleted) or :failed
    def send_message(http, target, title:, body:, data: {})
      data = data.to_h.transform_keys(&:to_s).transform_values(&:to_s) # FCM only takes strings here
      if fake
        deliveries << Delivery.new(token: target[:token], topic: target[:topic], title: title, body: body, data: data)
        return :ok
      end

      payload = {
        message: target.merge(
          notification: { title: title, body: body },
          data: data,
          android: { priority: "high", notification: { sound: "default" } },
          apns: { payload: { aps: { sound: "default" } } }
        )
      }
      request = Net::HTTP::Post.new("/v1/projects/#{credentials.fetch("project_id")}/messages:send")
      request["Authorization"] = "Bearer #{access_token}"
      request["Content-Type"] = "application/json"
      request.body = payload.to_json
      response = http.request(request)
      return :ok if response.is_a?(Net::HTTPSuccess)

      @mutex.synchronize { @access_token = nil } if response.code == "401"
      if target[:token] && token_gone?(response)
        DeviceToken.where(token: target[:token]).delete_all
        return :gone
      end
      Rails.logger.warn("[push] FCM #{response.code}: #{response.body.to_s.truncate(300)}")
      :failed
    end

    def token_gone?(response)
      return true if response.code == "404"
      body = JSON.parse(response.body.to_s) rescue {}
      codes = Array(body.dig("error", "details")).filter_map { |d| d["errorCode"] }
      codes.include?("UNREGISTERED") ||
        (response.code == "400" && body.dig("error", "message").to_s.match?(/registration token/i))
    end

    # A short-lived OAuth token for FCM, made by signing a JWT with the service account's key
    # (the same thing Google's client libraries do, without an extra gem). Cached until shortly before it expires.
    def access_token
      @mutex.synchronize do
        return @access_token if @access_token && @access_token_expires_at > 2.minutes.from_now

        creds = credentials or raise Error, "FIREBASE_CREDENTIALS is not set"
        now = Time.now.to_i
        token_uri = creds["token_uri"].presence || TOKEN_URI
        segments = [{ alg: "RS256", typ: "JWT" },
                    { iss: creds.fetch("client_email"), scope: SCOPE, aud: token_uri, iat: now, exp: now + 3600 }]
                   .map { |part| Base64.urlsafe_encode64(part.to_json, padding: false) }
        signing_input = segments.join(".")
        signature = OpenSSL::PKey::RSA.new(creds.fetch("private_key")).sign(OpenSSL::Digest.new("SHA256"), signing_input)
        assertion = "#{signing_input}.#{Base64.urlsafe_encode64(signature, padding: false)}"

        response = Net::HTTP.post_form(URI(token_uri), grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: assertion)
        raise Error, "Google sign-in for FCM failed (#{response.code}): #{response.body.to_s.truncate(200)}" unless response.is_a?(Net::HTTPSuccess)

        json = JSON.parse(response.body)
        @access_token_expires_at = Time.current + json.fetch("expires_in", 3600).to_i
        @access_token = json.fetch("access_token")
      end
    end
  end
end
