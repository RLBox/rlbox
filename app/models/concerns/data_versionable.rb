# frozen_string_literal: true

# DataVersionable Concern
#
# 用于验证器框架的数据版本隔离机制。
#
# 主要功能：
# 1. 自动注册模型到全局列表（DataVersionable.models）
# 2. 在 before_create 时自动读取 PostgreSQL 会话变量 app.data_version
# 3. 配合 RLS 策略实现基于版本的数据隔离
#
# 使用方式：
#   class Flight < ApplicationRecord
#     include DataVersionable
#   end
#
# 工作流程：
# 1. 系统启动：SET SESSION app.data_version = '0'，加载基线数据
# 2. 验证器 prepare：SET LOCAL app.data_version = '123456'
# 3. AI 创建数据：before_create 自动设置 data_version = 123456
# 4. 验证器 verify：RLS 策略自动过滤，只看到 data_version=0 + 123456 的数据
# 5. 回滚：DELETE WHERE data_version = 123456
#
module DataVersionable
  extend ActiveSupport::Concern
  
  included do
    # 在创建记录时自动设置 data_version
    before_create :set_data_version
    
    # 自动过滤 data_version：查询时只返回基线数据('0') + 当前会话的 data_version
    default_scope { where(data_version: DataVersionable.current_versions) }
    
    # 自动注册模型到全局列表（调用模块级别的方法）
    DataVersionable.register_model(self)
  end
  
  # Class methods to be added to including classes
  class_methods do
    # 当子类继承时自动注册
    def inherited(subclass)
      super
      DataVersionable.register_model(subclass)
    end

    # 声明该模型不需要 data_version 隔离（系统级/全局模型）
    def data_version_excluded!
      DataVersionable.register_excluded(self)
    end
  end
  
  # 模块级别的方法（用于管理全局模型列表）
  def self.models
    @versionable_models ||= []
  end
  
  def self.register_model(model_class)
    # 排除抽象类（如 ApplicationRecord）
    # 抽象类没有数据库表，不需要数据版本管理
    return if model_class.abstract_class?
    
    models << model_class unless models.include?(model_class)
  end
  
  # 模块级别排除列表（通过 data_version_excluded! 声明的模型）
  def self.excluded_models
    @excluded_models ||= []
  end

  def self.register_excluded(model_class)
    excluded_models << model_class unless excluded_models.include?(model_class)
  end

  # 重置模型列表（仅用于测试）
  def self.reset_models!
    @versionable_models = []
    @excluded_models = []
  end
  
  # 获取当前会话应该查询的 data_version 列表
  # 返回: ['0'] 或 ['0', 'current_session_version']
  def self.current_versions
    # 从 PostgreSQL 读取当前会话的 app.data_version 变量
    version_str = ActiveRecord::Base.connection.execute(
      "SELECT current_setting('app.data_version', true) AS version"
    ).first&.dig('version')
    
    # 如果没有设置或为 '0'，只返回基线数据
    # 如果设置了其他值，返回基线 + 当前版本
    if version_str.blank? || version_str == '0'
      ['0']
    else
      ['0', version_str]
    end
  rescue => e
    # 如果查询失败（如连接池未初始化），默认返回基线版本
    Rails.logger.warn "[DataVersionable] Failed to get current_setting: #{e.message}"
    ['0']
  end
  
  private
  
  # 设置 data_version（before_create 钩子）
  def set_data_version
    # 从 PostgreSQL 读取当前会话的 app.data_version 变量
    version_str = ActiveRecord::Base.connection.execute(
      "SELECT current_setting('app.data_version', true) AS version"
    ).first&.dig('version')

    # 如果没有设置，默认为 '0'（基线数据）
    # 注意：保持字符串类型，与 PostgreSQL session 变量类型一致
    self.data_version = (version_str.present? ? version_str : '0')

    # DEBUG: 仅在开发环境打印（生产环境太吵）
    if Rails.env.development?
      Rails.logger.debug "[DataVersionable] #{self.class.name}#set_data_version: PostgreSQL returned '#{version_str}' → setting data_version=#{self.data_version}"
    end
  end
end
