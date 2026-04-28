# frozen_string_literal: true

# 辅助工具：Validator 编号管理（Goomart 版）
#
# 使用示例：
#   require_relative 'validator_number_helper'
#   helper = ValidatorNumberHelper.new
#   helper.find_next_number('order')               # => "001"
#   helper.number_exists?('order', '003')          # => true/false
#   helper.get_available_number('order', '003')    # => { number: "004", conflict: true, message: "..." }
#
# A 方案（当前选定）：按业务模块分子目录
#   app/validators/{module}/v{NNN}_{module}_validator.rb
#
# Skill 是 project-scoped（放在 .clacky/skills/ 里），VALIDATORS_ROOT 会优先从
# 环境变量 GOOMART_ROOT 解析，否则相对于本文件定位到 app/validators/。

require 'pathname'

class ValidatorNumberHelper
  # 计算 Goomart 项目的 app/validators 绝对路径
  def self.default_validators_root
    # 环境变量优先（CI / 脚本外部调用）
    return ENV['GOOMART_ROOT'] + '/app/validators' if ENV['GOOMART_ROOT']

    # 本文件位于 <project>/.clacky/skills/validator-spec-generator/validator_number_helper.rb
    # 往上回溯 3 层到项目根
    here = Pathname.new(__FILE__).realpath
    project_root = here.parent.parent.parent.parent
    (project_root + 'app' + 'validators').to_s
  end

  VALIDATORS_ROOT = default_validators_root

  def initialize(root_path = VALIDATORS_ROOT)
    @root_path = root_path
  end

  # 扫描模块目录，获取下一个可用编号
  #   find_next_number('order') => "003"
  def find_next_number(module_name)
    module_dir = File.join(@root_path, module_name)
    return '001' unless Dir.exist?(module_dir)

    pattern = File.join(module_dir, "v*_validator.rb")
    numbers = Dir.glob(pattern).map do |file|
      basename = File.basename(file, '.rb')
      match = basename.match(/^v(\d{3})_/)
      match ? match[1].to_i : nil
    end.compact

    next_number = numbers.empty? ? 1 : numbers.max + 1
    format('%03d', next_number)
  end

  # 判断指定编号是否已存在（扫描目录，前缀匹配）
  def number_exists?(module_name, number)
    module_dir = File.join(@root_path, module_name)
    return false unless Dir.exist?(module_dir)

    Dir.glob(File.join(module_dir, "v#{number}_*_validator.rb")).any?
  end

  # 获取可用编号（如果冲突则自动递增）
  # @return [Hash] { number:, conflict:, message: }
  def get_available_number(module_name, requested_number = nil)
    if requested_number.nil?
      assigned = find_next_number(module_name)
      return {
        number: assigned,
        conflict: false,
        message: "自动分配编号 #{assigned}"
      }
    end

    normalized = format('%03d', requested_number.to_i)

    if number_exists?(module_name, normalized)
      next_available = find_next_number(module_name)
      return {
        number: next_available,
        conflict: true,
        message: "⚠️ 编号 #{normalized} 已存在，已自动递增到 #{next_available}"
      }
    end

    {
      number: normalized,
      conflict: false,
      message: "使用指定编号 #{normalized}"
    }
  end

  # 构造完整文件路径
  def file_path_for(module_name, number)
    File.join(@root_path, module_name, "v#{number}_#{module_name}_validator.rb")
  end

  # 构造类名（按文件名 Pascal 化，不含目录名 — Zeitwerk collapse 约定）
  # 注意：这里仅做基础兜底，实际应按完整 brief_name 生成
  # 例：file_path = "v002_reorder_previous_validator.rb" → "V002ReorderPreviousValidator"
  def class_name_for(filename)
    File.basename(filename.to_s, '.rb').split('_').map(&:capitalize).join
  end

  # 列出指定模块下所有 validator
  def list_validators(module_name)
    module_dir = File.join(@root_path, module_name)
    return [] unless Dir.exist?(module_dir)

    Dir.glob(File.join(module_dir, "v*_validator.rb")).map do |file|
      basename = File.basename(file, '.rb')
      match = basename.match(/^v(\d{3})_/)
      next nil unless match

      {
        number: match[1],
        filename: File.basename(file),
        path: file
      }
    end.compact.sort_by { |v| v[:number] }
  end

  # 列出所有业务模块（扫描 app/validators 的一级子目录）
  # 排除 support/（数据包）和其他非模块目录
  def list_modules
    return [] unless Dir.exist?(@root_path)

    Dir.entries(@root_path).select do |entry|
      next false if entry.start_with?('.')
      path = File.join(@root_path, entry)
      next false unless File.directory?(path)
      next false if %w[support].include?(entry)
      true
    end.sort
  end
end

# CLI 入口：直接执行本文件可做个烟测
if __FILE__ == $PROGRAM_NAME
  helper = ValidatorNumberHelper.new
  puts "VALIDATORS_ROOT: #{ValidatorNumberHelper::VALIDATORS_ROOT}"
  puts "已发现模块: #{helper.list_modules.inspect}"
  %w[order cart catalog checkout account common].each do |m|
    puts "  #{m}: next = #{helper.find_next_number(m)} (已有 #{helper.list_validators(m).size} 个)"
  end
end
