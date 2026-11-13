module Api
  module V1
    module Admin
      class HomeController < BaseController
        def show
          bookings = Booking.where("ends_at > ?", Time.current).order(:starts_at, :id)
          days = bookings.group_by { |booking| booking.starts_at.in_time_zone("Europe/Berlin").to_date.iso8601 }
          render json: { timeZone: "Europe/Berlin", days: days.map { |date, entries|
            { date: date, bookings: entries.map(&:confirmation) }
          } }
        end
      end
    end
  end
end
