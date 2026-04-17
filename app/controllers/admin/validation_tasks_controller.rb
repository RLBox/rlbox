# frozen_string_literal: true

class Admin::ValidationTasksController < Admin::BaseController
  # GET /admin/validation_tasks
  def index
    all_tasks = load_all_validators
    
    # 获取所有目录用于筛选
    @directories = all_tasks.map { |t| extract_directory(t[:validator_id]) }.uniq.sort
    
    # 搜索功能
    @search_query = params[:q].to_s.strip
    filtered_tasks = if @search_query.present?
      # 模糊搜索：支持 validator_id、title、description
      all_tasks.select do |t|
        t[:validator_id].to_s.downcase.include?(@search_query.downcase) ||
        t[:title].to_s.downcase.include?(@search_query.downcase) ||
        t[:description].to_s.downcase.include?(@search_query.downcase)
      end
    elsif params[:directory].present?
      # 按目录筛选
      @selected_directory = params[:directory]
      all_tasks.select { |t| extract_directory(t[:validator_id]) == @selected_directory }
    else
      all_tasks
    end
    
    # 分页（使用 Kaminari.paginate_array）
    @tasks = Kaminari.paginate_array(filtered_tasks).page(params[:page]).per(50)
  end

  # GET /admin/validation_tasks/:id
  def show
    @tasks = load_all_validators
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
  def load_all_validators
    # 自动加载 app/validators/**/*_validator.rb（支持子文件夹和命名空间）
    validator_files = Dir[Rails.root.join('app/validators/**/*_validator.rb')]
    
    validator_files.map do |file|
      # 跳过 base_validator.rb
      next if file.end_with?('base_validator.rb')
      
      # 从文件路径推导出完整的类名（包含命名空间）
      # 例如: app/validators/v001_v050/v001_book_budget_hotel_validator.rb
      # => V001V050::V001BookBudgetHotelValidator
      relative_path = file.gsub(Rails.root.join('app/validators/').to_s, '')
      class_path = relative_path.gsub('.rb', '').split('/')
      class_name = class_path.map(&:camelize).join('::')
      
      begin
        klass = class_name.constantize
        next unless klass < BaseValidator
        
        # 返回验证器的 metadata
        klass.metadata
      rescue StandardError => e
        Rails.logger.error "Failed to load validator #{class_name}: #{e.message}"
        nil
      end
    end.compact
  end

  # 根据ID查找验证器（支持 validator_id 或 task_id）
  def find_validator_by_id(id)
    load_all_validators.find { |task| task[:validator_id] == id || task[:task_id] == id }
  end

  # 从 validator_id 中提取目录名
  def extract_directory(validator_id)
    # 转换为字符串（防止整数类型）
    validator_id_str = validator_id.to_s
    
    # 匹配格式如 v001_v050::v001_xxx
    if validator_id_str =~ /^([a-z0-9_]+)::/i
      Regexp.last_match(1)
    else
      '其他'
    end
  end
  
  # 检查验证器是否为多轮对话类型
  def check_multi_turn_validator(validator_id)
    validator_files = Dir[Rails.root.join('app/validators/**/*_validator.rb')]
    
    validator_files.each do |file|
      next if file.end_with?('base_validator.rb') || file.end_with?('multi_turn_base_validator.rb')
      
      relative_path = file.gsub(Rails.root.join('app/validators/').to_s, '')
      class_path = relative_path.gsub('.rb', '').split('/')
      class_name = class_path.map(&:camelize).join('::')
      
      begin
        klass = class_name.constantize
        next unless klass < BaseValidator
        
        # 匹配 validator_id
        if klass.validator_id == validator_id
          # 检查是否继承自 MultiTurnBaseValidator
          return klass < MultiTurnBaseValidator
        end
      rescue StandardError => e
        next
      end
    end
    
    false
  end
  
  # 提取验证器的断言信息（通过解析 verify 方法源码）
  def extract_validator_assertions(validator_id)
    validator_files = Dir[Rails.root.join('app/validators/**/*_validator.rb')]
    
    validator_files.each do |file|
      next if file.end_with?('base_validator.rb') || file.end_with?('multi_turn_base_validator.rb')
      
      relative_path = file.gsub(Rails.root.join('app/validators/').to_s, '')
      class_path = relative_path.gsub('.rb', '').split('/')
      class_name = class_path.map(&:camelize).join('::')
      
      begin
        klass = class_name.constantize
        next unless klass < BaseValidator
        
        # 匹配 validator_id
        if klass.validator_id == validator_id
          # 读取文件内容并解析断言
          return parse_assertions_from_file(file)
        end
      rescue StandardError => e
        Rails.logger.error "Failed to extract assertions for #{validator_id}: #{e.message}"
        next
      end
    end
    
    []
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
