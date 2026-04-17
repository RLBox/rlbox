# frozen_string_literal: true

# 辅助工具：Validator 编号管理
# 用于扫描模块目录、自动分配编号、检测冲突等
#
# 使用示例：
#   helper = ValidatorNumberHelper.new
#   next_number = helper.find_next_number('hotel')  # => "001"
#   available = helper.get_available_number('hotel', '005')  # => "005" 或 "006"（如果 005 已存在）

class ValidatorNumberHelper
  # 默认的 validators 根目录
  VALIDATORS_ROOT = File.expand_path('~/fliggy/app/validators')
  
  # 初始化
  def initialize(root_path = VALIDATORS_ROOT)
    @root_path = root_path
  end
  
  # 扫描模块目录，获取下一个可用编号
  # @param module_name [String] 模块名，如 'hotel', 'flight', 'attraction'
  # @return [String] 三位数字编号，如 "001", "002", "003"
  def find_next_number(module_name)
    validators_dir = File.join(@root_path, module_name)
    
    # 如果目录不存在，返回 001
    return '001' unless Dir.exist?(validators_dir)
    
    # 查找所有符合命名规范的文件
    pattern = File.join(validators_dir, "v*_#{module_name}_validator.rb")
    files = Dir.glob(pattern)
    
    # 提取编号
    numbers = files.map do |file|
      basename = File.basename(file, '.rb')
      # 匹配 v{编号}_{module}_validator
      match = basename.match(/^v(\d{3})_#{Regexp.escape(module_name)}_validator$/)
      match ? match[1].to_i : nil
    end.compact
    
    # 返回最大编号 + 1（格式化为三位数字）
    next_number = numbers.empty? ? 1 : numbers.max + 1
    format('%03d', next_number)
  end
  
  # 检查指定编号是否已存在
  # @param module_name [String] 模块名
  # @param number [String] 三位数字编号，如 "001"
  # @return [Boolean] true 如果文件已存在
  def number_exists?(module_name, number)
    validators_dir = File.join(@root_path, module_name)
    file_path = File.join(validators_dir, "v#{number}_#{module_name}_validator.rb")
    File.exist?(file_path)
  end
  
  # 获取可用编号（如果指定的编号已存在，自动递增）
  # @param module_name [String] 模块名
  # @param requested_number [String, nil] 用户请求的编号（可选）
  # @return [Hash] { number: "001", conflict: false, message: "..." }
  def get_available_number(module_name, requested_number = nil)
    if requested_number
      # 用户手动指定了编号
      number = requested_number
      original_number = number
      conflict = false
      
      while number_exists?(module_name, number)
        conflict = true
        number = format('%03d', number.to_i + 1)
      end
      
      if conflict
        {
          number: number,
          conflict: true,
          message: "⚠️  编号 #{original_number} 已存在，已自动递增到 #{number}"
        }
      else
        {
          number: number,
          conflict: false,
          message: "✓ 使用指定编号 #{number}"
        }
      end
    else
      # 自动获取下一个可用编号
      number = find_next_number(module_name)
      {
        number: number,
        conflict: false,
        message: "✓ 自动分配编号 #{number}"
      }
    end
  end
  
  # 列出模块中所有已存在的 validator
  # @param module_name [String] 模块名
  # @return [Array<Hash>] 每个元素包含 { number: "001", file: "...", class_name: "..." }
  def list_validators(module_name)
    validators_dir = File.join(@root_path, module_name)
    
    return [] unless Dir.exist?(validators_dir)
    
    pattern = File.join(validators_dir, "v*_#{module_name}_validator.rb")
    files = Dir.glob(pattern).sort
    
    files.map do |file|
      basename = File.basename(file, '.rb')
      match = basename.match(/^v(\d{3})_#{Regexp.escape(module_name)}_validator$/)
      
      next unless match
      
      number = match[1]
      class_name = generate_class_name(module_name, number)
      
      {
        number: number,
        file: file,
        class_name: class_name,
        validator_id: "v#{number}_#{module_name}_validator"
      }
    end.compact
  end
  
  # 生成类名
  # @param module_name [String] 模块名，如 'hotel', 'flight'
  # @param number [String] 编号，如 "001"
  # @return [String] 类名，如 "V001HotelValidator"
  def generate_class_name(module_name, number)
    # 将模块名转为首字母大写（hotel → Hotel）
    module_pascal = module_name.split('_').map(&:capitalize).join
    # 编号保留三位数字
    "V#{number}#{module_pascal}Validator"
  end
  
  # 生成 validator_id
  # @param module_name [String] 模块名
  # @param number [String] 编号
  # @return [String] validator_id，如 "v001_hotel_validator"
  def generate_validator_id(module_name, number)
    "v#{number}_#{module_name}_validator"
  end
  
  # 生成文件路径
  # @param module_name [String] 模块名
  # @param number [String] 编号
  # @return [String] 完整的文件路径
  def generate_file_path(module_name, number)
    File.join(@root_path, module_name, "v#{number}_#{module_name}_validator.rb")
  end
  
  # 确保模块目录存在
  # @param module_name [String] 模块名
  # @return [String] 目录路径
  def ensure_module_directory(module_name)
    dir_path = File.join(@root_path, module_name)
    FileUtils.mkdir_p(dir_path) unless Dir.exist?(dir_path)
    dir_path
  end
end

# 使用示例
if __FILE__ == $PROGRAM_NAME
  helper = ValidatorNumberHelper.new
  
  # 示例 1: 查找下一个可用编号
  puts "=== 示例 1: 查找 hotel 模块的下一个可用编号 ==="
  next_number = helper.find_next_number('hotel')
  puts "下一个可用编号: #{next_number}"
  puts
  
  # 示例 2: 检查编号是否存在
  puts "=== 示例 2: 检查编号是否存在 ==="
  exists = helper.number_exists?('hotel', '001')
  puts "v001_hotel_validator.rb 是否存在: #{exists}"
  puts
  
  # 示例 3: 获取可用编号（自动分配）
  puts "=== 示例 3: 自动分配编号 ==="
  result = helper.get_available_number('hotel')
  puts result[:message]
  puts "分配的编号: #{result[:number]}"
  puts
  
  # 示例 4: 获取可用编号（手动指定，有冲突）
  puts "=== 示例 4: 手动指定编号（可能有冲突） ==="
  result = helper.get_available_number('hotel', '001')
  puts result[:message]
  puts "最终编号: #{result[:number]}"
  puts "是否发生冲突: #{result[:conflict]}"
  puts
  
  # 示例 5: 列出模块中的所有 validator
  puts "=== 示例 5: 列出 hotel 模块中的所有 validator ==="
  validators = helper.list_validators('hotel')
  if validators.empty?
    puts "未找到任何 validator"
  else
    validators.each do |v|
      puts "编号: #{v[:number]}, 类名: #{v[:class_name]}, 文件: #{File.basename(v[:file])}"
    end
  end
  puts
  
  # 示例 6: 生成各种名称
  puts "=== 示例 6: 生成命名 ==="
  module_name = 'hotel'
  number = '005'
  puts "模块: #{module_name}, 编号: #{number}"
  puts "类名: #{helper.generate_class_name(module_name, number)}"
  puts "validator_id: #{helper.generate_validator_id(module_name, number)}"
  puts "文件路径: #{helper.generate_file_path(module_name, number)}"
  puts
  
  # 示例 7: 确保目录存在
  puts "=== 示例 7: 确保模块目录存在 ==="
  dir_path = helper.ensure_module_directory('new_module')
  puts "目录已创建（如果不存在）: #{dir_path}"
end
