module Api
  module V1
    module Admin
      class BookingsController < BaseController
        PAGE_SIZE = 20

        def destroy
          Booking.transaction(requires_new: true) do
            booking = Booking.lock.find(params[:id])
            occupancy = booking.occupancy
            booking.destroy!
            occupancy.destroy!
          end
          head :no_content
        rescue ActiveRecord::RecordNotFound
          render json: { message: "Booking not found. Refresh the list before trying again." }, status: :not_found
        rescue ActiveRecord::ActiveRecordError
          render json: { message: "Unable to delete booking. Please try again." }, status: :service_unavailable
        end

        def index
          period = params.fetch(:period, "upcoming")
          page = params.fetch(:page, "1")
          unless %w[upcoming past].include?(period) && page.is_a?(String) &&
            page.match?(/\A[1-9][0-9]{0,9}\z/) && page.to_i <= 2_147_483_647
            render json: { message: "Choose Upcoming or Past and a positive whole-number page." }, status: :bad_request
            return
          end
          now = Time.current
          bookings = period == "past" ? Booking.where(ends_at: ..now) : Booking.where("ends_at > ?", now)
          direction = period == "past" ? :desc : :asc
          total = bookings.count
          records = bookings.order(starts_at: direction, id: :asc).offset((page.to_i - 1) * PAGE_SIZE).limit(PAGE_SIZE)
          render json: { bookings: records.map(&:confirmation), page: page.to_i, pageSize: PAGE_SIZE, total: total }
        end
      end
    end
  end
end
