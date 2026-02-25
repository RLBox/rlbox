class CreateValidatorExecutions < ActiveRecord::Migration[7.2]
  def change
    create_table :validator_executions do |t|
      t.string :execution_id, null: false
      t.jsonb :state, null: false, default: {}
      t.bigint :user_id
      t.boolean :is_active, null: false, default: false

      t.timestamps
    end

    add_index :validator_executions, :execution_id, unique: true
    add_index :validator_executions, :user_id
    add_index :validator_executions, :is_active
  end
end
