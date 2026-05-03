# frozen_string_literal: true

require 'rails/generators/active_record'

# rails g rls_policy TABLE
#
# Generate an idempotent migration that installs 4-op PostgreSQL RLS policies
# on a single table. See USAGE for details and prerequisites.
#
# This generator is the standard escape hatch for the snapshot-scan gap in
# split_rls_policies_by_operation: that migration only covers tables existing
# at its run-time, so any table added later inherits nothing (or inherits the
# stale FOR ALL policy). Run this generator for every new business table.
class RlsPolicyGenerator < ActiveRecord::Generators::Base
  source_root File.expand_path('templates', __dir__)

  # The Rails generator base treats the first positional arg as `name`, which
  # is normally a model name. For RLS we want an exact table name (plural, as
  # stored in PG), so we alias `table_name` to the provided name verbatim.
  desc 'Generate a migration that installs 4-op RLS policies on a single table'

  def create_migration_file
    # Sanity: warn (but not fail) if table does not exist yet. The migration is
    # still idempotent and safe to run after the table is created.
    if defined?(ActiveRecord::Base) && ActiveRecord::Base.connected?
      begin
        unless ActiveRecord::Base.connection.table_exists?(table_name)
          say_status :warn,
                     "Table '#{table_name}' does not exist yet. " \
                     'Migration will be generated but will fail until the table is created.',
                     :yellow
        end

        if ActiveRecord::Base.connection.table_exists?(table_name) &&
           !ActiveRecord::Base.connection.column_exists?(table_name, :data_version)
          say_status :warn,
                     "Table '#{table_name}' has no `data_version` column. " \
                     'RLS policies reference that column and will fail at migration time.',
                     :yellow
        end
      rescue ActiveRecord::NoDatabaseError
        # DB not created yet — skip pre-flight checks silently.
      end
    end

    migration_template(
      'migration.rb.tt',
      "db/migrate/add_rls_policies_for_#{table_name}.rb"
    )
  end

  # Expose for the ERB template.
  def table_name
    name.underscore
  end

  def migration_class_name
    "AddRlsPoliciesFor#{table_name.camelize}"
  end

  # Required by ActiveRecord::Generators::Migration
  def self.next_migration_number(dirname)
    ActiveRecord::Generators::Base.next_migration_number(dirname)
  end
end
