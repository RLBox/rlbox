# frozen_string_literal: true

# ValidatorExecution - 验证器执行状态存储
# 
# 用于在 prepare 和 verify 阶段之间传递验证器状态
# 
# 字段：
# - execution_id: 唯一执行 ID (UUID)
# - state: JSONB 存储验证器完整状态
# - is_active: 标记当前是否为活跃验证会话
# - user_id: 关联的用户 ID（用于多用户并发场景）
# 
# 使用示例：
#   # Prepare 阶段
#   execution = ValidatorExecution.create!(
#     execution_id: 'abc-123',
#     state: { validator_class: 'BookFlightValidator', data: {...} },
#     user_id: current_user.id,
#     is_active: true
#   )
#   
#   # Verify 阶段
#   execution = ValidatorExecution.find_by(execution_id: 'abc-123')
#   state_data = execution.state_data
class ValidatorExecution < ApplicationRecord
  # ValidatorExecution 是系统模型，不使用 data_version 机制
  default_scope { unscope(where: :data_version) }
  skip_callback :create, :before, :set_data_version

  # 验证
  validates :execution_id, presence: true, uniqueness: true
  validates :state, presence: true
  
  # 作用域
  scope :active, -> { where(is_active: true) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }
  
  # 便捷方法：获取状态数据的 Hash 对象
  def state_data
    return {} if state.blank?
    
    # state 字段是 jsonb 类型，Rails 自动转换为 Hash
    state.is_a?(Hash) ? state : JSON.parse(state)
  rescue JSON::ParserError
    {}
  end
  
  # 便捷方法：获取 data_version
  def data_version
    state_data.dig('data', 'data_version')
  end
  
  # 便捷方法：获取验证器类名
  def validator_class_name
    state_data['validator_class']
  end
  
  # 设置为活跃状态（允许同一用户拥有多个活跃会话）
  def activate!
    # 直接激活当前会话，不取消其他会话
    update!(is_active: true)
  end
  
  # 取消活跃状态
  def deactivate!
    update!(is_active: false)
  end
  
  # 类方法：获取用户的活跃验证会话列表（支持多个并发会话）
  def self.active_for_user(user_id)
    active.for_user(user_id).order(created_at: :desc)
  end
  
  # 类方法：清理过期的验证会话（超过 1 小时未使用）
  def self.cleanup_expired!
    where('created_at < ?', 1.hour.ago).delete_all
  end
end
