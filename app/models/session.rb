class Session < ApplicationRecord
  # 系统模型，排除 data_version 隔离（ADR-003 修订版，2026-05-03 tech-debt-cleanup）
  #
  # Session 是系统表：认证状态必须跨 baseline reset / session rollback 持久化，
  # 不参与 data_version 软隔离方案。
  #
  # 富版 `data_version_excluded!` 已经在宏内部完成：
  #   - unregister_model（不被视为业务表）
  #   - register_excluded（lint_schema 识别，免 4-op RLS policy）
  #   - skip_callback :set_data_version（create）
  #   - skip_callback :prevent_baseline_mutation!（update / destroy）
  #
  # 但 `default_scope { unscope(where: :data_version) }` **仍需手动写**：
  # ApplicationRecord 的 default_scope `where(data_version: ...)` 会被 has_many
  # 关联通过 "default values from scope" 继承，给新 build 对象自动赋 data_version=
  # 属性——而 sessions 表已经 drop 了 data_version 列（P1.3），会抛
  # ActiveModel::UnknownAttributeError。unscope 是必需的"二件套"第二件。
  data_version_excluded!
  default_scope { unscope(where: :data_version) }

  belongs_to :user

  before_create do
    self.user_agent = Current.user_agent
    self.ip_address = Current.ip_address
  end
end
