module Api
  module V1
    class MeetingTypesController < ApplicationController
      def index
        render json: {
          meetingTypes: MeetingType.where(published: true).order(:created_at, :id).map do |type|
            {
              id: type.id, name: type.name, description: type.description,
              durationMinutes: type.duration_minutes, slug: type.slug
            }
          end
        }
      end
    end
  end
end
