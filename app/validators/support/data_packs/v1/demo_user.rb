# frozen_string_literal: true

# demo_user_v1 数据包
# 加载方式: rake validator:reset_baseline
#
# 用途：为验证器和 auto_login 提供默认用户（data_version='0'）
# 注意：
#   - email 必须与 ApplicationController#auto_login_default_user 一致
#   - 具体值（EMAIL/NAME/LOGIN_PASSWORD/PAYMENT_PASSWORD/DATA_VERSION）来自
#     ./demo_user_constants.rb，本文件只做数据库写入。
#   - rlbox base 不预置 PaymentPassword（常量为 nil）；下游品牌通过覆盖常量文件定制。
#
# 见 ADR-013 Track C。

require_relative '_constants/demo_user_constants'

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
