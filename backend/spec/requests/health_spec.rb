require "rails_helper"
require_relative "../support/openapi_contract"

RSpec.describe "API health", type: :request do
  it "returns the agreed healthy JSON response" do
    get "/api/v1/health"

    expect { OpenapiContract.validate!(request, response) }.not_to raise_error
  end

  [ '{}', '{"status":"broken"}', '{"status":7}', '{"status":"ok","extra":true}', 'not-json' ].each do |body|
    it "rejects malformed response body #{body.inspect}" do
      get "/api/v1/health"
      response.body = body

      expect { OpenapiContract.validate!(request, response) }.to raise_error(Committee::InvalidResponse)
    end
  end

  it "rejects an undocumented HTTP status" do
    get "/api/v1/health"
    response.status = 201

    expect { OpenapiContract.validate!(request, response) }.to raise_error(Committee::InvalidResponse)
  end

  it "rejects an undocumented media type" do
    get "/api/v1/health"
    response.headers["content-type"] = "text/plain"

    expect { OpenapiContract.validate!(request, response) }.to raise_error(Committee::InvalidResponse)
  end
end
