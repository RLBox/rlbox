class AddColumnsToValidatorExecutions < ActiveRecord::Migration[7.2]
  def change
    add_column :validator_executions, :validator_id, :string
    add_column :validator_executions, :score, :integer
    add_column :validator_executions, :status, :string
    add_column :validator_executions, :verify_result, :jsonb, default: {}

    add_index :validator_executions, :validator_id
  end
end
