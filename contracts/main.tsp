import "@typespec/http";
import "@typespec/openapi";

using TypeSpec.Http;
using TypeSpec.OpenAPI;

@service(#{ title: "Calendar API" })
@info(#{ version: "1.0.0" })
@doc("Technical API for the Calendar application.")
@server("/api/v1", "Same-origin API prefix")
namespace Calendar;

@doc("API process health; does not imply database readiness.")
@example(#{ status: "ok" })
model Health {
  @doc("The API process is responding.")
  @example("ok")
  status: "ok";
}

@get
@route("/health")
@tag("Health")
@operationId("getHealth")
@summary("Get API health")
@doc("Check API process health independently of database readiness.")
op getHealth(): {
  @statusCode statusCode: 200;
  @header contentType: "application/json";
  @body body: Health;
};
