# frozen_string_literal: true

# ValidatorExecution - persists validator state between prepare and verify phases
#
# Fields:
# - execution_id: unique UUID, used as the session identifier
# - state:        JSONB, stores validator class name, data_version, and custom data
# - is_active:    marks whether this is an active validation session
# - user_id:      links to the user running the validator
#
# Example:
#   # Prepare phase
#   execution = ValidatorExecution.create!(
#     execution_id: SecureRandom.uuid,
#     state: { validator_class: 'BookFlightValidator', data: { data_version: '123' } },
#     user_id: current_user.id,
#     is_active: true
#   )
#
#   # Verify phase
#   execution = ValidatorExecution.find_by(execution_id: 'abc-123')
#   state_data = execution.state_data
class ValidatorExecution < ApplicationRecord
  # System model — stores validator state globally, not scoped per session
  data_version_excluded!

  validates :execution_id, presence: true, uniqueness: true
  validates :state, presence: true

  scope :active, -> { where(is_active: true) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }

  def state_data
    return {} if state.blank?
    state.is_a?(Hash) ? state : JSON.parse(state)
  rescue JSON::ParserError
    {}
  end

  def data_version
    state_data.dig('data', 'data_version')
  end

  def validator_class_name
    state_data['validator_class']
  end

  def activate!
    update!(is_active: true)
  end

  def deactivate!
    update!(is_active: false)
  end

  def self.active_for_user(user_id)
    active.for_user(user_id).order(created_at: :desc)
  end

  def self.cleanup_expired!
    where('created_at < ?', 1.hour.ago).delete_all
  end
end
