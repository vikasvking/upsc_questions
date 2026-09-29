# Sub-admin is no longer its own role: it is a teacher who has admin areas in `permissions`
class MakeSubAdminsTeachers < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE users SET role = 1, approved_at = COALESCE(approved_at, NOW()) WHERE role = 3"
    execute "UPDATE users SET permissions = '[]'::jsonb WHERE role <> 1"
  end

  def down
    # nothing to undo: teachers with permissions stay teachers
  end
end
