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

@doc("An English API error without credentials or private data.")
@example(#{ message: "Authentication required" })
model AuthError {
  @doc("Safe explanation of the failure.")
  @example("Authentication required")
  message: string;
}

@doc("The single administrator's current session. Expiry never slides.")
@example(#{ username: "owner", expiresAt: utcDateTime.fromISO("2026-11-14T10:00:00Z") })
model AdminSession {
  @doc("Configured administrator username.")
  @example("owner")
  username: string;
  @doc("Absolute session expiry, 24 hours after login.")
  @example(utcDateTime.fromISO("2026-11-14T10:00:00Z"))
  expiresAt: utcDateTime;
}

@doc("Initial credentials are configured by the operator, not public defaults.")
@example(#{ username: "owner", password: "example-not-a-default-password" })
model Credentials {
  @doc("Administrator username.")
  @example("owner")
  username: string;
  @doc("Administrator password.")
  @example("example-not-a-default-password")
  password: string;
}

@error
@doc("No valid administrator session.")
model Unauthenticated {
  @statusCode statusCode: 401;
  @body body: AuthError;
}

@error
@doc("The browser request failed same-origin protection.")
model Forbidden {
  @statusCode statusCode: 403;
  @body body: AuthError;
}

@error
@doc("Ten login attempts per IP per 15-minute window have been used.")
model RateLimited {
  @statusCode statusCode: 429;
  @header("Retry-After") retryAfter: int32;
  @body body: AuthError;
}

@doc("Opaque HttpOnly SameSite=Strict cookie, Secure in production.")
model AdminCookie is ApiKeyAuth<ApiKeyLocation.cookie, "calendar_admin">;

@route("/admin/session")
@tag("Administrator authentication")
interface Authentication {
  @post
  @operationId("loginAdmin")
  @summary("Log in to the single administrator account")
  @doc("Creates a 24-hour session. Requires X-Calendar-Request: 1 and same-origin browser requests. Sets an HttpOnly cookie. Credentials errors are always generic. Ten attempts per IP per 15 minutes, shared through PostgreSQL.")
  login(
    @doc("Required custom header; cross-origin browsers must preflight and are not granted CORS access.")
    @header("X-Calendar-Request") calendarRequest: "1",
    @doc("The operator-configured username and password.")
    @body credentials: Credentials
  ): AdminSession | Unauthenticated | Forbidden | RateLimited;

  @get
  @useAuth(AdminCookie)
  @operationId("getAdminSession")
  @summary("Read the current administrator session")
  @doc("Requires the session cookie; never extends expiry. Responses are not cacheable.")
  current(): AdminSession | Unauthenticated;

  @delete
  @useAuth(AdminCookie)
  @operationId("logoutAdmin")
  @summary("Revoke the current administrator session")
  @doc("Immediately revokes the cookie's session. Requires X-Calendar-Request: 1; safe to repeat.")
  logout(
    @doc("Required custom header protecting against cross-origin form submissions.")
    @header("X-Calendar-Request") calendarRequest: "1"
  ): {
    @statusCode statusCode: 204;
  } | Forbidden;
}

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

@doc("A schedule-valid interval. Availability is advisory and never reserves time.")
@example(#{ startsAt: utcDateTime.fromISO("2026-11-13T13:15:00Z"), endsAt: utcDateTime.fromISO("2026-11-13T13:35:00Z"), available: true })
model CalendarInterval {
  @doc("Exact start instant on the Berlin quarter-hour grid.")
  startsAt: utcDateTime;
  @doc("Exact end instant, including the full meeting duration.")
  endsAt: utcDateTime;
  @doc("True only for future intervals without shared occupancy.")
  available: boolean;
}

@doc("A Berlin calendar date in the booking window.")
@example(#{ date: plainDate.fromISO("2026-11-14"), workingDay: false, intervals: #[] })
model CalendarDay {
  @doc("ISO local date in Europe/Berlin.")
  date: plainDate;
  @doc("Monday through Friday; weekends still count toward the window.")
  workingDay: boolean;
  @doc("Schedule-valid intervals, empty on weekends.")
  intervals: CalendarInterval[];
}

@doc("Public calendar snapshot calculated using server time, without guest or occupancy details.")
@example(#{
  meetingType: #{ id: "29a71c26-c842-407d-bcd2-e93c8ea0ceab", name: "Discussion", description: "", durationMinutes: 20, slug: "discussion" },
  hostName: "Alex Morgan", timeZone: "Europe/Berlin",
  serverNow: utcDateTime.fromISO("2026-11-13T13:07:00Z"),
  today: plainDate.fromISO("2026-11-13"), windowEnd: plainDate.fromISO("2026-11-26"),
  days: #[#{ date: plainDate.fromISO("2026-11-13"), workingDay: true, intervals: #[
    #{ startsAt: utcDateTime.fromISO("2026-11-13T13:15:00Z"), endsAt: utcDateTime.fromISO("2026-11-13T13:35:00Z"), available: true }
  ] }]
})
model Availability {
  @doc("The current published offer.")
  @example(#{ id: "29a71c26-c842-407d-bcd2-e93c8ea0ceab", name: "Discussion", description: "", durationMinutes: 20, slug: "discussion" })
  meetingType: MeetingType;
  @doc("Predetermined public host name, never an email address.")
  @example("Alex Morgan")
  hostName: string;
  @doc("The fixed schedule and display time zone.")
  @example("Europe/Berlin")
  timeZone: "Europe/Berlin";
  @doc("Server instant used to calculate this snapshot.")
  @example(utcDateTime.fromISO("2026-11-13T13:07:00Z"))
  serverNow: utcDateTime;
  @doc("Today's Berlin date.")
  @example(plainDate.fromISO("2026-11-13"))
  today: plainDate;
  @doc("Inclusive last Berlin date: today plus thirteen calendar dates.")
  @example(plainDate.fromISO("2026-11-26"))
  windowEnd: plainDate;
  @doc("All fourteen dates, including weekends.")
  @example(#[#{ date: plainDate.fromISO("2026-11-14"), workingDay: false, intervals: #[] }])
  days: CalendarDay[];
}

@doc("Indistinguishable response for hidden and nonexistent meeting types.")
@example(#{ message: "Meeting type unavailable" })
model MeetingTypeUnavailable {
  @doc("Safe public explanation.")
  message: "Meeting type unavailable";
}

@get
@route("/meeting-types/{slug}/availability")
@tag("Meeting types")
@operationId("getAvailability")
@summary("Get a public meeting calendar")
@doc("Return fourteen Berlin dates with advisory shared availability. Reading never creates a booking or reserves an interval.")
op getAvailability(
  @doc("Current public address segment.") @path slug: string,
): {
  @statusCode statusCode: 200;
  @header contentType: "application/json";
  @body body: Availability;
} | {
  @statusCode statusCode: 404;
  @header contentType: "application/json";
  @body body: MeetingTypeUnavailable;
};
