require "rails_helper"

RSpec.describe "API health", type: :request do
  it "returns the agreed healthy JSON response" do
    get "/api/v1/health"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    expect(response.parsed_body).to eq("status" => "ok")
  end
end
