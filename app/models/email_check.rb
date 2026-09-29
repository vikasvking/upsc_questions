require "resolv"

# Checks that an email address looks right and that its domain can receive mail.
module EmailCheck
  # Off in tests so they never need the network
  mattr_accessor :domain_lookup, default: !Rails.env.test?

  COMMON_TYPOS = {
    "gmial.com" => "gmail.com", "gamil.com" => "gmail.com", "gmai.com" => "gmail.com", "gmail.co" => "gmail.com",
    "gmail.con" => "gmail.com", "gnail.com" => "gmail.com", "yahooo.com" => "yahoo.com", "yaho.com" => "yahoo.com",
    "yahoo.co" => "yahoo.com", "hotmial.com" => "hotmail.com", "hotmail.co" => "hotmail.com",
    "outlok.com" => "outlook.com", "outlook.co" => "outlook.com", "rediffmial.com" => "rediffmail.com"
  }.freeze

  # nil when the address is fine, otherwise a message
  def self.problem(email)
    email = email.to_s.strip.downcase
    return "is not a valid email address" unless email.match?(URI::MailTo::EMAIL_REGEXP) && email.include?(".")

    domain = email.split("@").last
    if (fix = COMMON_TYPOS[domain])
      return "looks mistyped: did you mean #{email.split("@").first}@#{fix}?"
    end
    return nil unless domain_lookup

    receives_mail?(domain) == false ? "has a domain (#{domain}) that cannot receive email" : nil
  end

  # true / false, or nil when DNS could not be asked (then we do not block signup)
  def self.receives_mail?(domain)
    Rails.cache.fetch("email_check/#{domain}", expires_in: 1.day) do
      Resolv::DNS.open do |dns|
        dns.timeouts = 2
        dns.getresources(domain, Resolv::DNS::Resource::IN::MX).any? ||
          dns.getresources(domain, Resolv::DNS::Resource::IN::A).any?
      end
    end
  rescue Resolv::ResolvError, Resolv::ResolvTimeout, SocketError, Errno::ECONNREFUSED
    nil
  end
end
