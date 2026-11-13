module Api
  module V1
    module Admin
      # All administrative data/mutation controllers must inherit this boundary.
      class BaseController < ApplicationController
        include ActionController::Cookies

        before_action :prevent_caching
        before_action :require_same_origin, unless: -> { request.get? || request.head? }
        before_action :require_administrator

        private

        def prevent_caching
          response.headers["Cache-Control"] = "no-store"
        end

        def require_same_origin
          origin = request.headers["Origin"]
          return if request.headers["X-Calendar-Request"] == "1" &&
            (origin.blank? || origin == request.base_url) &&
            request.headers["Sec-Fetch-Site"] != "cross-site"
          render json: { message: "Same-origin request required" }, status: :forbidden
        end

        def current_admin_session
          return @current_admin_session if defined?(@current_admin_session)
          token = cookies[:calendar_admin]
          @current_admin_session = token.present? ? AdminSession.find_by(token_digest: AdminSession.token_digest(token), expires_at: Time.current..) : nil
          @current_admin_session = nil if @current_admin_session && @current_admin_session.expires_at <= Time.current
          @current_admin_session
        end

        def require_administrator
          render json: { message: "Authentication required" }, status: :unauthorized unless current_admin_session
        end
      end
    end
  end
end
