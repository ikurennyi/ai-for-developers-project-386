require "rails_helper"
require_relative "../support/openapi_contract"

RSpec.describe "Administrator form authentication recovery", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:headers) { { "X-Calendar-Request" => "1" } }

  around do |example|
    previous = ENV.to_h.slice("ADMIN_USERNAME", "ADMIN_PASSWORD")
    ENV["ADMIN_USERNAME"] = "recovery-owner"
    ENV["ADMIN_PASSWORD"] = "recovery-test-password!"
    example.run
  ensure
    %w[ADMIN_USERNAME ADMIN_PASSWORD].each { |key| ENV[key] = previous[key] }
  end

  def login
    post "/api/v1/admin/session",
      params: { username: ENV.fetch("ADMIN_USERNAME"), password: ENV.fetch("ADMIN_PASSWORD") },
      headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    OpenapiContract.validate!(request, response)
  end

  it "rejects Save and Publish at absolute expiry and changes nothing merely by logging in again" do
    travel_to Time.utc(2026, 11, 13, 10) do
      login
      details = { name: "Saved offer", description: "Saved description", durationMinutes: 20, slug: "saved-recovery" }
      post "/api/v1/admin/meeting-types", params: details, headers: headers, as: :json
      expect(response).to have_http_status(:created)
      OpenapiContract.validate!(request, response)
      id = response.parsed_body.fetch("id")
      token = cookies["calendar_admin"]
      travel 24.hours
      # Replay even the expired browser cookie: the API is the authority.
      expired = ActionDispatch::Integration::Session.new(Rails.application)
      expired_headers = headers.merge("Cookie" => "calendar_admin=#{token}")
      [
        [ :post, "/api/v1/admin/meeting-types", details.merge(slug: "expired-new") ],
        [ :put, "/api/v1/admin/meeting-types/#{id}", details.merge(name: "Expired edit") ],
        [ :put, "/api/v1/admin/meeting-types/#{id}/publication", { published: true } ]
      ].each do |method, path, body|
        expired.public_send(method, path, params: body, headers: expired_headers, as: :json)
        expect(expired.response).to have_http_status(:unauthorized)
        expect(expired.response.parsed_body).to eq("message" => "Authentication required")
        expect(expired.response.headers["Cache-Control"]).to include("no-store")
        OpenapiContract.validate!(expired.request, expired.response)
      end
      login
      get "/api/v1/admin/meeting-types"
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch("meetingTypes")).to contain_exactly(
        include("id" => id, "name" => "Saved offer", "description" => "Saved description",
          "durationMinutes" => 20, "slug" => "saved-recovery", "published" => false)
      )
      OpenapiContract.validate!(request, response)
      put "/api/v1/admin/meeting-types/#{id}", params: details.merge(name: "Explicit edit"), headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("name" => "Explicit edit", "published" => false)
      OpenapiContract.validate!(request, response)
    end
  end
end
