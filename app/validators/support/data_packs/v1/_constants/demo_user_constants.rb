# frozen_string_literal: true

# demo_user_v1 数据包的【常量真相源】
# ADR-013 Track C：demo 账号数据的常量导出。这个文件纯常量、无副作用，
# 可以被 controller / validator / spec 安全地 require_relative。
#
# 放在 _constants/ 子目录下是为了**与 data pack seed 脚本区分**：
#   - data_packs/v1/*.rb            → rake validator:reset_baseline 会扫这层（非递归）
#   - data_packs/v1/_constants/*.rb → 纯常量，不会被当作数据包执行
#
# 下游品牌（Goomart/Kangoo/IdleSwap/duvy）通过**覆盖本文件**来定制各自的 demo 账号值。

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
