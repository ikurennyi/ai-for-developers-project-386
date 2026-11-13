# Keep the format, Unicode code-point limits and ECMAScript trim whitespace in
# sync with GuestBookingForm. Neither email nor notes are silently normalized.
class GuestDetails
  TRIM = /\A[\u0009-\u000D\u0020\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]+|[\u0009-\u000D\u0020\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]+\z/
  EMAIL = /\A[A-Za-z0-9!#$%&'*+\/=?^_`{|}~-]+(?:\.[A-Za-z0-9!#$%&'*+\/=?^_`{|}~-]+)*@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+\z/
  attr_reader :name, :email, :notes, :errors

  def initialize(name, email, notes)
    @name = name.is_a?(String) ? name.gsub(TRIM, "") : ""
    @email = email
    @notes = notes.nil? ? "" : notes
    @errors = {}
    @errors[:guestName] = "Enter your name (1–100 characters)." unless @name.length.between?(1, 100)
    unless email.is_a?(String) && email.length <= 254 && EMAIL.match?(email)
      @errors[:guestEmail] = "Enter a valid email address (up to 254 characters)."
    end
    unless @notes.is_a?(String) && @notes.length <= 2000
      @errors[:notes] = "Use at most 2000 characters."
    end
  end
end
