# frozen_string_literal: true

# LlmMessageValidationConcern
#
# Include in any model that stores LLM conversation messages (role + content).
# Handles role validation and provides convenience helpers.
#
# Expected columns:
#   role    :string, null: false   — "assistant", "system", or "user"
#   content :text                  — may be blank during streaming
#
# Usage:
#   class Message < ApplicationRecord
#     include LlmMessageValidationConcern
#   end
module LlmMessageValidationConcern
  extend ActiveSupport::Concern

  VALID_ROLES = %w[assistant system user].freeze

  included do
    validates :role, presence: true, inclusion: {
      in: VALID_ROLES,
      message: "%{value} is not a valid role. Must be one of: #{VALID_ROLES.join(', ')}"
    }

    # Content may be blank — in streaming mode content starts empty and fills in gradually
    validates :content, allow_blank: true, length: { maximum: 100_000 }

    scope :by_role, ->(role) { where(role: role) }
  end

  def assistant?
    role == 'assistant'
  end

  def user?
    role == 'user'
  end

  def system?
    role == 'system'
  end
end
