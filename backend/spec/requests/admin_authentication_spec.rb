require "rails_helper"
require_relative "../support/openapi_contract"

RSpec.describe "Administrator access", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:headers) { { "X-Calendar-Request" => "1" } }
  let(:password) { "test-only-password-24!" }

  around do |example|
    previous = ENV.to_h.slice("ADMIN_USERNAME", "ADMIN_PASSWORD")
    ENV["ADMIN_USERNAME"] = "owner"
    ENV["ADMIN_PASSWORD"] = password
    example.run
  ensure
    %w[ADMIN_USERNAME ADMIN_PASSWORD].each { |key| ENV[key] = previous[key] }
  end

  def login(username: "owner", password: self.password)
    post "/api/v1/admin/session", params: { username: username, password: password }, headers: headers, as: :json
    OpenapiContract.validate!(request, response)
  end

  it "protects administrative access and persists login across requests" do
    get "/api/v1/admin/session"
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq("message" => "Authentication required")
    login
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["username"]).to eq("owner")
    expect(response.headers["Set-Cookie"]).to include("httponly", "samesite=strict")
    expect(response.body).not_to include(password)
    get "/api/v1/admin/session"
    expect(response).to have_http_status(:ok)
    OpenapiContract.validate!(request, response)
  end

  it "returns the same generic error for unknown usernames and incorrect passwords" do
    login(username: "nobody")
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq("message" => "Invalid username or password")
    login(password: "wrong")
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq("message" => "Invalid username or password")
    get "/api/v1/admin/session"
    expect(response).to have_http_status(:unauthorized)
  end

  it "expires exactly 24 hours after login even with intervening activity and a replayed cookie" do
    travel_to Time.utc(2026, 11, 13, 10) do
      login
      expiry = response.parsed_body.fetch("expiresAt")
      token = cookies["calendar_admin"]
      travel 23.hours
      get "/api/v1/admin/session"
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch("expiresAt")).to eq(expiry)
      travel 1.hour
      # Bypass the browser's cookie expiry so only server-side expiry can pass.
      client = ActionDispatch::Integration::Session.new(Rails.application)
      client.get "/api/v1/admin/session", headers: { "Cookie" => "calendar_admin=#{token}" }
      expect(client.response).to have_http_status(:unauthorized)
      OpenapiContract.validate!(client.request, client.response)
    end
  end

  it "revokes logout immediately, including replay of the old cookie" do
    login
    token = cookies["calendar_admin"]
    delete "/api/v1/admin/session", headers: headers
    expect(response).to have_http_status(:no_content)
    OpenapiContract.validate!(request, response)
    client = ActionDispatch::Integration::Session.new(Rails.application)
    client.get "/api/v1/admin/session", headers: { "Cookie" => "calendar_admin=#{token}" }
    expect(client.response).to have_http_status(:unauthorized)
    expect(client.response.body).not_to include("owner")
    OpenapiContract.validate!(client.request, client.response)
  end

  it "limits all login attempts to ten per IP for fifteen minutes without leaking credentials" do
    travel_to Time.utc(2026, 11, 13, 10) do
      10.times do
        login(password: "wrong")
        expect(response).to have_http_status(:unauthorized)
      end
      login
      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers["Retry-After"]).to eq("900")
      expect(response.body).not_to include("owner", password)
      travel 899.seconds
      login
      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers["Retry-After"]).to eq("1")
      travel 1.second
      login
      expect(response).to have_http_status(:ok)
    end
  end

  it "rejects cross-origin login and logout and leaves the existing session valid" do
    login
    delete "/api/v1/admin/session", headers: headers.merge("Origin" => "https://attacker.example")
    expect(response).to have_http_status(:forbidden)
    OpenapiContract.validate!(request, response)
    delete "/api/v1/admin/session"
    expect(response).to have_http_status(:forbidden)
    get "/api/v1/admin/session"
    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to eq("no-store")
    post "/api/v1/admin/session", params: { username: "owner", password: password },
      headers: headers.merge("Origin" => "https://attacker.example"), as: :json
    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include(password)
    OpenapiContract.validate!(request, response)
  end

  it "fails closed without configured credentials and has no registration or reset endpoint" do
    ENV.delete("ADMIN_PASSWORD")
    login
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq("message" => "Invalid username or password")
    %w[registration password reset].each do |path|
      post "/api/v1/admin/#{path}", params: { username: "owner", password: password }, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  it "never authenticates a truncated password" do
    ENV["ADMIN_PASSWORD"] = "a" * 1024
    login(password: "#{'a' * 1024}wrong")
    expect(response).to have_http_status(:unauthorized)
  end
end
