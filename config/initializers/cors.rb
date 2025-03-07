# config/initializers/cors.rb
# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) to accept cross-origin Ajax requests.

# Read more: https://github.com/cyu/rack-cors

Rails.application.config.middleware.insert_before 0, Rack::Cors do
    allow do
      # Adjust origins to match your React frontend's URL
      # origins 'http://localhost:3001' # Change to your React app's port if different
      origins ENV['CORS_ALLOWED_ORIGINS']&.split(',') || 'http://localhost:3001'
  
      resource '*',
        # headers: :any,
        # methods: [:get, :post, :put, :patch, :delete, :options, :head]
        headers: ['Authorization', 'Content-Type', 'Accept'],
        methods: [:get, :post, :put, :patch, :delete, :options]
    end
  end