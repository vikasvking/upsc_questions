module ProfilesHelper
  # ab•••@example.com
  def mask(email)
    local, domain = email.to_s.split("@", 2)
    "#{local.to_s[0, 2]}#{"•" * [local.to_s.length - 2, 3].max}@#{domain}"
  end
end
