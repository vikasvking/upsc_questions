class HomesController < ApplicationController
  include HomePage
  allow_unauthenticated_access only: [ :index ]

  def index
    redirect_to dashboard_path and return if authenticated?

    load_home_page
  end
end
