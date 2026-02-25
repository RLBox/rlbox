# frozen_string_literal: true

require 'rspec/expectations'
require 'rspec/matchers'

# BaseValidator 为验证任务提供 RSpec 风格的 DSL
# 
# 使用示例:
#   class MyValidator < BaseValidator
#     self.validator_id = 'my_task'
#     self.title = '任务标题'
#     
#     def prepare
#       # 准备数据和环境
#     end
#     
#     def verify
#       # 使用 expect 进行断言
#       expect(Booking.count).to eq(1)
#     end
#   end
class BaseValidator
  include RSpec::Matchers

  # Raised when a validator declares requires_ui for a value not exposed in the frontend.
  class UiCapabilityMissingError < StandardError; end

  attr_reader :execution_id, :errors, :score, :assertions
  
  class << self
    attr_accessor :validator_id, :task_id, :title, :description, :timeout_seconds

    # Declare required UI capabilities. Called at class level in subclasses:
    #   requires_ui :posts, status: [:draft, :published]
    #
    # Raises UiCapabilityMissingError in execute_prepare if the frontend form
    # does not declare the corresponding ui_supports: annotation.
    def requires_ui(resource, **field_values)
      @ui_requirements ||= []
      field_values.each do |field, values|
        Array(values).each do |value|
          @ui_requirements << { resource: resource.to_s, field: field.to_s, value: value.to_s }
        end
      end
    end

    def ui_requirements
      @ui_requirements || []
    end

    # 返回验证器元信息
    def metadata
      {
        id: task_id || validator_id,  # 优先使用 task_id（UUID），向后兼容 validator_id
        validator_id: validator_id,    # 保留旧字段用于兼容
        task_id: task_id,              # 新字段（UUID）
        title: title,
        description: description,
        timeout: timeout_seconds,
        is_multi_turn: false           # 默认不支持多轮对话
      }
    end
  end
  
  # 数据包版本（当前使用 v1）
  DATA_PACK_VERSION = 'v1'
  
  def initialize(execution_id = SecureRandom.uuid)
    @execution_id = execution_id
    @errors = []
    @score = 0
    @assertions = []
    @prepare_result = nil
  end
  
  # 子类必须实现的方法
  def prepare
    raise NotImplementedError, "Subclass must implement #prepare"
  end
  
  def verify
    raise NotImplementedError, "Subclass must implement #verify"
  end
  
  # 子类必须实现：模拟 AI Agent 操作
  def simulate
    raise NotImplementedError, "Subclass must implement #simulate"
  end
  
  # 执行准备阶段（设置 data_version）
  def execute_prepare
    # Pre-flight: verify frontend declares all UI capabilities this validator needs
    check_ui_requirements!

    # 生成唯一的 data_version（使用十六进制随机字符串）
    # 使用 SecureRandom.hex(8) 生成 16 字符的十六进制字符串
    # 示例: "a3f9c8b2e1d4567f"
    # 优势: 字符串类型与 PostgreSQL session 变量匹配，无需类型转换
    @data_version = SecureRandom.hex(8)
    
    # 设置 PostgreSQL 会话变量 app.data_version
    # 使用 SET SESSION 确保连接级别作用域（不仅限于事务内）
    # RLS 策略会自动过滤查询，只返回 data_version=0（基线）+ 当前版本的数据
    # DataVersionable 的 before_create 钩子会自动读取并设置新记录的 data_version
    ActiveRecord::Base.connection.execute("SET SESSION app.data_version = '#{@data_version}'")
    
    # 执行自定义准备逻辑（通常不需要加载数据，直接使用基线数据即可）
    @prepare_result = prepare
    
    # 构造统一的返回格式
    # 1. 添加日期上下文到 title
    # 2. 将 prepare 返回的数据作为额外参数
    # 3. 添加 description（来自类变量）
    result = {
      title: add_date_context(self.class.title),
      description: self.class.description
    }
    
    # 如果 prepare 返回了 Hash，合并所有字段（排除 task 和 hint）
    if @prepare_result.is_a?(Hash)
      @prepare_result.each do |key, value|
        # 跳过 task 和 hint 字段（已经统一到 title 和 description）
        next if [:task, :hint].include?(key)
        result[key] = value
      end
    end
    
    # 保存执行状态（用于验证阶段恢复）
    save_execution_state
    
    result
  end
  
  # 执行验证阶段（验证用户操作结果）
  def execute_verify
    result = {
      execution_id: @execution_id,
      status: 'unknown',
      score: 0,
      assertions: [],
      errors: []
    }
    
    begin
      # 恢复执行状态（从准备阶段保存的状态，包括 @data_version）
      restore_execution_state
      
      # 恢复 PostgreSQL 会话变量 app.data_version
      # 使用 SET SESSION 确保连接级别作用域
      # 这样查询时可以看到基线数据 + AI 创建的数据
      ActiveRecord::Base.connection.execute("SET SESSION app.data_version = '#{@data_version}'")
      
      # 执行验证（直接验证现有数据，不重新加载任何数据）
      verify
      
      # 计算结果
      result[:status] = @errors.empty? ? 'passed' : 'failed'
      result[:score] = @score
      result[:assertions] = @assertions
      result[:errors] = @errors
      
    rescue StandardError => e
      result[:status] = 'error'
      result[:errors] << "验证执行出错: #{e.message}"
      result[:errors] << e.backtrace.first(5).join("\n")
    end
    
    # 清理执行状态
    # ⚠️ 注释掉以便调试和重复验证
    # cleanup_execution_state
    
    # 验证完成后，回滚到基线状态（删除当前 data_version 的所有数据）
    rollback_to_baseline
    
    result
  end
  
  # 执行完整的自动化测试流程（prepare -> simulate -> verify）
  def execute_simulate
    result = {
      task_id: self.class.task_id,
      validator_id: self.class.validator_id,  # 保留向后兼容
      title: self.class.title,
      status: 'unknown',
      prepare_info: nil,
      simulate_info: nil,
      verify_result: nil,
      timestamp: Time.current.iso8601
    }
    
    begin
      # 0. 确保基线数据已加载
      ensure_baseline_data_loaded
      
      # 1. 准备阶段
      result[:prepare_info] = execute_prepare
      
      # 2. 模拟操作阶段
      result[:simulate_info] = simulate
      
      # 3. 验证阶段
      result[:verify_result] = execute_verify
      
      # 判断最终状态
      result[:status] = result[:verify_result][:status]
      
    rescue StandardError => e
      result[:status] = 'error'
      result[:error] = e.message
      result[:backtrace] = e.backtrace.first(10)
      
      # 确保即使出错也回滚数据
      rollback_to_baseline if @data_version
    end
    
    result
  end
  
  private
  
  # 添加日期上下文到任务标题前面
  # 示例: "今天是2024年3月15日。请为一家三口预订..."
  def add_date_context(title)
    current_date = Date.current
    date_str = current_date.strftime('%Y年%m月%d日')
    "今天是#{date_str}。#{title}"
  end
  
  # Ensure baseline data (data_version='0') is loaded.
  # Called before simulate so automated tests are self-contained.
  # The web initializer (config/initializers/validator_baseline.rb) handles
  # normal app startup; this is a fallback for rake/test contexts.
  def ensure_baseline_data_loaded
    # Check whether any versionable model already has baseline records
    versionable = DataVersionable.models - DataVersionable.excluded_models
    has_baseline = versionable.any? do |model|
      model.column_names.include?('data_version') &&
        model.unscoped.where(data_version: '0').exists?
    end
    return if has_baseline

    data_packs_dir = Rails.root.join('app/validators/support/data_packs')
    pack_files = Dir.glob(data_packs_dir.join('**/*.rb')).sort
    return if pack_files.empty?

    Rails.logger.info '[BaseValidator] Loading baseline data packs...'
    ActiveRecord::Base.connection.execute("SET SESSION app.data_version = '0'")

    base_file = pack_files.find { |f| File.basename(f) == 'base.rb' }
    if base_file
      pack_files.delete(base_file)
      pack_files.unshift(base_file)
    end

    pack_files.each do |file|
      filename = Pathname.new(file).relative_path_from(Rails.root).to_s
      begin
        load file
        Rails.logger.info "[BaseValidator]   ✓ #{filename}"
      rescue StandardError => e
        Rails.logger.error "[BaseValidator]   ✗ #{filename}: #{e.message}"
        raise e
      end
    end
  end
  
  # Verify that every requires_ui declaration is satisfied by current ERB annotations.
  def check_ui_requirements!
    failures = self.class.ui_requirements.reject do |req|
      UiCapabilities.supports?(req[:resource], req[:field], req[:value])
    end
    return if failures.empty?

    lines = failures.map { |r| "  #{r[:resource]}.#{r[:field]}=#{r[:value]}" }
    # Build a suggested annotation string grouped by resource
    by_resource = failures.group_by { |r| r[:resource] }
    suggestions = by_resource.map do |resource, reqs|
      by_field = reqs.group_by { |r| r[:field] }
      fields_str = by_field.map { |field, rs| "#{field}=[#{rs.map { |r| r[:value] }.join(',')}]" }.join(' ')
      "  app/views/#{resource}/_form.html.erb:\n    <%# ui_supports: #{fields_str} %>"
    end.join("\n")

    raise UiCapabilityMissingError, <<~MSG.strip
      #{self.class.name} requires UI capabilities not declared in any _form.html.erb:

      #{lines.join("\n")}

      Add ui_supports: annotations to the relevant form views:
      #{suggestions}
    MSG
  end

  # 回滚到基线状态（删除当前 data_version 的所有数据）
  def rollback_to_baseline
    return unless @data_version
    
    # 使用 DataVersionable.models 获取所有注册的模型
    # 按依赖关系反向删除（先删除子记录如 Membership，再删除父记录如 User）
    # reverse 可以处理大部分情况（假设模型按依赖顺序注册）
    DataVersionable.models.reverse.each do |model|
      begin
        deleted_count = model.where(data_version: @data_version).delete_all
        # 静默删除，不输出日志（减少噪音）
      rescue StandardError => e
        # 捕获外键约束错误，但不中断回滚流程
        puts "  ⚠️  回滚 #{model.name} 失败: #{e.message}"
      end
    end
  end
  
  # 保存执行状态到数据库
  def save_execution_state
    # 获取子类定义的状态数据
    custom_data = execution_state_data || {}
    
    # 确保 data_version 总是被保存（即使子类覆盖了 execution_state_data）
    custom_data[:data_version] = @data_version
    
    state = {
      validator_class: self.class.name,
      timestamp: Time.current.to_s,
      data: custom_data
    }
    
    # 使用数据库存储，使用 JSON 类型
    ActiveRecord::Base.connection.execute(
      "INSERT INTO validator_executions (execution_id, state, created_at, updated_at) " \
      "VALUES (#{ActiveRecord::Base.connection.quote(@execution_id)}, " \
      "#{ActiveRecord::Base.connection.quote(state.to_json)}, " \
      "NOW(), NOW()) " \
      "ON CONFLICT (execution_id) DO UPDATE SET " \
      "state = EXCLUDED.state, updated_at = NOW()"
    )
  end
  
  # 从数据库恢复执行状态
  def restore_execution_state
    result = ActiveRecord::Base.connection.execute(
      "SELECT state FROM validator_executions WHERE execution_id = #{ActiveRecord::Base.connection.quote(@execution_id)}"
    ).first
    
    raise "执行状态不存在: #{@execution_id}" unless result
    
    state = JSON.parse(result['state'])
    data = state['data'] || {}
    
    # 恢复 data_version（必须）
    @data_version = data['data_version']
    
    # 调用子类的恢复方法
    restore_from_state(data)
  end
  
  # 清理执行状态
  def cleanup_execution_state
    ActiveRecord::Base.connection.execute(
      "DELETE FROM validator_executions WHERE execution_id = #{ActiveRecord::Base.connection.quote(@execution_id)}"
    )
  end
  

  
  # 子类可覆盖：返回需要保存的状态数据
  def execution_state_data
    {
      data_version: @data_version
    }
  end
  
  # 子类可覆盖：从状态恢复实例变量
  def restore_from_state(data)
    @data_version = data['data_version']
  end
  
  # 添加断言（RSpec 风格）
  def add_assertion(name, weight:)
    assertion = { name: name, weight: weight, passed: false }

    begin
      yield
      assertion[:passed] = true
      @score += weight
    rescue RSpec::Expectations::ExpectationNotMetError => e
      assertion[:error] = e.message
      @errors << "#{name}: #{e.message}"
    rescue StandardError => e
      assertion[:error] = "执行错误: #{e.message}"
      @errors << "#{name}: #{e.message}"
    end

    @assertions << assertion
  end

  # 提供 RSpec 的 expect 方法
  def expect(actual)
    RSpec::Expectations::ExpectationTarget.new(actual)
  end
end
