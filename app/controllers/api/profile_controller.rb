# frozen_string_literal: true

module Api
  # ADR-013 Track B：Agent Profile API
  #
  # Agent 评测流程中，task goal 字段只描述"做什么"，不应污染式地塞账号/支付密码等
  # 用户档案信息。此端点让 agent 像真实用户一样"去翻账号设置页"拿到 email/支付密码/
  # 默认地址，作为 task goal 之外的附加上下文。
  #
  # 认证策略：**免认证**（与 Api::TasksController 同级同策略）
  #   - 训练/评测环境是内部网络
  #   - Agent 只是外部触发器，不扮演用户身份
  #   - 数据固定取自 DataPacks::V1::DemoUser 常量 + baseline seed
  class ProfileController < ApplicationController
    # 跳过 auto_login 逻辑 — 本 endpoint 是 agent 查询，不需要建 session
    skip_before_action :set_current_request_details, raise: false
    skip_before_action :verify_authenticity_token, raise: false

    # GET /api/profile
    def show
      ensure_data_pack_loaded!

      email = DataPacks::V1::DemoUser::EMAIL
      user = User.unscoped.find_by(
        email: email,
        data_version: DataPacks::V1::DemoUser::DATA_VERSION
      )

      unless user
        render json: { error: 'demo user not seeded' }, status: :not_found
        return
      end

      render json: {
        user: {
          email: user.email,
          name: user.name,
          payment_password: DataPacks::V1::DemoUser::PAYMENT_PASSWORD,
          default_address: address_payload(user)
        }
      }
    end

    private

    # data_packs/v1/_constants/demo_user_constants.rb 是纯常量文件，无副作用。
    # Rails dev 环境里它不在 eager_load 范围，web 请求可能看不到常量。
    # 这里惰性 require 一次，后续请求 Ruby 自己缓存。
    def ensure_data_pack_loaded!
      return if defined?(DataPacks::V1::DemoUser::EMAIL)
      constants_path = Rails.root.join(
        'app/validators/support/data_packs/v1/_constants/demo_user_constants.rb'
      )
      require constants_path.to_s if constants_path.exist?
    end

    # 返回默认收货地址（若 Address 模型不存在或用户无地址则返回 nil）
    # 字段名适配不同品牌 schema（Goomart 用 contact_name/contact_phone/full_address；
    # duvy/Kangoo 可能用 recipient/phone/address）。
    def address_payload(user)
      return nil unless defined?(Address)
      addr = Address.unscoped.where(
        user_id: user.id,
        data_version: DataPacks::V1::DemoUser::DATA_VERSION
      ).order(is_default: :desc, id: :asc).first
      return nil unless addr

      {
        recipient: addr.try(:recipient) || addr.try(:contact_name),
        phone: addr.try(:phone) || addr.try(:contact_phone),
        address: addr.try(:full_address) || addr.try(:address)
      }
    end
  end
end
