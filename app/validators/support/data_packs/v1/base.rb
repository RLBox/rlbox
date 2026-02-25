# frozen_string_literal: true

# 加载 activerecord-import gem
require 'activerecord-import' unless defined?(ActiveRecord::Import)

# base_v1 数据包
# 基础数据
# 
# 用途：
# - 所有验证器的依赖数据

puts "正在加载 base_v1 数据包..."

puts "base_v1 数据包加载完成"