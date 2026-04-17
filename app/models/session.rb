class Session < ApplicationRecord
  # 系统模型，排除 data_version 隔离
  default_scope { unscope(where: :data_version) }
  skip_callback :create, :before, :set_data_version

  belongs_to :user

  before_create do
    self.user_agent = Current.user_agent
    self.ip_address = Current.ip_address
  end
end
