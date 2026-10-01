# config/routes.rb
Rails.application.routes.draw do
  root "homes#index"

  # JSON API for the Rankwise mobile app. Sign in with POST /api/v1/session, then send
  # "Authorization: Bearer <token>" with every request (see Api::V1::BaseController).
  namespace :api, defaults: { format: :json } do
    namespace :v1 do
      resource :session, only: [:create, :destroy]
      get   "me",    to: "profiles#show"
      patch "me",    to: "profiles#update"
      get   "exams", to: "profiles#exams"
      patch "me/notifications", to: "profiles#notifications"
      post   "devices", to: "devices#create"
      delete "devices", to: "devices#destroy"

      # Students
      get "dashboard",  to: "dashboard#show"
      get "membership", to: "dashboard#membership"
      get "leaderboard", to: "dashboard#leaderboard"
      resources :tests, only: [:index, :show] do
        post :start, on: :member
        post :verify_pin, on: :collection
      end
      post "practice", to: "attempts#practice"
      resources :attempts, only: [:index, :show], param: :token do
        member do
          post :answer
          post :finish
          get  :result
          post :heartbeat
          post :report_leave
        end
      end
      get  "question_bank",        to: "question_bank#index"
      get  "question_bank/topic",  to: "question_bank#topic"
      post "question_bank/answer", to: "question_bank#answer"

      # Teachers (and admins)
      namespace :teacher do
        get "form_options", to: "tests#form_options"
        resources :tests, only: [:index, :show, :create, :update] do
          member do
            get  :results
            get  :live
            post :reinstate
          end
        end
        resources :questions, only: [:index, :show, :create, :update]
      end
    end
  end

  get "dashboard", to: "dashboards#show", as: :dashboard
  get "question_bank", to: "questionbanks#show", as: :question_bank
  get "question_bank/topic", to: "questionbanks#topic", as: :question_bank_topic
  post "question_bank/answer", to: "questionbanks#answer", as: :question_bank_answer

  # Teacher tests (now includes :update, which was missing and broke "Edit Paper")
  resources :test_sessions, only: [:index, :new, :create, :show, :edit, :update] do
    collection do
      get  :join, to: "test_sessions#join_form"
      post :verify_pin
      get  :upload_form
      post :import
      get  :download_template
    end
    # Strict mode: teacher lets a blocked student continue; live panel while the test is open
    post :reinstate, on: :member
    get  :live, on: :member
  end

  # Quiz lifecycle
  get  "dashboard/all_tests",      to: "dashboards#all_tests",     as: :all_tests_dashboard
  get  "dashboard/tests/:id",      to: "dashboards#test_intro",    as: :test_intro_dashboard
  post "dashboard/start_test",     to: "dashboards#start_test",    as: :start_test_dashboard
  get  "dashboard/arena/:token",   to: "dashboards#arena",         as: :arena_dashboard
  post "dashboard/submit_answer",  to: "dashboards#submit_answer", as: :submit_answer_dashboard
  post "dashboard/skip_question",  to: "dashboards#skip_question", as: :skip_question_dashboard
  post "dashboard/finish_test",    to: "dashboards#finish_test",   as: :finish_test_dashboard
  get  "dashboard/results",        to: "dashboards#results",       as: :test_results_dashboard
  # Strict mode: the test page reports presence and leaving (JSON)
  post "dashboard/heartbeat",      to: "dashboards#heartbeat",     as: :heartbeat_dashboard,    defaults: { format: :json }
  post "dashboard/report_leave",   to: "dashboards#report_leave",  as: :report_leave_dashboard, defaults: { format: :json }

  resources :questions, only: [:index, :new, :create, :edit, :update] do
    collection do
      get  :upload_form
      post :import
      get  :import, to: "questions#upload_form" # browser reload after a failed upload
      get  :download_template
    end
  end

  # Paying for Warrior (students) or a school plan (teachers): UPI QR + transaction ID, or Razorpay when switched on
  resources :payments, only: [:index, :new, :create] do
    post :razorpay_order, on: :collection
    post :razorpay_verify, on: :member
  end

  # Contact form in the home page footer (open only while email is on)
  resources :contact_messages, only: :create

  # Question picker in the test form: one exam, 50 at a time, searched on the server (Turbo Frame)
  get "question_library", to: "question_libraries#show", as: :question_library

  resource :profile, only: [:show, :edit, :update]
  patch "profile/exam", to: "profiles#update_exam", as: :profile_exam # exam used for the dashboard rank
  patch "profile/details", to: "profiles#update_details", as: :profile_details # name, exams, subjects... (no password)
  resource :session
  resources :passwords, param: :token
  get  "sign_up", to: "registrations#new", as: :new_registration
  post "sign_up", to: "registrations#create"

  # Under-18 students: the parent's code (new signups by token; existing accounts via parent_consent)
  get  "consent/:token",        to: "consents#show",   as: :consent
  post "consent/:token",        to: "consents#verify", as: :verify_consent
  post "consent/:token/resend", to: "consents#resend", as: :resend_consent
  get  "parent_consent/new",    to: "consents#new",    as: :new_parent_consent
  post "parent_consent",        to: "consents#create", as: :parent_consent

  get  "confirm_email/:token", to: "email_confirmations#show", as: :email_confirmation
  post "confirm_email",        to: "email_confirmations#create", as: :resend_email_confirmation
  get  "pending_approval",     to: "account_status#pending_approval", as: :pending_approval

  # Schools and coachings: join with a code or ask; teachers approve requests and share the code
  resources :institutions, only: [:index, :create] do
    post :regenerate_code, on: :member
  end
  resources :batches, except: [:show] # a teacher's saved groups of students
  resources :teachers, only: :show     # public teacher profile
  get "membership", to: "tiers#show", as: :membership # a student's tier: Free, Plus or Warrior
  resources :ratings, only: [:create, :destroy]
  resources :question_reports, only: [:index, :create, :update] # "Report a problem" on a question
  resources :memberships, only: [:create, :destroy] do
    patch :approve, on: :member
  end

  # Admins only: manage teachers, students, questions and tests (every change is logged)
  namespace :admin do
    root "dashboard#show"
    resources :users do
      patch :approve, on: :member
    end
    resources :approvals, only: [:index] do
      patch :approve_teacher, on: :member
    end
    resources :institutions, except: [:show] do
      post :merge, on: :member
      post :regenerate_code, on: :member
      patch :subscription, on: :member
    end
    resources :plans, except: [:show, :destroy]
    resource :mail_settings, only: [:edit, :update] do
      post :send_test, on: :member
    end
    resources :questions, except: [:show] do
      patch :toggle_gift, on: :member # 🎁 free sample on/off in one click
    end
    resources :test_sessions, path: "tests", except: [:show] do
      patch :toggle_gift, on: :member
    end
    resources :payments, only: [:index] do # UPI transaction IDs to check, and Razorpay payments
      patch :approve, on: :member
      patch :reject, on: :member
    end
    resource :payment_settings, only: [:edit, :update] # Razorpay keys + on/off, UPI ID for the QR
    resources :contact_messages, path: "messages", only: [:index, :update] # from the home page contact form
    resources :logs, only: [:index]
    resources :moderation, only: [:index] do
      patch :hide_comment, on: :member
      patch :unhide_comment, on: :member
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
