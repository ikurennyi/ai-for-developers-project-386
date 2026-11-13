module Api
  module V1
    module Admin
      class MeetingTypesController < BaseController
        before_action :find_type, only: [ :show, :update, :publication ]

        def show
          render json: representation(@type)
        end

        def update
          @type.with_lock { save_details(@type) }
        rescue ActiveRecord::RecordNotUnique
          address_collision(@type)
        end

        def publication
          unless [ true, false ].include?(params[:published])
            render json: { message: "Publication must be true or false.", errors: {} }, status: :unprocessable_content
            return
          end
          @type.with_lock do
            @type.update!(published: params[:published])
            render json: representation(@type)
          end
        end

        def index
          render json: { meetingTypes: MeetingType.order(:created_at, :id).map { |type| representation(type) } }
        end

        def create
          type = MeetingType.new
          save_details(type, status: :created)
        rescue ActiveRecord::RecordNotUnique
          address_collision(type)
        end

        private

        def find_type
          @type = MeetingType.find_by(id: params[:id])
          render json: { message: "Meeting type not found" }, status: :not_found unless @type
        end

        def save_details(type, status: :ok)
          errors = input_type_errors
          if errors.any?
            render json: { message: "Please correct the highlighted fields.", errors: errors }, status: :unprocessable_content
            return
          end
          type.assign_attributes(
            name: params[:name], description: params.fetch(:description, ""),
            duration_minutes: params[:durationMinutes], slug: params[:slug]
          )
          if type.save
            render json: representation(type), status: status
          else
            render_errors(type)
          end
        end

        def address_collision(type)
          # Rescue outside the transaction, after PostgreSQL has rolled it back.
          type.errors.add(:slug, "has already been taken")
          render_errors(type)
        end

        # Check JSON types before Active Record can coerce floats, booleans or
        # numeric strings into integers, or malformed values into text.
        def input_type_errors
          errors = {}
          %w[name slug].each do |field|
            errors[field] = [ "must be text" ] unless params[field].is_a?(String)
          end
          if params.key?(:description) && !params[:description].is_a?(String)
            errors["description"] = [ "must be text" ]
          end
          errors["durationMinutes"] = [ "must be a whole number from 1 to 540" ] unless params[:durationMinutes].is_a?(Integer)
          errors
        end

        def representation(type)
          { id: type.id, name: type.name, description: type.description,
            durationMinutes: type.duration_minutes, slug: type.slug, published: type.published }
        end

        def render_errors(type)
          errors = type.errors.messages.transform_keys { |key| key == :duration_minutes ? "durationMinutes" : key.to_s }
          render json: { message: "Please correct the highlighted fields.", errors: errors }, status: :unprocessable_content
        end
      end
    end
  end
end
