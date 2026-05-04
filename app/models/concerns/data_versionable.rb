# frozen_string_literal: true

# DataVersionable Concern
#
# 用于验证器框架的数据版本隔离机制（见 docs/architecture/data-version.md）。
#
# 主要功能：
# 1. 自动注册模型到全局列表（DataVersionable.models）
# 2. 在 before_create 自动从 PG session 变量读 app.data_version 写入新记录
# 3. **baseline 写保护**（before_update / before_destroy）——
#    不允许把 data_version='0' 的 baseline 记录 UPDATE 或 DELETE，除非显式
#    打开 `DataVersionable.allow_baseline_mutation` 作用域（仅供 data pack 加载流程使用）。
# 4. 与 DB 层的 RLS policy 一起做双保险（见 migration
#    20260428133747_split_rls_policies_by_operation.rb）
#
# 使用方式：
#   class Post < ApplicationRecord
#     include DataVersionable
#   end
#
# 完整工作流程：
#   1. bin/db_init / rake validator:reset_baseline 里开 `DataVersionable.allow_baseline_mutation` 块，
#      同步 SET SESSION app.baseline_loading = 'on'，加载 data pack（INSERT data_version='0'）
#   2. 系统正常请求：app.data_version='0'，agent 只能 SELECT baseline，不能 INSERT/UPDATE/DELETE baseline
#   3. validator prepare：SET LOCAL app.data_version = '<hex>'
#   4. Agent 创建数据：before_create 自动填 data_version = '<hex>'
#   5. validator verify：RLS policy 自动过滤，只看到 data_version=0 + <hex>
#   6. 回滚：TRUNCATE 或 DELETE WHERE data_version='<hex>'
#
module DataVersionable
  extend ActiveSupport::Concern

  # baseline 被尝试 UPDATE / DELETE 时抛出。
  # 在 controller 层出现多半是 bug：要么 validator / data pack 没走 allow_baseline_mutation，
  # 要么应用代码想改一条 baseline 记录（应该 where.not(data_version:'0') 排除掉）。
  class BaselineMutationError < StandardError; end

  included do
    before_create  :set_data_version
    before_update  :prevent_baseline_mutation!
    before_destroy :prevent_baseline_mutation!

    # 默认只返回 baseline + 当前 session 的数据
    default_scope { where(data_version: DataVersionable.current_versions) }

    DataVersionable.register_model(self)
  end

  class_methods do
    def inherited(subclass)
      super
      DataVersionable.register_model(subclass)
    end

    # 声明该模型不需要 data_version 隔离（系统级/全局模型，如 Session / Administrator）。
    # 调用这个方法会：
    #   1. 从 DataVersionable.models 注册表移除（schema lint 不会检查这张表）
    #   2. 跳过所有 data_version 相关的回调（set / prevent_baseline_mutation）
    # 调用者**仍需**手动配置：
    #   default_scope { unscope(where: :data_version) } 防止 default_scope 引用不存在的列
    def data_version_excluded!
      DataVersionable.register_excluded(self)
      DataVersionable.unregister_model(self)
      skip_callback :create,  :before, :set_data_version
      skip_callback :update,  :before, :prevent_baseline_mutation!
      skip_callback :destroy, :before, :prevent_baseline_mutation!
    end
  end

  # ---------- 模块级工具 ----------

  def self.models
    @versionable_models ||= []
  end

  def self.register_model(model_class)
    return if model_class.abstract_class?
    models << model_class unless models.include?(model_class)
  end

  def self.unregister_model(model_class)
    models.delete(model_class)
  end

  def self.excluded_models
    @excluded_models ||= []
  end

  def self.register_excluded(model_class)
    excluded_models << model_class unless excluded_models.include?(model_class)
  end

  def self.reset_models!
    @versionable_models = []
    @excluded_models = []
  end

  # 获取当前 PG session 的 data_version 列表
  # 返回: ['0'] 或 ['0', '<hex>']
  def self.current_versions
    version_str = ActiveRecord::Base.connection.execute(
      "SELECT current_setting('app.data_version', true) AS version"
    ).first&.dig('version')

    if version_str.blank? || version_str == '0'
      ['0']
    else
      ['0', version_str]
    end
  rescue StandardError => e
    Rails.logger.warn "[DataVersionable] Failed to get current_setting: #{e.message}"
    ['0']
  end

  # 作用域内放开 baseline 写保护。
  # 同时 SET SESSION app.baseline_loading='on'（绕过 DB 层 RLS）+ 设 Thread.current 开关（绕过 Ruby 层回调）。
  # 仅供 data pack 加载流程使用（validator.rake / base_validator.rb）。
  #
  # 用法：
  #   DataVersionable.allow_baseline_mutation do
  #     ActiveRecord::Base.connection.execute("SET SESSION app.data_version = '0'")
  #     load 'app/validators/support/data_packs/v1/base.rb'
  #   end
  def self.allow_baseline_mutation
    prev_thread = Thread.current[:allow_baseline_mutation]
    Thread.current[:allow_baseline_mutation] = true

    conn = ActiveRecord::Base.connection
    conn.execute("SET SESSION app.baseline_loading = 'on'")
    yield
  ensure
    Thread.current[:allow_baseline_mutation] = prev_thread
    begin
      # 无论 yield 是否抛异常，都把 SESSION 开关关回去，避免连接回到连接池后还是 on
      ActiveRecord::Base.connection.execute("SET SESSION app.baseline_loading = 'off'")
    rescue StandardError => e
      # 连接异常时忽略；ApplicationController 每次请求会再 reset 一次做双保险
      Rails.logger.warn "[DataVersionable] Failed to reset baseline_loading: #{e.message}"
    end
  end

  # 仅供测试 / 诊断：查询当前作用域是否允许写 baseline
  def self.baseline_mutation_allowed?
    Thread.current[:allow_baseline_mutation] == true
  end

  # ---------- 实例级回调 ----------
  private

  # before_create：从 PG session 读 app.data_version 写进新记录
  def set_data_version
    version_str = ActiveRecord::Base.connection.execute(
      "SELECT current_setting('app.data_version', true) AS version"
    ).first&.dig('version')

    # 没设置时默认 '0'（加载 baseline 的情况）
    self.data_version = (version_str.present? ? version_str : '0')

    if Rails.env.development?
      Rails.logger.debug "[DataVersionable] #{self.class.name}#set_data_version: PostgreSQL returned '#{version_str}' → setting data_version=#{self.data_version}"
    end
  end

  # before_update / before_destroy：拒改/拒删 baseline 行
  #
  # 决策细节：
  #   - 看 `data_version_was`（DB 里原本的值），不是新赋的值。这样"把 baseline 行的 data_version
  #     改成当前 session"这种"擦掉 baseline"的攻击面也能挡。
  #   - destroy 场景 data_version_was 始终等于当前值，正常检查即可。
  def prevent_baseline_mutation!
    return if DataVersionable.baseline_mutation_allowed?

    original = respond_to?(:data_version_was) ? data_version_was : data_version
    return unless original.to_s == '0'

    raise BaselineMutationError,
          "Refusing to #{destroyed? ? 'destroy' : 'update'} baseline record " \
          "#{self.class.name}##{id} (data_version='0'). " \
          "Baseline records are immutable outside of data-pack loading. " \
          "If the caller is a controller, exclude baseline with `.where.not(data_version: '0')`."
  end
end
