class CreateUsers < ActiveRecord::Migration[7.2]
  def change
    create_table :users do |t|
      t.string :name
      t.string :email,     null: false, index: { unique: true }
      t.string :password_digest

      t.boolean :verified, null: false, default: false

      t.string :provider
      t.string :uid

      t.string :data_version, null: false, default: '0', limit: 50
      t.index :data_version

      t.timestamps
    end
  end
end
