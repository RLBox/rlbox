# frozen_string_literal: true

# demo_user_v1 数据包
# 加载方式: rake validator:reset_baseline
#
# 用途：
#   1. 为验证器和 auto_login 提供默认用户（data_version='0'）
#   2. 作为 demo 账号数据的【唯一真相源】，导出常量供 validator / profile_controller 引用
#
# 注意：
#   - email 必须与 ApplicationController#auto_login_default_user 一致
#   - rlbox base 不预置 PaymentPassword（设为 nil），下游品牌（Goomart/Kangoo）覆盖此文件时可赋真实值
#
# 见 ADR-013 Track C。

module DataPacks
  module V1
    module DemoUser
      EMAIL            = 'demo@rlbox.ai' unless defined?(EMAIL)
      NAME             = 'Demo User' unless defined?(NAME)
      LOGIN_PASSWORD   = 'password123' unless defined?(LOGIN_PASSWORD)
      PAYMENT_PASSWORD = nil unless defined?(PAYMENT_PASSWORD)  # rlbox base 无支付业务
      DATA_VERSION     = '0' unless defined?(DATA_VERSION)
    end
  end
end

puts "正在加载 demo_user_v1 数据包..."

User.insert_all([{
  name: DataPacks::V1::DemoUser::NAME,
  email: DataPacks::V1::DemoUser::EMAIL,
  password_digest: BCrypt::Password.create(DataPacks::V1::DemoUser::LOGIN_PASSWORD),
  verified: true,
  data_version: DataPacks::V1::DemoUser::DATA_VERSION
}])

if defined?(PaymentPassword) && DataPacks::V1::DemoUser::PAYMENT_PASSWORD
  PaymentPassword.insert_all([{
    user_id: User.find_by!(email: DataPacks::V1::DemoUser::EMAIL).id,
    password_digest: BCrypt::Password.create(DataPacks::V1::DemoUser::PAYMENT_PASSWORD),
    data_version: DataPacks::V1::DemoUser::DATA_VERSION
  }])
end

puts "✓ demo_user_v1 数据包加载完成"
