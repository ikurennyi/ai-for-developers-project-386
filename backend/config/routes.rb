Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      namespace :admin do
        resources :bookings, only: [ :index ]
        resources :meeting_types, path: "meeting-types", only: [ :index, :create, :show, :update ] do
          put :publication, on: :member
        end
        resource :session, only: [ :show, :create, :destroy ], controller: :sessions
      end
    end
  end
  namespace :api do
    namespace :v1 do
      get "health", to: "health#show"
      get "meeting-types", to: "meeting_types#index"
      get "meeting-types/:slug/availability", to: "availability#show"
      post "meeting-types/:slug/bookings", to: "bookings#create"
    end
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
