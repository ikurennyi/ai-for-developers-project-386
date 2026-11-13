class BookingAttempt < ApplicationRecord
  belongs_to :booking, optional: true
end
