class AddColumnsToValidatorExecutions < ActiveRecord::Migration[7.2]
  def change
    add_column :validator_executions, :validator_id, :string unless column_exists?(:validator_executions, :validator_id)
    add_column :validator_executions, :score, :integer unless column_exists?(:validator_executions, :score)
    add_column :validator_executions, :status, :string unless column_exists?(:validator_executions, :status)
    add_column :validator_executions, :verify_result, :jsonb, default: {} unless column_exists?(:validator_executions, :verify_result)

    add_index :validator_executions, :validator_id unless index_exists?(:validator_executions, :validator_id)
  end
end
