Rails.application.routes.draw do
  get "/login", to: "auth#login_page"
  get "/auth/session", to: "auth#session_status"
  post "/auth/login", to: "auth#login"
  post "/auth/logout", to: "auth#logout"

  get "/health", to: "health#show"
  get "/dashboard", to: "dashboard#overview"
  get "/dashboard/revenue", to: "dashboard#revenue"
  get "/dashboard/users", to: "dashboard#users"
  get "/dashboard/payments", to: "dashboard#payments"
  get "/dashboard/ops", to: "dashboard#ops"

  namespace :metrics do
    get "/daily", to: "daily#index"
    get "/daily/details", to: "daily_details#show"
    get "/summary", to: "summary#show"
    get "/providers", to: "providers#index"
    get "/products", to: "products#index"
    get "/referrals", to: "referrals#index"
    get "/promos", to: "promos#index"
    get "/cohorts", to: "cohorts#index"
    get "/funnel", to: "funnel#index"
    get "/payments", to: "payments#index"
    get "/insights", to: "insights#index"
    get "/users", to: "users#index"
    get "/users/details", to: "users#show"
  end

  namespace :ops do
    get "/jobs", to: "jobs#index"
    get "/data-quality", to: "data_quality#index"
    post "/backfill", to: "backfill#create"
    post "/data-quality/run", to: "data_quality#run"
  end

  namespace :exports do
    get "/metrics", to: "metrics#index"
  end
end
