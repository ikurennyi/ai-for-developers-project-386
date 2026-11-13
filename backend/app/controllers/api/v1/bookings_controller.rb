module Api
  module V1
    class BookingsController < ApplicationController
      def create
        response.headers["Cache-Control"] = "no-store"
        if params.key?(:attemptToken) && !BookingRetry.valid?(params[:attemptToken])
          render json: { code: "validation", message: "Invalid booking attempt. Please reload and try again." },
            status: :unprocessable_content
          return
        end
        guest = GuestDetails.new(params[:guestName], params[:guestEmail], params[:notes])
        unless guest.errors.empty?
          render json: { code: "validation", message: "Please correct the highlighted fields.", errors: guest.errors },
            status: :unprocessable_content
          return
        end
        Booking.transaction do
          attempt_digest = BookingRetry.lock(params[:attemptToken])
          if attempt_digest && (original = Booking.find_by(attempt_digest: attempt_digest))
            render json: original.confirmation, status: :created
            return
          end
          # Shared row locks allow concurrent confirmations but serialize offer
          # edits/hiding against the reviewed-details check and saved snapshot.
          meeting_type = MeetingType.lock("FOR SHARE").find_by(slug: params[:slug], published: true)
          unless meeting_type
            render json: { message: "Meeting type unavailable" }, status: :not_found
            return
          end
          reviewed = params[:meetingType]
          unless reviewed.is_a?(ActionController::Parameters) &&
              reviewed[:name] == meeting_type.name && reviewed[:description] == meeting_type.description &&
              reviewed[:durationMinutes] == meeting_type.duration_minutes
            render json: { code: "details_changed",
              message: "Meeting details changed. Please return to the calendar and review them before confirming." },
              status: :conflict
            return
          end
          starts_at = selected_start
          now = Time.current
          snapshot = CalendarAvailability.new(meeting_type, now: now).as_json
          interval = snapshot[:days].flat_map { |day| day[:intervals] }
            .find { |entry| Time.iso8601(entry[:startsAt]) == starts_at }
          unless interval && starts_at > now
            render json: { code: "invalid_interval",
              message: "This selection is no longer valid. Please choose another time." }, status: :conflict
            return
          end
          unless interval[:available]
            occupied
            return
          end
          ends_at = starts_at + meeting_type.duration_minutes.minutes
          occupancy = Occupancy.create!(starts_at: starts_at, ends_at: ends_at)
          booking = Booking.create!(meeting_type: meeting_type, occupancy: occupancy,
            starts_at: starts_at, ends_at: ends_at, meeting_name: meeting_type.name,
            meeting_description: meeting_type.description, duration_minutes: meeting_type.duration_minutes,
            guest_name: guest.name, guest_email: guest.email, notes: guest.notes, attempt_digest: attempt_digest)
          # An exclusion/FK lock can wait after the initial schedule check.
          # Recheck at the end of the transaction, rolling back both records.
          if starts_at <= Time.current
            render json: { code: "invalid_interval",
              message: "This selection is no longer valid. Please choose another time." }, status: :conflict
            raise ActiveRecord::Rollback
          end
          render json: booking.confirmation, status: :created
        end
      rescue ActiveRecord::Deadlocked
        # Simultaneous GiST exclusion checks can deadlock. PostgreSQL has
        # already rolled this transaction back, so rechecking is safe and
        # observes the winner's committed occupancy. Never retry a lost response.
        @deadlock_retries = (@deadlock_retries || 0) + 1
        retry if @deadlock_retries <= 2
        raise
      rescue ActiveRecord::StatementInvalid => error
        raise unless error.cause.is_a?(PG::ExclusionViolation)
        occupied
      end

      private

      def selected_start
        value = params[:startsAt]
        return unless value.is_a?(String) && value.match?(/T.*(?:Z|[+-]\d{2}:\d{2})\z/)
        Time.iso8601(value)
      rescue ArgumentError
        nil
      end

      def occupied
        render json: { code: "occupied",
          message: "This time is no longer available. Please choose another time." }, status: :conflict
      end
    end
  end
end
