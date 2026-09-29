# Paid plans: schools pay monthly for a number of students, teachers and tests per month (their students become Plus);
# students can pay for Warrior. Free students get admin-chosen sample tests and questions, once.
class AddPlansSubscriptionsAndTiers < ActiveRecord::Migration[8.1]
  def change
    create_table :plans do |t|
      t.string  :name, null: false
      t.string  :kind, null: false, default: "school" # school or student
      t.integer :price_month_inr, default: 0, null: false
      t.integer :price_year_inr, default: 0, null: false
      t.integer :price_month_upgrade_inr                # student plans: price for Plus students upgrading
      t.integer :max_students                           # school plans (nil = no limit)
      t.integer :max_teachers
      t.integer :max_tests_per_month
      t.string  :member_tier, default: "plus"           # what the school's students get
      t.integer :member_max_exams, default: 2           # exams a Plus student can use outside school tests
      t.boolean :active, default: true, null: false
      t.integer :position, default: 0, null: false
      t.timestamps
    end
    add_index :plans, :name, unique: true

    change_table :institutions, bulk: true do |t|
      t.references :plan, foreign_key: { on_delete: :nullify }
      t.string  :subscription_status, default: "none", null: false # none, trial, active, past_due, suspended, cancelled
      t.date    :subscription_started_on
      t.date    :subscription_renews_on
      t.integer :override_max_students                  # a special deal for this school (nil = the plan's number)
      t.integer :override_max_teachers
      t.integer :override_max_tests_per_month
      t.text    :billing_notes
      t.string  :payment_reference                      # e.g. a Razorpay subscription id, later
    end

    change_table :users, bulk: true do |t|
      t.string :membership_tier, default: "free", null: false # the student's own tier: free, plus or warrior
      t.date   :tier_until                                    # nil = no end date
      t.string :tier_source                                   # paid, admin
      t.string :payment_reference
    end

    # Admin-chosen samples for free students
    add_column :test_sessions, :free_sample, :boolean, default: false, null: false
    add_column :questions, :free_sample, :boolean, default: false, null: false
    add_index :test_sessions, :free_sample
    add_index :questions, :free_sample
  end
end
