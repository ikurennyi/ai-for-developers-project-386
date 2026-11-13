class MeetingType < ApplicationRecord
  attr_readonly :id, :initial_key

  normalizes :name, :slug, with: ->(value) { value.strip }
  normalizes :description, with: ->(value) { value.blank? ? "" : value }

  validates :name, presence: true, length: { maximum: 100 }
  validates :description, length: { maximum: 2000 }
  validates :duration_minutes, numericality: { only_integer: true, in: 1..540 }
  validates :slug, presence: true, length: { maximum: 80 },
    format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }, uniqueness: true
end
