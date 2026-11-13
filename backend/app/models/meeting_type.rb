class MeetingType < ApplicationRecord
  attr_readonly :id, :initial_key

  # Match JavaScript String.trim so the form and API agree on Unicode edges.
  EDGE_WHITESPACE = /\A[\s\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]+|[\s\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]+\z/
  normalizes :name, :slug, with: ->(value) { value.gsub(EDGE_WHITESPACE, "") }
  normalizes :description, with: ->(value) { value.blank? ? "" : value }

  validates :name, presence: true, length: { maximum: 100 }
  validates :description, length: { maximum: 2000 }
  validates :duration_minutes, numericality: { only_integer: true, in: 1..540 }
  validates :slug, presence: true, length: { maximum: 80 },
    format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }, uniqueness: true
end
