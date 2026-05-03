class Session < ApplicationRecord
  # 系统模型，排除 data_version 隔离（ADR-003 "trio" pattern）
  #
  # Session 是系统表：认证状态必须跨 baseline reset / session rollback 持久化，
  # 不参与 data_version 软隔离方案。
  #
  # 三件套（trio）用来抵消 ApplicationRecord include DataVersionable 引入的
  # 自动行为：
  #   1. data_version_excluded!  → lint_schema 识别为系统表，不要求 4-op RLS policy
  #   2. unscope default_scope   → 抵消 where(data_version: ...) 默认过滤
  #   3. skip_callback ...       → 抵消 before_create :set_data_version
  #
  # 第 2、3 件在 sessions.data_version 列被删除后（2026-05-03 tech-debt-cleanup P1.3）
  # 依旧必需：否则 DataVersionable 会尝试给不存在的 data_version 列赋值而崩溃。
  data_version_excluded!
  default_scope { unscope(where: :data_version) }
  skip_callback :create, :before, :set_data_version

  belongs_to :user

  before_create do
    self.user_agent = Current.user_agent
    self.ip_address = Current.ip_address
  end
end
