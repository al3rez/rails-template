gem "devise"
gem "devise-jwt"
gem "fast_jsonapi"
gem "kaminari"

gem_group :development, :test do
  gem "guard"
  gem "guard-minitest"
  gem "minitest-reporters"
  gem "pry-byebug"
  gem "pry-rails"
  gem "reek"
  gem "standard", "0.1.6"
end

def disable_inflection_for_blocklist!
  inflections = <<-BODY
  ActiveSupport::Inflector.inflections(:en) do |inflect|
    inflect.plural "blocklist", "blocklist"
  end
  BODY
  insert_into_file "config/initializers/inflections.rb", inflections, after: "# end\n"
end

def generate_jwt_blocklist!
  disable_inflection_for_blocklist!
  generate "model jwt_blocklist jti:string:index exp:datetime"
  jwt_blocklist = <<-BODY
  include Devise::JWT::RevocationStrategies::Blacklist
  self.table_name = "jwt_blocklist"
  BODY
  insert_into_file "app/models/jwt_blocklist.rb", jwt_blocklist, after: "class JwtBlocklist < ApplicationRecord\n"
end

def config_jwt_for_devise!
  jwt_config = <<-CONFIG
  config.jwt do |jwt|
    jwt.secret = Rails.application.credentials.secret_key_base
    jwt.dispatch_requests = [
        ['POST', %r{^/login$}]
      ]
      jwt.revocation_requests = [
        ['DELETE', %r{^/logout$}]
      ]
    jwt.expiration_time = 5.minutes.to_i
  end
  CONFIG
  insert_into_file "config/initializers/devise.rb", jwt_config, after: "# config.sign_in_after_change_password = true\n"
  gsub_file "config/initializers/devise.rb", /  # config.navigational_formats = .+/, "  config.navigational_formats = []"
  generate "controller sessions"
  generate "controller registrations"

  gsub_file "app/controllers/sessions_controller.rb", /ApplicationController/, "Devise::SessionsController"
  gsub_file "app/controllers/registrations_controller.rb", /ApplicationController/, "Devise::RegistrationsController"
  gsub_file "config/routes.rb", /  devise_for :users/, <<-REPLACE_WITH
    devise_for :users,
      path: "",
      path_names: {
        sign_in: "login",
        sign_out: "logout",
        registration: "signup"
      },
      controllers: {
        sessions: "sessions",
        registrations: "registrations"
      }
  REPLACE_WITH
  insert_into_file "app/controllers/application_controller.rb", "  include ActionController::MimeResponds\n", afer: "class ApplicationController < ActionController::API\n"
  insert_into_file "app/controllers/sessions_controller.rb", "  respond_to :json\n", after: "class SessionsController < Devise::SessionsController\n"
  insert_into_file "app/controllers/registrations_controller.rb", "  respond_to :json\n", after: "class RegistrationsController < Devise::RegistrationsController\n"
  sessions_controller_tests = <<-TESTS
  test "users can login" do
    post "/login", params: {user: {email: "alice@example.com", password: "password"}}
    assert_response :success
  end

  test "users cannot login with wrong password or email" do
    post "/login", params: {user: {email: "alice@example.com", password: "wrong"}}
    assert_response :unauthorized

    post "/login", params: {user: {email: "alise@example.com", password: "password"}}
    assert_response :unauthorized
  end
  TESTS
  insert_into_file "test/controllers/sessions_controller_test.rb", sessions_controller_tests, after: "SessionsControllerTest < ActionDispatch::IntegrationTest\n"
  gsub_file "test/fixtures/users.yml", /one: {}/, <<-GSUB
  alice:
    email: alice@example.com
    encrypted_password: <%= Devise::Encryptor.digest(User, 'password') %>
  GSUB

  gsub_file "test/fixtures/users.yml", /two: {}/, <<-GSUB
  bob:
    email: bob@example.com
    encrypted_password: <%= Devise::Encryptor.digest(User, 'password') %>
  GSUB

  generate_jwt_blocklist!
  inject_into_file("app/models/user.rb", ", :jwt_authenticatable, jwt_revocation_strategy: JwtBlocklist", after: ":validatable")
  insert_into_file("test/test_helper.rb", "require 'devise/jwt/test_helpers'", after: "require \"rails/test_help\"\n")
end

def config_devise!(with_jwt = false)
  generate "devise:install"
  generate "devise User"
  environment "config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }",
    env: "development"

  return unless with_jwt

  config_jwt_for_devise!
end

after_bundle do
  run "standardrb --fix"

  git :init
  git add: "."
  git commit: "-a -m 'feat: init project'"

  run "./bin/spring stop"
  config_devise!(with_jwt: true)

  run "standardrb --fix"
  rails_command "db:drop"
  rails_command "db:create"
  rails_command "db:migrate"
  rails_command "test"
  git commit: "-a -m 'feat: add authentication [devise/jwt]'"
end
