module Api
  module V1
    module Admin
      class SessionsController < BaseController
        skip_before_action :require_administrator, only: [ :create, :destroy ]

        def show
          render_session(current_admin_session)
        end

        def create
          if (retry_after = AdminLoginLimit.consume(request.remote_ip))
            response.headers["Retry-After"] = retry_after.to_s
            return render json: { message: "Too many login attempts. Please try again later." }, status: :too_many_requests
          end
          admin = Administrator.configured
          unless admin
            # Match the cost of a provisioned account, without public defaults.
            Administrator.digest(params[:password].to_s)
            return invalid_credentials
          end
          admin.with_lock do
            return invalid_credentials unless admin.authenticates?(params[:username].to_s, params[:password].to_s)
            current_admin_session&.destroy!
            token = SecureRandom.hex(32)
            session = AdminSession.create!(token_digest: AdminSession.token_digest(token), expires_at: 24.hours.from_now)
            cookies[:calendar_admin] = { value: token, expires: session.expires_at, httponly: true,
              same_site: :strict, secure: Rails.env.production?, path: "/api/v1/admin" }
            render_session(session)
          end
        end

        def destroy
          current_admin_session&.destroy!
          cookies.delete(:calendar_admin, path: "/api/v1/admin", same_site: :strict, secure: Rails.env.production?)
          head :no_content
        end

        private

        def invalid_credentials
          render json: { message: "Invalid username or password" }, status: :unauthorized
        end

        def render_session(session)
          render json: { username: Administrator.find(1).username, expiresAt: session.expires_at.iso8601 }
        end
      end
    end
  end
end
