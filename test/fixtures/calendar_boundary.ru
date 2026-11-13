# The Rails server's existing --config seam, never a deployed initializer or API.
require_relative "../../backend/config/environment"
abort "Calendar boundary fixture is test-only" unless Rails.env.test?
require "active_support/testing/time_helpers"
extend ActiveSupport::Testing::TimeHelpers
travel_to Time.iso8601("2026-12-28T08:00:00Z")
run Rails.application
