# frozen_string_literal: true

# demo_user_v1 数据包
# 加载方式: rake validator:reset_baseline
#
# 用途：为验证器和 auto_login 提供默认用户（data_version='0'）
# 注意：email 必须与 ApplicationController#auto_login_default_user 一致

puts "正在加载 demo_user_v1 数据包..."

User.insert_all([
  {
    name: 'Demo User',
    email: 'demo@rlbox.ai',
    password_digest: BCrypt::Password.create('password123'),
    verified: true,
    data_version: '0'
  }
])

puts "✓ demo_user_v1 数据包加载完成"
