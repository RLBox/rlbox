# frozen_string_literal: true

require 'rails_helper'

# ADR-013 Track B：/api/profile 是 agent 免认证端点，暴露 demo user 账号信息，
# 让 android agent 在 task goal 之外还能主动查到"登录邮箱/支付密码/默认地址"等
# 真实用户才知道的信息。
RSpec.describe 'Api::ProfileController', type: :request do
  describe 'GET /api/profile' do
    context 'demo user 已 seed' do
      # rlbox 的 reset_baseline 会在 spec 启动前跑过一次（dev DB），
      # 这里用 find_or_create 保证 baseline 数据存在，不依赖外部状态。
      before do
        ActiveRecord::Base.connection.execute("SET SESSION app.data_version = '0'")
        User.unscoped.find_or_create_by!(email: DataPacks::V1::DemoUser::EMAIL) do |u|
          u.name            = DataPacks::V1::DemoUser::NAME
          u.password_digest = BCrypt::Password.create(DataPacks::V1::DemoUser::LOGIN_PASSWORD)
          u.verified        = true
          u.data_version    = DataPacks::V1::DemoUser::DATA_VERSION
        end
      end

      it '返回 demo user 的账号信息' do
        get '/api/profile', headers: { 'Accept' => 'application/json' }

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body.dig('user', 'email')).to eq('demo@rlbox.ai')
        expect(body.dig('user', 'name')).to eq('Demo User')
        # rlbox base 无支付业务
        expect(body.dig('user', 'payment_password')).to be_nil
      end
    end

    context 'demo user 未 seed' do
      before do
        User.unscoped.where(email: DataPacks::V1::DemoUser::EMAIL, data_version: '0').delete_all
      end

      it '返回 404 with descriptive error' do
        get '/api/profile', headers: { 'Accept' => 'application/json' }
        expect(response).to have_http_status(:not_found)
        body = JSON.parse(response.body)
        expect(body['error']).to eq('demo user not seeded')
      end
    end
  end
end
