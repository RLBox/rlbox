# frozen_string_literal: true

# DataVersionable Concern
#
# Validator framework data isolation via data_version.
#
# How it works:
# 1. App start: SET SESSION app.data_version = '0', load baseline data
# 2. Validator prepare: SET LOCAL app.data_version = '<uuid>'
# 3. AI creates data: before_create sets data_version = <uuid>
# 4. Validator verify: queries see data_version=0 (baseline) + <uuid> (test data)
# 5. Cleanup: DELETE WHERE data_version = <uuid>
#
# Included in ApplicationRecord — applies automatically to all domain models.
#
# Models that should NOT be data-versioned (system/global models) call:
#
#   data_version_excluded!
#
# This registers them as intentionally excluded and is checked by the
# DataVersion convention spec to distinguish "deliberately skipped" from
# "accidentally missing column".
#
module DataVersionable
  extend ActiveSupport::Concern

  included do
    before_create :set_data_version

    # Apply version filter only if the table has a data_version column.
    # Models without the column (system models, gem models) are unaffected.
    default_scope {
      column_names.include?('data_version') ? where(data_version: DataVersionable.current_versions) : all
    }

    DataVersionable.register_model(self)
  end

  class_methods do
    def inherited(subclass)
      super
      DataVersionable.register_model(subclass)
    end

    # Declare this model as intentionally excluded from data versioning.
    #
    # Use for system/global models that should not be scoped per validator session
    # (e.g. Administrator, AdminOplog, ValidatorExecution).
    #
    # This does three things:
    # 1. Registers the model in DataVersionable.excluded_models (used by convention spec)
    # 2. Removes any data_version WHERE clause from queries
    # 3. Skips the set_data_version before_create callback
    #
    # Usage:
    #   class Administrator < ApplicationRecord
    #     data_version_excluded!
    #   end
    def data_version_excluded!
      DataVersionable.exclude_model(self)
      default_scope { unscope(where: :data_version) }
      skip_callback :create, :before, :set_data_version
    end
  end

  # --- Module-level registries ---

  def self.models
    @versionable_models ||= []
  end

  def self.register_model(model_class)
    return if model_class.abstract_class?
    models << model_class unless models.include?(model_class)
  end

  def self.excluded_models
    @excluded_models ||= []
  end

  def self.exclude_model(model_class)
    excluded_models << model_class unless excluded_models.include?(model_class)
  end

  # For test isolation only
  def self.reset_models!
    @versionable_models = []
    @excluded_models = []
  end

  # Returns the data_version values the current session should query.
  # Returns ['0'] for baseline-only, or ['0', '<uuid>'] when in a validator session.
  def self.current_versions
    version_str = ActiveRecord::Base.connection.execute(
      "SELECT current_setting('app.data_version', true) AS version"
    ).first&.dig('version')

    if version_str.blank? || version_str == '0'
      ['0']
    else
      ['0', version_str]
    end
  rescue => e
    Rails.logger.warn "[DataVersionable] Failed to get current_setting: #{e.message}"
    ['0']
  end

  private

  def set_data_version
    return unless self.class.column_names.include?('data_version')

    version_str = ActiveRecord::Base.connection.execute(
      "SELECT current_setting('app.data_version', true) AS version"
    ).first&.dig('version')

    self.data_version = version_str.present? ? version_str : '0'

    if Rails.env.development?
      Rails.logger.debug "[DataVersionable] #{self.class.name}#set_data_version: '#{version_str}' → data_version=#{self.data_version}"
    end
  end
end
