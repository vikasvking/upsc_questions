# Payments for Warrior (students) and school plans (teachers): UPI QR + transaction ID checked by an admin,
# or Razorpay when the admin switches it on. PaymentSetting holds the keys, the switch and the UPI ID.
class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_settings do |t|
      t.boolean :gateway_enabled, null: false, default: false
      t.string :razorpay_key_id
      t.text :encrypted_razorpay_key_secret
      t.string :upi_id
      t.string :payee_name
      t.text :instructions
      t.timestamps
    end

    create_table :payments do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :plan, null: false, foreign_key: true
      t.references :institution, foreign_key: { on_delete: :nullify } # school plans only
      t.string :period, null: false, default: "month"
      t.integer :amount_inr, null: false
      t.string :pay_method, null: false, default: "upi_qr"
      t.string :status, null: false, default: "pending"
      t.string :utr
      t.string :razorpay_order_id
      t.string :razorpay_payment_id
      t.date :paid_until
      t.references :reviewed_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :reviewed_at
      t.string :admin_note
      t.timestamps
    end
    add_index :payments, [:status, :created_at]
    add_index :payments, :utr, unique: true, where: "utr IS NOT NULL"
    add_index :payments, :razorpay_order_id, unique: true, where: "razorpay_order_id IS NOT NULL"
  end
end
