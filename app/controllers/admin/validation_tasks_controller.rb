# frozen_string_literal: true

class Admin::ValidationTasksController < Admin::BaseController
  # GET /admin/validation_tasks
  def index
    all_tasks = load_all_validators

    # Attach latest execution status to each task
    attach_execution_status!(all_tasks)

    # 获取所有目录用于筛选
    @directories = all_tasks.map { |t| t[:directory] }.compact.uniq.sort

    # 搜索功能
    @search_query = params[:q].to_s.strip
    filtered_tasks = if @search_query.present?
      # 模糊搜索：支持 validator_id、title（见 ADR-019：description 已废弃，只用 title）
      all_tasks.select do |t|
        t[:validator_id].to_s.downcase.include?(@search_query.downcase) ||
        t[:title].to_s.downcase.include?(@search_query.downcase)
      end
    elsif params[:directory].present?
      # 按目录筛选
      @selected_directory = params[:directory]
      all_tasks.select { |t| t[:directory] == @selected_directory }
    else
      all_tasks
    end

    # 状态筛选
    @selected_status = params[:status]
    if @selected_status.present?
      filtered_tasks = filtered_tasks.select { |t| t[:execution_status] == @selected_status }
    end

    # 排序
    @sort = params[:sort] || 'status'
    filtered_tasks = sort_tasks(filtered_tasks, @sort)

    # Stats for status filter cards
    @status_counts = {
      'passed'  => all_tasks.count { |t| t[:execution_status] == 'passed' },
      'failed'  => all_tasks.count { |t| t[:execution_status] == 'failed' },
      'running' => all_tasks.count { |t| t[:execution_status] == 'running' },
      'pending' => all_tasks.count { |t| t[:execution_status] == 'pending' }
    }

    # 分页（使用 Kaminari.paginate_array）
    @tasks = Kaminari.paginate_array(filtered_tasks).page(params[:page]).per(50)
  end

  # GET /admin/validation_tasks/:id
  def show
    @tasks = load_all_validators
    attach_execution_status!(@tasks)
    # 优先通过 validator_id 查找（URL 友好），也支持 task_id（UUID）
    @task = @tasks.find { |t| t[:validator_id] == params[:id] || t[:task_id] == params[:id] }

    if @task.nil?
      redirect_to admin_validation_tasks_path, alert: "任务不存在"
      return
    end

    # 检查是否为多轮对话验证器
    @is_multi_turn = check_multi_turn_validator(@task[:validator_id])

    # 提取验证器的断言信息
    @assertions = extract_validator_assertions(@task[:validator_id])

    # 查找上一个和下一个任务
    current_index = @tasks.index { |t| t[:validator_id] == @task[:validator_id] }
    @prev_task = @tasks[current_index - 1] if current_index && current_index > 0
    @next_task = @tasks[current_index + 1] if current_index && current_index < @tasks.length - 1
  end

  private

  # 加载所有验证器类
  #
  # Zeitwerk 配置（见 config/application.rb + ADR-006）：
  #   app/validators/ 被 push_dir 到 `Validators` 命名空间，
  #   所以 app/validators/order/v002_foo_validator.rb 定义的常量是
  #   `Validators::Order::V002FooValidator`（不是顶层 V002FooValidator，
  #   也不是 Order::V002FooValidator——后者会和顶层 Order 模型撞车）。
  def load_all_validators
    validator_files = Dir[Rails.root.join('app/validators/**/*_validator.rb')].sort

    validator_files.filter_map do |file|
      next if file.end_with?('base_validator.rb')
      next if file.include?('/support/') # data_packs 脚本，非 validator

      # 路径 → 完整常量名：
      #   app/validators/order/v002_reorder_previous_validator.rb
      #   → ["order", "v002_reorder_previous_validator"]
      #   → "Validators::Order::V002ReorderPreviousValidator"
      rel  = file.to_s.sub(%r{^.*?/app/validators/}, '')
      parts = rel.sub(/\.rb\z/, '').split('/')
      class_name = (['Validators'] + parts.map(&:camelize)).join('::')

      begin
        klass = class_name.constantize
        next unless klass < Validators::BaseValidator

        # 把文件路径一起塞进 metadata，后续 extract_directory / assertions 直接复用
        klass.metadata.merge(
          file_path: file,
          directory: extract_directory_from_path(file)
        )
      rescue StandardError => e
        Rails.logger.error "Failed to load validator #{class_name} (#{file}): #{e.class} #{e.message}"
        nil
      end
    end
  end

  # 从文件路径提取子目录名（catalog / cart / checkout / order / account …）
  # app/validators/order/v002_foo_validator.rb → "order"
  # app/validators/v001_foo_validator.rb       → "其他"（无子目录）
  def extract_directory_from_path(file)
    rel = file.to_s.sub(%r{^.*?/app/validators/}, '')
    parts = rel.split('/')
    parts.length > 1 ? parts.first : '其他'
  end

  # 旧接口保留兼容：优先用 metadata 里塞的 directory
  def extract_directory(task_or_id)
    return task_or_id[:directory] if task_or_id.is_a?(Hash) && task_or_id[:directory]
    '其他'
  end

  # 检查验证器是否为多轮对话类型
  def check_multi_turn_validator(validator_id)
    task = load_all_validators.find { |t| t[:validator_id] == validator_id }
    return false unless task && task[:file_path]

    relative_path = task[:file_path].to_s.sub(%r{^.*?/app/validators/}, '')
    class_path = relative_path.gsub('.rb', '').split('/')
    class_name = (['Validators'] + class_path.map(&:camelize)).join('::')

    begin
      klass = class_name.constantize
      return false unless klass < Validators::BaseValidator
      klass < Validators::MultiTurnBaseValidator
    rescue StandardError
      false
    end
  end

  # Attach latest execution status/score to each task hash.
  # Source of truth: db/validator_statuses.json — written by API after every verify run.
  # DB (ValidatorExecution) is only used for session lifecycle, not for display.
  def attach_execution_status!(tasks)
    json_statuses = load_json_statuses

    tasks.each do |task|
      entry = json_statuses[task[:validator_id]]
      if entry
        task[:execution_status] = entry['status'] || 'pending'
        task[:execution_score]  = entry['score']
        task[:execution_time]   = Time.parse(entry['updated_at']) rescue nil
      else
        task[:execution_status] = 'pending'
        task[:execution_score]  = nil
        task[:execution_time]   = nil
      end
    end
  end

  # Load validator statuses from db/validator_statuses.json (cached per request).
  # This file is the single source of truth — updated by API::TasksController#verify.
  def load_json_statuses
    @json_statuses ||= begin
      path = Rails.root.join('db/validator_statuses.json')
      path.exist? ? JSON.parse(File.read(path)) : {}
    rescue JSON::ParserError
      {}
    end
  end

  # Sort tasks by the chosen strategy
  def sort_tasks(tasks, sort_key)
    status_order = { 'passed' => 0, 'failed' => 1, 'running' => 2, 'pending' => 3 }

    case sort_key
    when 'status'
      # Completed (passed) first, then failed, running, pending
      tasks.sort_by { |t| [status_order[t[:execution_status]] || 99, -(t[:execution_score]&.to_f || 0)] }
    when 'status_asc'
      # Pending first (reverse)
      tasks.sort_by { |t| [-(status_order[t[:execution_status]] || 99), t[:execution_score]&.to_f || 0] }
    when 'score'
      tasks.sort_by { |t| -(t[:execution_score]&.to_f || -1) }
    when 'name'
      tasks.sort_by { |t| t[:validator_id].to_s }
    else
      tasks
    end
  end

  # 提取验证器的断言信息（通过解析 verify 方法源码）
  def extract_validator_assertions(validator_id)
    task = load_all_validators.find { |t| t[:validator_id] == validator_id }
    return [] unless task && task[:file_path]

    parse_assertions_from_file(task[:file_path])
  end

  # 解析验证器文件中的 add_assertion 调用
  def parse_assertions_from_file(file_path)
    assertions = []
    content = File.read(file_path)

    # 正则匹配 add_assertion "名称", weight: 数字 do
    # 支持单引号和双引号，支持多行
    content.scan(/add_assertion\s+(["'])(.+?)\1\s*,\s*weight:\s*(\d+)/m) do |quote, name, weight|
      assertions << {
        name: name.strip,
        weight: weight.to_i
      }
    end

    assertions
  end
end
