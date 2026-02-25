# frozen_string_literal: true

# DataVersion Convention Spec
#
# Ensures every business model either:
#   (a) has a data_version column in its table, OR
#   (b) explicitly declares data_version_excluded! in the model class
#
# This catches cases where a developer added a new model but forgot to include
# data_version in the migration, which would cause silent isolation failures.
#
# To fix a failure:
#
#   Option A — add to the migration (business model, should be version-isolated):
#     t.string :data_version, null: false, default: '0', limit: 50
#     t.index :data_version
#
#   Option B — declare excluded in the model (system/global model):
#     class MySystemModel < ApplicationRecord
#       data_version_excluded!
#     end
#
RSpec.describe 'DataVersion column convention' do
  # Load all models so ApplicationRecord.descendants is fully populated
  before(:all) do
    Dir[Rails.root.join('app/models/**/*.rb')].each { |f| require f }
  end

  it 'every ApplicationRecord model has data_version column or is explicitly excluded' do
    all_models     = DataVersionable.models
    excluded       = DataVersionable.excluded_models
    needs_column   = all_models - excluded

    missing = needs_column.select { |m| !m.column_names.include?('data_version') }

    expect(missing).to be_empty, <<~MSG
      The following models are missing a data_version column but have not called data_version_excluded!:

        #{missing.map(&:name).join("\n  ")}

      Fix by choosing one of:

        A) Add to the model's create_table migration (business model):
             t.string :data_version, null: false, default: '0', limit: 50
             t.index :data_version

        B) Declare exclusion in the model class (system/global model):
             data_version_excluded!
    MSG
  end
end
