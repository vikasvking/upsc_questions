# config/routes.rb
Rails.application.routes.draw do
  root "homes#index"

  get "dashboard", to: "dashboards#show", as: :dashboard
  get "question_bank", to: "questionbanks#show", as: :question_bank

  # Teacher tests (now includes :update, which was missing and broke "Edit Paper")
  resources :test_sessions, only: [:index, :new, :create, :show, :edit, :update] do
    collection do
      get  :join, to: "test_sessions#join_form"
      post :verify_pin
      get  :upload_form
      post :import
      get  :download_template
    end
  end

  # Quiz lifecycle
  get  "dashboard/tests/:id",      to: "dashboards#test_intro",    as: :test_intro_dashboard
  post "dashboard/start_test",     to: "dashboards#start_test",    as: :start_test_dashboard
  get  "dashboard/arena/:token",   to: "dashboards#arena",         as: :arena_dashboard
  post "dashboard/submit_answer",  to: "dashboards#submit_answer", as: :submit_answer_dashboard
  post "dashboard/skip_question",  to: "dashboards#skip_question", as: :skip_question_dashboard
  post "dashboard/finish_test",    to: "dashboards#finish_test",   as: :finish_test_dashboard
  get  "dashboard/results",        to: "dashboards#results",       as: :test_results_dashboard

  resources :questions, only: [:index, :edit, :update] do
    collection do
      get  :upload_form
      post :import
      get  :import, to: "questions#upload_form" # browser reload after a failed upload
      get  :download_template
    end
  end

  resource :profile, only: [:show, :edit, :update]
  resource :session
  resources :passwords, param: :token
  get  "sign_up", to: "registrations#new", as: :new_registration
  post "sign_up", to: "registrations#create"

  get "up" => "rails/health#show", as: :rails_health_check
end
