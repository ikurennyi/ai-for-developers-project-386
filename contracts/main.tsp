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
  @example("29a71c26-c842-407d-bcd2-e93c8ea0ceab")
  id: string;
  @doc("Meeting name.")
  @example("Short meeting")
  name: string;
  @doc("Optional meeting description; empty when not supplied.")
  @example("A quick conversation.")
  description: string;
  @doc("Meeting duration in whole minutes.")
  @example(15)
  @minValue(1)
  @maxValue(540)
  durationMinutes: int32;
  @doc("Current unique public address segment.")
  @example("short-meeting")
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

@doc("An administrator-visible offer, including hidden drafts.")
@example(#{ id: "29a71c26-c842-407d-bcd2-e93c8ea0ceab", name: "Planning", description: "", durationMinutes: 20, slug: "planning", published: false })
model AdminMeetingType {
  ...MeetingType;
  @doc("True only after a separate publication action.")
  @example(true)
  published: boolean;
}

@doc("All meeting types in creation order.")
@example(#{ meetingTypes: #[] })
model AdminMeetingTypeList {
  @doc("Published and hidden offers.")
  meetingTypes: AdminMeetingType[];
}

@doc("New hidden meeting type. Trim name and address at their edges only. Description consisting only of whitespace becomes empty. Unknown fields cannot assign identity or publication.")
@example(#{ name: "Planning", description: "", durationMinutes: 20, slug: "planning" })
model NewMeetingType {
  @doc("After trimming: 1–100 characters.")
  name: string;
  @doc("Optional description, at most 2000 characters.")
  description?: string;
  @doc("A whole number from 1 to 540, not restricted to a 15-minute multiple.")
  durationMinutes: int32;
  @doc("After trimming: 1–80 lowercase Latin letters/digits with single hyphens between nonempty parts. Unique among all offers; never silently renamed.")
  slug: string;
}

@doc("English errors keyed by the form's field names.")
@example(#{ name: #["can't be blank"], description: #["is too long (maximum is 2000 characters)"], durationMinutes: #["must be a whole number from 1 to 540"], slug: #["has already been taken"] })
model MeetingTypeFieldErrors {
  @doc("Name errors.")
  name?: string[];
  @doc("Description errors.")
  description?: string[];
  @doc("Duration errors.")
  durationMinutes?: string[];
  @doc("Address errors, including concurrent collisions.")
  slug?: string[];
}

@error
@doc("The offer was not saved; preserve the form and correct these fields.")
model InvalidMeetingType {
  @statusCode statusCode: 422;
  @body body: {
    @doc("Safe English summary.")
    @example("Please correct the highlighted fields.")
    message: string;
    @doc("Errors beside the relevant fields.")
    @example(#{ slug: #["has already been taken"] })
    errors: MeetingTypeFieldErrors;
  };
}

@route("/admin/meeting-types")
@tag("Administrator meeting types")
@useAuth(AdminCookie)
interface AdminMeetingTypes {
  @get
  @operationId("listAdminMeetingTypes")
  @summary("List all meeting types")
  @doc("Requires administrator access. Includes hidden drafts and publication state; responses are not cacheable.")
  list(): AdminMeetingTypeList | Unauthenticated;

  @post
  @operationId("createAdminMeetingType")
  @summary("Create a hidden meeting type")
  @doc("Save never publishes. Requires same-origin protection. Invalid input or an occupied address returns field errors without saving or renaming.")
  create(
    @doc("Required mutation protection header.")
    @header("X-Calendar-Request") calendarRequest: "1",
    @doc("The administrator's explicit offer details.")
    @body body: NewMeetingType
  ): {
    @statusCode statusCode: 201;
    @body body: AdminMeetingType;
  } | InvalidMeetingType | Unauthenticated | Forbidden;
}

@error
@doc("The administrative meeting type does not exist.")
model AdminMeetingTypeNotFound {
  @statusCode statusCode: 404;
  @body body: AuthError;
}

@doc("Explicit desired publication state; saving details never changes this state.")
@example(#{ published: true })
model MeetingTypePublication {
  @doc("Publish for new bookings, or hide without changing existing bookings or occupancy.")
  published: boolean;
}

@route("/admin/meeting-types/{id}")
@tag("Administrator meeting types")
@useAuth(AdminCookie)
interface ManageMeetingType {
  @get
  @operationId("getAdminMeetingType")
  @summary("Read meeting type details for editing")
  @doc("Requires administrator access; hidden offers are included. Responses are not cacheable.")
  read(@doc("Immutable system-assigned identifier.") @path id: string):
    AdminMeetingType | AdminMeetingTypeNotFound | Unauthenticated;

  @put
  @operationId("updateAdminMeetingType")
  @summary("Save meeting type details without changing publication")
  @doc("Uses creation validation. Identity is immutable. A changed address immediately releases the old address without redirecting it. Existing booking snapshots and occupancy are unchanged.")
  update(
    @doc("Immutable system-assigned identifier.") @path id: string,
    @doc("Required mutation protection header.") @header("X-Calendar-Request") calendarRequest: "1",
    @doc("Complete editable details; omitted description is empty.") @body body: NewMeetingType
  ): AdminMeetingType | InvalidMeetingType | AdminMeetingTypeNotFound | Unauthenticated | Forbidden;

  @put
  @route("/publication")
  @operationId("setAdminMeetingTypePublication")
  @summary("Publish, hide or republish a meeting type")
  @doc("Explicit idempotent state change, separate from Save. Hiding prevents new bookings but preserves existing snapshots and occupancy. Only successful responses confirm the new state.")
  publication(
    @doc("Immutable system-assigned identifier.") @path id: string,
    @doc("Required mutation protection header.") @header("X-Calendar-Request") calendarRequest: "1",
    @doc("Explicit desired state.") @body body: MeetingTypePublication
  ): AdminMeetingType | InvalidMeetingType | AdminMeetingTypeNotFound | Unauthenticated | Forbidden;
}

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

@doc("Meeting details explicitly reviewed by the guest, checked again at confirmation.")
@example(#{ name: "Discussion", description: "", durationMinutes: 20 })
model ReviewedMeeting {
  @doc("Reviewed meeting name.") name: string;
  @doc("Reviewed description.") description: string;
  @doc("Reviewed duration in minutes.") durationMinutes: int32;
}

@doc("An explicit confirmation; reading availability never creates this record.")
@example(#{ startsAt: utcDateTime.fromISO("2026-11-13T09:00:00Z"), meetingType: #{ name: "Discussion", description: "", durationMinutes: 20 }, guestName: "Guest", guestEmail: "guest@example.com", notes: "" })
model BookingConfirmation {
  @doc("Exact selected start instant.") startsAt: utcDateTime;
  @doc("Details the guest reviewed.") meetingType: ReviewedMeeting;
  @doc("Guest name, trimmed to 1–100 characters.") guestName: string;
  @doc("Required email, at most 254 characters.") guestEmail: string;
  @doc("Optional plain-text notes, at most 2000 characters.") notes?: string;
}

@doc("A persisted snapshot returned to its creating request or the authenticated administrator; there is no public booking lookup.")
@example(#{ id: "29a71c26-c842-407d-bcd2-e93c8ea0ceab", meetingName: "Discussion", meetingDescription: "", durationMinutes: 20, hostName: "Alex Morgan", timeZone: "Europe/Berlin", startsAt: utcDateTime.fromISO("2026-11-13T09:00:00Z"), endsAt: utcDateTime.fromISO("2026-11-13T09:20:00Z"), guestName: "Guest", guestEmail: "guest@example.com", notes: "" })
model Booking {
  @doc("System identifier, not a public access credential.") id: string;
  @doc("Saved meeting name.") meetingName: string;
  @doc("Saved description.") meetingDescription: string;
  @doc("Saved duration.") durationMinutes: int32;
  @doc("Fixed calendar owner.") hostName: string;
  @doc("Fixed display zone.") timeZone: "Europe/Berlin";
  @doc("Exact saved start.") startsAt: utcDateTime;
  @doc("Exact saved end.") endsAt: utcDateTime;
  @doc("Trimmed name.") guestName: string;
  @doc("Guest email.") guestEmail: string;
  @doc("Plain-text notes.") notes: string;
}

@doc("Unfinished bookings sharing a start date in Europe/Berlin.")
@example(#{ date: plainDate.fromISO("2026-11-13"), bookings: #[] })
model AdminHomeDay {
  @doc("Berlin start date.") @example(plainDate.fromISO("2026-11-13")) date: plainDate;
  @doc("Saved bookings ordered by start ascending, then identifier.") @example(#[]) bookings: Booking[];
}

@doc("All ongoing and future bookings, without a creation-window limit or pagination.")
@example(#{ timeZone: "Europe/Berlin", days: #[] })
model AdminHome {
  @doc("Fixed display zone.") @example("Europe/Berlin") timeZone: "Europe/Berlin";
  @doc("Berlin days ascending; empty when no booking has an end strictly after server now.")
  @example(#[])
  days: AdminHomeDay[];
}

@get
@route("/admin/home")
@tag("Administrator Home")
@useAuth(AdminCookie)
@operationId("getAdminHome")
@summary("Read all unfinished bookings grouped by Berlin day")
@doc("Requires administrator access. Includes ongoing bookings and every future booking, including hidden types and dates beyond the creation window. End equal to server now is excluded. Returns saved snapshots and full plain-text guest details. Responses are no-store.")
op getAdminHome(): AdminHome | Unauthenticated;

@doc("One page of retained administrator booking snapshots.")
@example(#{ bookings: #[], page: 1, pageSize: 20, total: 0 })
model AdminBookingPage {
  @doc("Saved meeting and guest details in the requested order.")
  @example(#[#{ id: "29a71c26-c842-407d-bcd2-e93c8ea0ceab", meetingName: "Discussion", meetingDescription: "", durationMinutes: 20, hostName: "Alex Morgan", timeZone: "Europe/Berlin", startsAt: utcDateTime.fromISO("2026-11-13T09:00:00Z"), endsAt: utcDateTime.fromISO("2026-11-13T09:20:00Z"), guestName: "Guest", guestEmail: "guest@example.com", notes: "" }])
  bookings: Booking[];
  @doc("Requested one-based page.") @example(1) @minValue(1) page: int32;
  @doc("Fixed maximum records per page.") @example(20) pageSize: 20;
  @doc("Total matching records, not limited by the creation window.") @example(0) @minValue(0) total: int32;
}

@get
@route("/admin/bookings")
@tag("Administrator bookings")
@useAuth(AdminCookie)
@operationId("listAdminBookings")
@summary("Read upcoming bookings or retained history")
@doc("Private, non-cacheable snapshots. Upcoming includes ongoing meetings (end > server now), ordered by start ascending; Past uses end <= now and start descending. Equal starts use identifier order. No creation-window limit. Pages contain at most 20 bookings.")
op listAdminBookings(
  @doc("Defaults to Upcoming.") @query period?: "upcoming" | "past",
  @doc("One-based page; defaults to 1. Beyond the last page returns an empty array.") @query @minValue(1) page?: int32
): AdminBookingPage | Unauthenticated | {
  @statusCode statusCode: 400;
  @body body: AuthError;
};

@delete
@route("/admin/bookings/{id}")
@tag("Administrator bookings")
@useAuth(AdminCookie)
@operationId("deleteAdminBooking")
@summary("Permanently delete a booking")
@doc("Requires explicit administrator confirmation and same-origin protection. Atomically removes the booking and its shared occupancy; failures change neither. No trash, restoration or cancellation status. Freed time remains subject to schedule, current time, window and other occupancy.")
op deleteAdminBooking(
  @doc("Saved booking identifier.") @path id: string,
  @doc("Required mutation protection header.") @header("X-Calendar-Request") calendarRequest: "1"
): {
  @statusCode statusCode: 204;
} | Unauthenticated | Forbidden | {
  @statusCode statusCode: 404;
  @body body: AuthError;
} | {
  @statusCode statusCode: 503;
  @body body: AuthError;
};

@doc("English field validation messages; absent keys have no error.")
@example(#{ guestName: "Enter your name (1–100 characters)." })
model GuestErrors {
  @doc("Name error.") guestName?: string;
  @doc("Email error.") guestEmail?: string;
  @doc("Notes error.") notes?: string;
}

@doc("A rejected confirmation. Codes distinguish changed terms, invalid schedule and shared occupancy.")
@example(#{ code: "occupied", message: "This time is no longer available. Please choose another time." })
model BookingError {
  @doc("Machine-readable reason.") code: "validation" | "details_changed" | "invalid_interval" | "occupied";
  @doc("English explanation.") message: string;
  @doc("Field errors for invalid guest data.") errors?: GuestErrors;
}

@post
@route("/meeting-types/{slug}/bookings")
@tag("Bookings")
@operationId("confirmBooking")
@summary("Explicitly confirm a meeting")
@doc("Atomically rechecks current publication, reviewed details, schedule and shared occupancy. Returns a private creation response with no public read endpoint. All responses are no-store.")
op confirmBooking(
  @doc("Current published address.") @path slug: string,
  @doc("Reviewed meeting, selected instant and guest details.") @body confirmation: BookingConfirmation,
): {
  @statusCode statusCode: 201;
  @body body: Booking;
} | {
  @statusCode statusCode: 422;
  @body body: BookingError;
} | {
  @statusCode statusCode: 409;
  @body body: BookingError;
} | {
  @statusCode statusCode: 404;
  @body body: MeetingTypeUnavailable;
};
