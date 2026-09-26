# config/routes.rb
Rails.application.routes.draw do
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
