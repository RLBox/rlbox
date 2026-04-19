class Administrator < ApplicationRecord
  # System model — globally visible, not scoped per validator session
  data_version_excluded!
  # 不使用 data_version 机制：移除 default_scope 和 before_create 回调
  default_scope { unscope(where: :data_version) }
  skip_callback :create, :before, :set_data_version

  validates :name, presence: true, uniqueness: true
  validates :role, presence: true, inclusion: { in: %w[admin super_admin] }
  has_secure_password

  has_many :admin_oplogs, dependent: :destroy

  # Role constants
  ROLES = %w[admin super_admin].freeze

  # Role check methods
  def super_admin?
    role == 'super_admin'
  end

  def admin?
    role == 'admin'
  end

  # Permission check methods
  def can_manage_administrators?
    super_admin?
  end

  def can_delete_administrators?
    super_admin?
  end

  def can_be_deleted_by?(current_admin)
    return false unless current_admin.can_delete_administrators?
    # Super admin cannot delete themselves
    return false if self == current_admin
    true
  end

  # Display role name
  def role_name
    case role
    when 'super_admin'
      'Super Admin'
    when 'admin'
      'Admin'
    else
      role.humanize
    end
  end

  # Role options for form select
  def self.role_options
    [
      ['Admin', 'admin'],
      ['Super Admin', 'super_admin']
    ]
  end
end
