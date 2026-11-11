require "committee"

# Validates the real request/response pair against the generated source of truth.
module OpenapiContract
  DOCUMENT = JSON.parse(File.read(File.expand_path("../../../contracts/generated/openapi.json", __dir__)))
  SCHEMA = Committee::Drivers.load_from_data(DOCUMENT, parser_options: { strict_reference_validation: true })

  def self.validate!(request, response)
    options = {
      schema: SCHEMA,
      prefix: DOCUMENT.fetch("servers").first.fetch("url"),
      strict: true,
      raise: true,
      validate_success_only: false
    }
    app = ->(_env) { [ response.status, response.headers.to_h, [ response.body ] ] }
    app = Committee::Middleware::ResponseValidation.new(app, **options)
    app = Committee::Middleware::RequestValidation.new(app, **options)
    app.call(request.env)
  end
end
