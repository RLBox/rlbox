# frozen_string_literal: true

# Multi-Turn Base Validator
# Extends BaseValidator to support AI-powered multi-turn dialogue testing
#
# Usage:
#   class V201BookingMultiTurnValidator < MultiTurnBaseValidator
#     self.validator_id = 'v201'
#     self.title = '预订多轮对话'
#     self.max_turns = 10
#
#     def initial_task_goal
#       "帮我创建一篇已发布的帖子"
#     end
#
#     def user_context
#       { status: 'published' }
#     end
#
#     def verify
#       add_assertion "创建了帖子", weight: 100 do
#         expect(Post.where(data_version: @data_version)).not_to be_empty
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
