class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  # Jobs an admin can switch off on Admin → Background work (see BackgroundJobSetting).
  # When off, the job still runs on its schedule but returns at once without doing anything.
  class_attribute :background_switch_key, instance_writer: false

  def self.background_switch(key)
    raise ArgumentError, "Unknown background job: #{key}" unless BackgroundJobSetting::JOBS.key?(key.to_s)

    self.background_switch_key = key.to_s
    around_perform :run_if_switched_on
  end

  private

  def run_if_switched_on
    setting = BackgroundJobSetting.for(background_switch_key)
    return unless setting.enabled?

    started = Time.current
    setting.record_start!(started)
    yield
    setting.record_finish!(started)
  rescue StandardError => e
    setting.record_finish!(started, error: e) if setting && started
    raise
  end
end
