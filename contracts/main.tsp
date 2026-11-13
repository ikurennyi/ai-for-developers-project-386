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
