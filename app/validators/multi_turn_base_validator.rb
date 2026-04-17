# frozen_string_literal: true

# Multi-Turn Base Validator
# Extends BaseValidator to support AI-powered multi-turn dialogue testing
#
# Usage:
#   class HotelBookingMultiTurnValidator < MultiTurnBaseValidator
#     self.validator_id = 'v201'
#     self.task_id = 'uuid-here'
#     self.title = '酒店预订多轮对话'
#     self.max_turns = 10
#
#     def initial_task_goal
#       "帮我订一个上海的酒店，预算 500 元左右"
#     end
#
#     def user_context
#       { budget: 500, city: '上海', check_in_date: 3.days.from_now }
#     end
#
#     def verify
#       # Use standard assertions to check results
#       add_assertion "创建了酒店订单", weight: 50 do
#         orders = HotelOrder.where(data_version: @data_version)
#         expect(orders).not_to be_empty
#       end
#     end
#   end
class MultiTurnBaseValidator < BaseValidator
  class << self
    attr_accessor :max_turns

    # Override metadata to mark multi-turn validators
    def metadata
      super.merge(is_multi_turn: true)
    end
  end

  # Default max conversation turns
  self.max_turns = 10

  attr_reader :conversation_turns, :simul_user_service

  def initialize(execution_id = SecureRandom.uuid)
    super(execution_id)
    @conversation_turns = []
    @simul_user_service = nil
    @current_turn = 0
  end

  # Subclasses must implement: Define the initial task goal
  def initial_task_goal
    raise NotImplementedError, "Subclass must implement #initial_task_goal"
  end

  # Subclasses can override: Provide user context/background
  def user_context
    {}
  end

  # Subclasses can override: Evaluate agent behavior during conversation
  # This is called after each agent response for real-time validation
  def evaluate_agent_behavior(agent_response, turn_number)
    # Default: no evaluation
    # Subclasses can override to add real-time checks
    nil
  end
end
