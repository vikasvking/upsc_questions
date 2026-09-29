# Who can see a test or question: everyone, the teacher's institution, or selected students/institutions/batches
class AddVisibilityAndBatches < ActiveRecord::Migration[8.1]
  def change
    %i[test_sessions questions].each do |table|
      add_column table, :visibility, :string, default: "public", null: false
      add_reference table, :institution, foreign_key: { on_delete: :nullify } # for "my institution"
      add_index table, :visibility
    end

    # A teacher's saved group of students, e.g. "Batch A – UPSC 2027"
    create_table :batches do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade } # the teacher who made it
      t.references :institution, foreign_key: { on_delete: :nullify }
      t.string :name, null: false
      t.timestamps
    end

    create_table :batch_members do |t|
      t.references :batch, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end
    add_index :batch_members, [:batch_id, :user_id], unique: true

    # "Selected": which students, institutions or batches may see a test or question
    create_table :audience_grants do |t|
      t.string :item_type, null: false     # TestSession or Question
      t.bigint :item_id, null: false
      t.string :grantee_type, null: false  # User, Institution or Batch
      t.bigint :grantee_id, null: false
      t.timestamps
    end
    add_index :audience_grants, [:item_type, :item_id, :grantee_type, :grantee_id], unique: true, name: "index_audience_grants_unique"
    add_index :audience_grants, [:grantee_type, :grantee_id]
  end
end
