# Deletes the records of finished jobs so the jobs tables stay small. Every hour (config/recurring.yml).
# Was a `command:` in recurring.yml; a job class lets it have an on/off switch on Admin → Background work.
class ClearFinishedJobsJob < ApplicationJob
  queue_as :default
  background_switch :clear_finished_jobs

  def perform
    SolidQueue::Job.clear_finished_in_batches(sleep_between_batches: 0.3)
  end
end
