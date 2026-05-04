# frozen_string_literal: true

# Sessions is a system table per ADR-003 (business-vs-system-tables).
# It does NOT participate in the data_version soft-isolation scheme because
# auth state must persist across baseline resets and session rollbacks.
#
# Historically sessions was generated with `rails g authentication` before
# the data_version convention was codified, so it ended up with a
# data_version column + index. This migration removes that vestige.
#
# The Session model uses the "trio" pattern (ADR-003):
#   data_version_excluded!
#   default_scope { unscope(where: :data_version) }
#   skip_callback :create, :before, :set_data_version
#
# After this migration, sessions has no data_version column at all —
# the trio is effectively a no-op but kept for clarity as a system-table marker.
class DropDataVersionFromSessions < ActiveRecord::Migration[7.2]
  def up
    remove_index :sessions, :data_version if index_exists?(:sessions, :data_version)
    remove_column :sessions, :data_version if column_exists?(:sessions, :data_version)
  end

  def down
    add_column :sessions, :data_version, :string, limit: 50, default: '0', null: false
    add_index :sessions, :data_version
  end
end
