# frozen_string_literal: true

class Post < ApplicationRecord
  belongs_to :user

  STATUSES = %w[draft published].freeze

  validates :title,  presence: true
  validates :status, inclusion: { in: STATUSES }
end
