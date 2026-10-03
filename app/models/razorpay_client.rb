require "net/http"

# The two Razorpay calls Lakshyank needs: create an order, and check the signature Razorpay
# returns after the payer pays (https://razorpay.com/docs/payments/server-integration/).
module RazorpayClient
  class Error < StandardError; end

  ORDERS_URL = URI("https://api.razorpay.com/v1/orders")

  # => { "id" => "order_...", "amount" => 4900, ... }
  def self.create_order(amount_paise:, receipt:, notes: {}, setting: PaymentSetting.current)
    request = Net::HTTP::Post.new(ORDERS_URL, "Content-Type" => "application/json")
    request.basic_auth(setting.razorpay_key_id, setting.razorpay_key_secret)
    request.body = { amount: amount_paise, currency: "INR", receipt: receipt, notes: notes }.to_json

    response = Net::HTTP.start(ORDERS_URL.host, ORDERS_URL.port, use_ssl: true, open_timeout: 10, read_timeout: 15) do |http|
      http.request(request)
    end
    body = JSON.parse(response.body) rescue {}
    raise Error, body.dig("error", "description") || "Razorpay answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    body
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
    raise Error, "Could not reach Razorpay (#{e.class.name.demodulize})"
  end

  # True when the signature proves Razorpay confirmed this payment for this order
  def self.valid_signature?(order_id:, payment_id:, signature:, setting: PaymentSetting.current)
    secret = setting.razorpay_key_secret
    return false if secret.blank? || order_id.blank? || payment_id.blank? || signature.blank?
    expected = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{order_id}|#{payment_id}")
    ActiveSupport::SecurityUtils.secure_compare(expected, signature.to_s)
  end
end
