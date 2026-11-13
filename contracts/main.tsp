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

@doc("A published offer available for guest booking.")
@example(#{ id: "29a71c26-c842-407d-bcd2-e93c8ea0ceab", name: "Short meeting", description: "A quick conversation.", durationMinutes: 15, slug: "short-meeting" })
model MeetingType {
  @doc("Immutable system-assigned identifier.")
  id: string;
  @doc("Meeting name.")
  name: string;
  @doc("Optional meeting description; empty when not supplied.")
  description: string;
  @doc("Meeting duration in whole minutes.")
  @minValue(1)
  @maxValue(540)
  durationMinutes: int32;
  @doc("Current unique public address segment.")
  slug: string;
}

@doc("The available public meeting offers.")
@example(#{ meetingTypes: #[] })
model MeetingTypeList {
  @doc("Published offers, or an empty array when none are available.")
  meetingTypes: MeetingType[];
}

@get
@route("/meeting-types")
@tag("Meeting types")
@operationId("listMeetingTypes")
@summary("List published meeting types")
@doc("Return every published offer. Hidden offers are never included.")
op listMeetingTypes(): {
  @statusCode statusCode: 200;
  @header contentType: "application/json";
  @body body: MeetingTypeList;
};
