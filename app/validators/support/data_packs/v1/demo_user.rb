# frozen_string_literal: true

# demo_user_v1 数据包
# 
# 用途：
# - 为验证器提供默认用户

demo_user = User.find_or_create_by(email: 'zhangsan@example.com') do |u|
  u.password = 'password123'
  u.password_confirmation = 'password123'
  u.name = '张三'
  u.verified = true
end
  
puts "✓ 张三用户加载成功"

