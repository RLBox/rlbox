# frozen_string_literal: true

require 'rails_helper'

# ADR-013 Track C：demo_user_v1 数据包作为 demo 账号数据的"唯一真相源"，
# 导出常量给 validator / profile_controller 引用。本 spec 固化常量的存在性和值。
RSpec.describe 'DataPacks::V1::DemoUser constants' do
  # 数据包本身在 spec 启动时已经被 reset_baseline 加载一次；
  # 但为了保证 DataPacks 常量在 isolated test 环境里可用，这里显式 load 一次。
  before(:all) do
    load Rails.root.join('app/validators/support/data_packs/v1/demo_user.rb').to_s
  end

  it '导出 EMAIL / NAME / LOGIN_PASSWORD / DATA_VERSION' do
    expect(DataPacks::V1::DemoUser::EMAIL).to eq('demo@rlbox.ai')
    expect(DataPacks::V1::DemoUser::NAME).to eq('Demo User')
    expect(DataPacks::V1::DemoUser::LOGIN_PASSWORD).to eq('password123')
    expect(DataPacks::V1::DemoUser::DATA_VERSION).to eq('0')
  end

  it 'rlbox base 不预置 PAYMENT_PASSWORD（为 nil，下游品牌覆盖）' do
    expect(DataPacks::V1::DemoUser::PAYMENT_PASSWORD).to be_nil
  end
end
