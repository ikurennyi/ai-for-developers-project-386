require "rails_helper"
require_relative "../support/openapi_contract"

RSpec.describe "Managing meeting types", type: :request do
  let(:headers) { { "X-Calendar-Request" => "1" } }
  let(:details) { { name: " Updated ", description: "New details", durationMinutes: 45, slug: " new-address " } }

  around do |example|
    previous = ENV.to_h.slice("ADMIN_USERNAME", "ADMIN_PASSWORD")
    ENV["ADMIN_USERNAME"] = "manage-owner"
    ENV["ADMIN_PASSWORD"] = "manage-test-password!"
    example.run
  ensure
    %w[ADMIN_USERNAME ADMIN_PASSWORD].each { |key| ENV[key] = previous[key] }
  end

  def login
    post "/api/v1/admin/session", params: { username: ENV.fetch("ADMIN_USERNAME"), password: ENV.fetch("ADMIN_PASSWORD") },
      headers: headers, as: :json
    expect(response).to have_http_status(:ok)
  end

  def publish(id, published)
    put "/api/v1/admin/meeting-types/#{id}/publication", params: { published: published }, headers: headers, as: :json
  end

  it "edits immutable-identity details without publishing, then independently publishes, hides and republishes" do
    login
    post "/api/v1/admin/meeting-types", params: { name: "Original", durationMinutes: 20, slug: "original" },
      headers: headers, as: :json
    id = response.parsed_body.fetch("id")
    get "/api/v1/admin/meeting-types/#{id}"
    expect(response).to have_http_status(:ok)
    OpenapiContract.validate!(request, response)
    put "/api/v1/admin/meeting-types/#{id}", params: details.merge(id: "replacement", published: true),
      headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("id" => id, "name" => "Updated", "slug" => "new-address",
      "description" => "New details", "durationMinutes" => 45, "published" => false)
    OpenapiContract.validate!(request, response, validate_request: false)
    [ true, false, true ].each do |published|
      publish(id, published)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("id" => id, "published" => published)
      OpenapiContract.validate!(request, response)
      get "/api/v1/meeting-types"
      expect(response.parsed_body.fetch("meetingTypes").map { |type| type["id"] }).to eq(published ? [ id ] : [])
      get "/api/v1/meeting-types/new-address/availability"
      expect(response.status).to eq(published ? 200 : 404)
      OpenapiContract.validate!(request, response)
    end
  end

  it "protects reads and writes, rejects malformed publication and provides contract errors for missing offers" do
    type = MeetingType.create!(name: "Protected", duration_minutes: 20, slug: "protected")
    get "/api/v1/admin/meeting-types/#{type.id}"
    expect(response).to have_http_status(:unauthorized)
    OpenapiContract.validate!(request, response)
    put "/api/v1/admin/meeting-types/#{type.id}", params: details, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    OpenapiContract.validate!(request, response)
    publish(type.id, true)
    expect(response).to have_http_status(:unauthorized)
    OpenapiContract.validate!(request, response)
    login
    [ "/api/v1/admin/meeting-types/#{type.id}", "/api/v1/admin/meeting-types/#{type.id}/publication" ].each do |path|
      put path, params: details, as: :json
      expect(response).to have_http_status(:forbidden)
      OpenapiContract.validate!(request, response, validate_request: false)
    end
    [ nil, "true", 1, [], {} ].each do |value|
      publish(type.id, value)
      expect(response).to have_http_status(:unprocessable_content)
      OpenapiContract.validate!(request, response, validate_request: false)
    end
    get "/api/v1/admin/meeting-types/#{type.id}"
    expect(response.parsed_body).to include("name" => "Protected", "published" => false)
    [ "00000000-0000-0000-0000-000000000000", "invalid-id" ].each do |id|
      get "/api/v1/admin/meeting-types/#{id}"
      expect(response).to have_http_status(:not_found)
      OpenapiContract.validate!(request, response)
      put "/api/v1/admin/meeting-types/#{id}", params: details, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
      OpenapiContract.validate!(request, response)
      publish(id, true)
      expect(response).to have_http_status(:not_found)
      OpenapiContract.validate!(request, response)
    end
  end

  it "validates edited fields exactly like creation and leaves saved details and publication unchanged on errors" do
    type = MeetingType.create!(name: "Original", description: "Saved", duration_minutes: 20, slug: "original", published: true)
    MeetingType.create!(name: "Occupied", duration_minutes: 1, slug: "occupied")
    login
    invalid = {
      name: [ "", " \n ", "a" * 101, nil, 123, [ "name" ] ],
      description: [ "a" * 2001, 123, [ "description" ] ],
      durationMinutes: [ 0, 541, 1.5, "20", true, nil ],
      slug: [ "", "A", "-a", "a-", "a--b", "a b", "a_b", "a/b", "é", "a" * 81, nil, 123, "occupied" ]
    }
    invalid.each do |field, values|
      values.each do |value|
        put "/api/v1/admin/meeting-types/#{type.id}", params: details.merge(field => value), headers: headers, as: :json
        expect(response).to have_http_status(:unprocessable_content), "#{field}=#{value.inspect}: #{response.body}"
        expect(response.parsed_body.fetch("errors")).to have_key(field.to_s)
        OpenapiContract.validate!(request, response, validate_request: false)
      end
    end
    get "/api/v1/admin/meeting-types/#{type.id}"
    expect(response.parsed_body).to include("name" => "Original", "description" => "Saved",
      "slug" => "original", "durationMinutes" => 20, "published" => true)
    put "/api/v1/admin/meeting-types/#{type.id}",
      params: { name: "\u00a0名\u3000", slug: " original ", durationMinutes: 540 }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("id" => type.id, "name" => "名", "description" => "",
      "slug" => "original", "durationMinutes" => 540, "published" => true)
    OpenapiContract.validate!(request, response)
  end

  it "releases old addresses without redirects and keeps shared occupancy when editing or hiding" do
    type = MeetingType.create!(name: "Original", duration_minutes: 20, slug: "original", published: true)
    Occupancy.create!(starts_at: 1.day.from_now.beginning_of_day, ends_at: 15.days.from_now)
    login
    put "/api/v1/admin/meeting-types/#{type.id}", params: details, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    publish(type.id, false)
    expect(response).to have_http_status(:ok)
    bodies = [ "original", "new-address", "nonexistent" ].map do |slug|
      get "/api/v1/meeting-types/#{slug}/availability"
      expect(response).to have_http_status(:not_found)
      expect(response.headers["Location"]).to be_nil
      OpenapiContract.validate!(request, response)
      response.parsed_body
    end
    expect(bodies).to eq([ { "message" => "Meeting type unavailable" } ] * 3)
    post "/api/v1/admin/meeting-types", params: { name: "Reused", durationMinutes: 15, slug: "original" },
      headers: headers, as: :json
    expect(response).to have_http_status(:created)
    publish(response.parsed_body.fetch("id"), true)
    expect(response).to have_http_status(:ok)
    get "/api/v1/meeting-types/original/availability"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("meetingType", "name")).to eq("Reused")
    expect(response.parsed_body.fetch("days").drop(1).flat_map { |day| day.fetch("intervals") })
      .to all(include("available" => false))
    OpenapiContract.validate!(request, response)
  end
end
