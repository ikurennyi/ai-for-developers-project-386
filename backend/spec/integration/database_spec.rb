require "rails_helper"

RSpec.describe "PostgreSQL connection" do
  it "executes a query against the configured test database" do
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      expect(connection.select_value("SELECT 1")).to eq(1)
    end
  end
end
