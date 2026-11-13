module Api
  module V1
    class AvailabilityController < ApplicationController
      def show
        meeting_type = MeetingType.find_by(slug: params[:slug], published: true)
        response.headers["Cache-Control"] = "no-store"
        if meeting_type
          render json: CalendarAvailability.new(meeting_type).as_json
        else
          render json: { message: "Meeting type unavailable" }, status: :not_found
        end
      end
    end
  end
end
