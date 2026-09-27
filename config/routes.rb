# config/routes.rb
Rails.application.routes.draw do
  get "announcements/show",to: "announcements#show", as: :announcement
  get "questionbanks/show",to: "questionbanks#show", as: :questionbanks
  get "profiles/show"
  get "profiles/edit"
  get "profiles/update"
  root "homes#index"

  # Student Practice Dashboard & Quiz Lifecycle Matrix
  get  "dashboard", to: "dashboards#show", as: :dashboard
  post "dashboard/start_test", to: "dashboards#start_test", as: :start_test_dashboard
  post "dashboard/submit_answer", to: "dashboards#submit_answer", as: :submit_answer_dashboard
  post "dashboard/skip_question", to: "dashboards#skip_question", as: :skip_question_dashboard
  post "dashboard/finish_test", to: "dashboards#finish_test", as: :finish_test_dashboard
  get  "dashboard/results", to: "dashboards#results", as: :test_results_dashboard


  resource :profile, only: [ :show, :edit, :update ]
  # Authentication Management Rails
  resource :session
  resources :passwords, param: :token

  get  "sign_up", to: "registrations#new", as: :new_registration
  post "sign_up", to: "registrations#create"

  resources :questions, only: [:index] do
    collection do
      get :upload_form
      post :import
    end
  end
end
