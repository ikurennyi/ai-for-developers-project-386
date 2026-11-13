require "rails_helper"
require_relative "../support/openapi_contract"

RSpec.describe "Published meeting types", type: :request do
  it "returns a contract-valid empty list when all offers are hidden" do
    MeetingType.create!(name: "Hidden", duration_minutes: 15, slug: "hidden")
    get "/api/v1/meeting-types"
    expect(JSON.parse(response.body)).to eq("meetingTypes" => [])
    OpenapiContract.validate!(request, response)
  end

  it "initializes offers once without restoring changed names, addresses, durations or publication" do
    Rails.application.load_seed
    get "/api/v1/meeting-types"
    original = JSON.parse(response.body).fetch("meetingTypes")
    expect(original.map { |type| type.fetch("durationMinutes") }).to contain_exactly(15, 30)
    changed = MeetingType.find(original.first.fetch("id"))
    changed.update!(name: "Updated offer", description: "Edited", slug: "updated-offer",
      duration_minutes: 20, published: false)

    Rails.application.load_seed
    get "/api/v1/meeting-types"
    expect(JSON.parse(response.body).fetch("meetingTypes").map { |type| type.fetch("id") })
      .to eq([ original.last.fetch("id") ])
    changed.update!(published: true)
    get "/api/v1/meeting-types"
    expect(JSON.parse(response.body).fetch("meetingTypes")).to include(
      hash_including("id" => original.first.fetch("id"), "name" => "Updated offer",
        "description" => "Edited", "slug" => "updated-offer", "durationMinutes" => 20)
    )
  end

  it "lists every published offer without disclosing hidden offers" do
    MeetingType.create!(name: "Focused discussion", description: "A specific topic", duration_minutes: 20,
      slug: "focused-discussion", published: true)
    MeetingType.create!(name: "Private offer", duration_minutes: 45, slug: "private-offer")

    get "/api/v1/meeting-types"

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).fetch("meetingTypes")).to contain_exactly(
      hash_including("name" => "Focused discussion", "description" => "A specific topic",
        "durationMinutes" => 20, "slug" => "focused-discussion", "id" => kind_of(String))
    )
    OpenapiContract.validate!(request, response)
  end
end
