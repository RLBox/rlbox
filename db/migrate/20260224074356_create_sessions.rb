class CreateSessions < ActiveRecord::Migration[7.2]
  def change
    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :user_agent
      t.string :ip_address

      t.string :data_version, null: false, default: '0', limit: 50
      t.index :data_version

      t.timestamps
    end
  end
end
