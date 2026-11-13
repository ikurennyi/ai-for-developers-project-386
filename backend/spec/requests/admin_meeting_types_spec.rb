require "rails_helper"
require_relative "../support/openapi_contract"

RSpec.describe "Administrator meeting types", type: :request do
  let(:headers) { { "X-Calendar-Request" => "1" } }
  let(:attributes) { { name: "  Planning  ", description: " \n ", durationMinutes: 20, slug: " planning-20 " } }

  around do |example|
    previous = ENV.to_h.slice("ADMIN_USERNAME", "ADMIN_PASSWORD")
    ENV["ADMIN_USERNAME"] = "types-owner"
    ENV["ADMIN_PASSWORD"] = "types-test-password!"
    example.run
  ensure
    %w[ADMIN_USERNAME ADMIN_PASSWORD].each { |key| ENV[key] = previous[key] }
  end

  def login
    post "/api/v1/admin/session",
      params: { username: "types-owner", password: ENV.fetch("ADMIN_PASSWORD") }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
  end

  def create_type(params = attributes)
    post "/api/v1/admin/meeting-types", params: params, headers: headers, as: :json
  end

  it "requires authentication and same-origin mutation protection" do
    get "/api/v1/admin/meeting-types"
    expect(response).to have_http_status(:unauthorized)
    create_type
    expect(response).to have_http_status(:unauthorized)
    login
    post "/api/v1/admin/meeting-types", params: attributes, as: :json
    expect(response).to have_http_status(:forbidden)
    OpenapiContract.validate!(request, response, validate_request: false)
    get "/api/v1/admin/meeting-types"
    expect(response.parsed_body["meetingTypes"]).to eq([])
  end

  it "creates only a hidden type with a system identifier and lists it only for the administrator" do
    login
    create_type(attributes.merge(published: true, id: "user-chosen"))
    expect(response).to have_http_status(:created)
    OpenapiContract.validate!(request, response, validate_request: false)
    type = response.parsed_body
    expect(type).to include("name" => "Planning", "description" => "", "durationMinutes" => 20,
      "slug" => "planning-20", "published" => false)
    expect(type["id"]).to match(/\A[0-9a-f-]{36}\z/)
    get "/api/v1/admin/meeting-types"
    expect(response.parsed_body["meetingTypes"]).to eq([ type ])
    OpenapiContract.validate!(request, response)
    get "/api/v1/meeting-types"
    expect(response.parsed_body["meetingTypes"]).to eq([])
  end

  it "rejects invalid fields independently of browser restrictions without saving" do
    login
    invalid = {
      name: [ "", " \n ", "a" * 101, nil, 123, [ "name" ] ],
      description: [ "a" * 2001, 123, [ "description" ] ],
      durationMinutes: [ 0, 541, 1.5, "20", "20minutes", true, nil ],
      slug: [ "", "A", "-a", "a-", "a--b", "a b", "a_b", "a/b", "é", "a" * 81, nil, 123 ]
    }
    invalid.each do |field, values|
      values.each do |value|
        create_type(attributes.merge(field => value))
        expect(response).to have_http_status(:unprocessable_content), "#{field}=#{value.inspect}: #{response.body}"
        expect(response.parsed_body.fetch("errors")).to have_key(field.to_s)
        OpenapiContract.validate!(request, response, validate_request: false)
      end
    end
    get "/api/v1/admin/meeting-types"
    expect(response.parsed_body["meetingTypes"]).to eq([])
  end

  it "accepts inclusive limits, arbitrary whole minutes, Unicode names and optional descriptions" do
    login
    [ 1, 20, 45, 90, 540 ].each_with_index do |duration, index|
      create_type(name: index.zero? ? "名" * 100 : "X", durationMinutes: duration,
        slug: index.zero? ? "a" * 80 : "limit-#{index}", description: index.zero? ? "é" * 2000 : "")
      expect(response).to have_http_status(:created)
      OpenapiContract.validate!(request, response)
      expect(response.parsed_body["durationMinutes"]).to eq(duration)
    end
    create_type(name: "No description", durationMinutes: 7, slug: "optional-description")
    expect(response).to have_http_status(:created)
    expect(response.parsed_body["description"]).to eq("")
  end

  it "trims surrounding Unicode whitespace without changing the address's case or interior" do
    login
    create_type(name: "\u00a0Name\u3000", slug: "\u00a0unicode-edge\u3000", durationMinutes: 1)
    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include("name" => "Name", "slug" => "unicode-edge")
  end

  it "empties all ECMAScript trim whitespace before description length validation, preserving nonempty text exactly" do
    login
    whitespace = " \t\n\v\f\r\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000\ufeff"
    [ whitespace, "\ufeff" * 2001, " " * 2001, whitespace * 100, "#{whitespace}Text#{whitespace}", "\u0085" ].each_with_index do |description, index|
      create_type(name: "#{whitespace}Name#{whitespace}", slug: "#{whitespace}whitespace-#{index}#{whitespace}",
        durationMinutes: 20, description: description)
      expect(response).to have_http_status(:created)
      OpenapiContract.validate!(request, response)
      expected = index < 4 ? "" : description
      expect(response.parsed_body).to include("name" => "Name", "slug" => "whitespace-#{index}", "description" => expected)
      id = response.parsed_body.fetch("id")
      put "/api/v1/admin/meeting-types/#{id}",
        params: { name: "Name", slug: "whitespace-#{index}", durationMinutes: 20, description: description },
        headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      OpenapiContract.validate!(request, response)
      expect(response.parsed_body["description"]).to eq(expected)
    end
  end

  it "reports address collisions with both published and hidden types without automatic suffixes" do
    MeetingType.create!(name: "Published", duration_minutes: 15, slug: "published", published: true)
    login
    create_type
    expect(response).to have_http_status(:created)
    [ "published", " planning-20 " ].each do |slug|
      create_type(attributes.merge(slug: slug))
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("errors", "slug")).to include("has already been taken")
      OpenapiContract.validate!(request, response)
    end
    get "/api/v1/admin/meeting-types"
    expect(response.parsed_body["meetingTypes"].map { |type| type["slug"] }).to eq([ "published", "planning-20" ])
  end
end
