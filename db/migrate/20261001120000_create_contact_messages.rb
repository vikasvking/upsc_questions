# Messages from the contact form in the home page footer (shown only while email is on)
class CreateContactMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :contact_messages do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :phone
      t.string :organisation
      t.string :topic, null: false, default: "other"
      t.text :message, null: false
      t.string :status, null: false, default: "new"
      t.references :handled_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :handled_at
      t.string :ip_address
      t.timestamps
    end
    add_index :contact_messages, [:status, :created_at]
  end
end
