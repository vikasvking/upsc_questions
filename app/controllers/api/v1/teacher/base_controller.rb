# Teacher (and admin) part of the API. Uses the website's "Visible to" rules (AudienceAssignment):
# send visibility=public|institution|selected, institution_id, and for "selected"
# audience[batch_ids][], audience[institution_ids][], audience[user_ids][], audience[emails]="a@x.com, b@y.com".
module Api
  module V1
    module Teacher
      class BaseController < Api::V1::BaseController
        include AudienceAssignment

        before_action :require_ready_account!
        before_action :require_faculty!

        private

        # AudienceAssignment reports unknown student emails through flash; the API returns them as a warning
        def flash = (@api_flash ||= {})

        def warning = flash[:alert]

        def audience_json(record)
          { visibility: record.visibility, label: record.audience_label, institution_id: record.institution_id,
            user_ids: record.granted_ids("User"), institution_ids: record.granted_ids("Institution"), batch_ids: record.granted_ids("Batch") }
        end

        def errors_of(record) = record.errors.full_messages.to_sentence
      end
    end
  end
end
