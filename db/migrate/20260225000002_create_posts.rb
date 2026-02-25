# frozen_string_literal: true

class CreatePosts < ActiveRecord::Migration[7.2]
  def change
    create_table :posts do |t|
      t.string  :title,        null: false
      t.text    :body
      t.string  :status,       null: false, default: 'draft'
      t.references :user,      null: false, foreign_key: true

      t.string :data_version, null: false, default: '0', limit: 50
      t.index  :data_version

      t.timestamps
    end
  end
end
