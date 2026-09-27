class FixDatabaseRolesColumnMapping < ActiveRecord::Migration[8.1]
  def change
   # 1. Safely remove the rogue role column from the questions table if it exists
   if column_exists?(:questions, :role)
     remove_column :questions, :role, :integer
   end

   # 2. Bind the integer column parameter safely to your real users entity profile track
   unless column_exists?(:users, :role)
     add_column :users, :role, :integer, default: 0, null: false
   end
 end
end
