# config/routes.rb
Rails.application.routes.draw do
  get "dashboard", to: "dashboards#show", as: :dashboard
  get  "sign_up", to: "registrations#new", as: :new_registration
  post "sign_up", to: "registrations#create"
  resource :session
  resources :passwords, param: :token
  root "homes#index"
  get "questions/index"
  get "questions/upload_form"


  resources :questions, only: [:index] do
    collection do
      get :upload_form
      post :import
    end
  end
end
