# Signup data, schools/coachings, parent consent for under-18 students, sub-admins and email settings
class AddAccountsInstitutionsAndConsent < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      t.string   :name
      t.date     :date_of_birth          # students; under 18 needs parent consent
      t.text     :bio                    # teachers
      t.datetime :approved_at            # teachers: set when an admin approves the account
      t.datetime :email_confirmed_at
      t.jsonb    :permissions, default: [], null: false # sub-admins: areas they may manage
    end

    create_table :user_exams do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :exam_type, null: false
      t.timestamps
    end
    add_index :user_exams, [:user_id, :exam_type], unique: true

    create_table :teacher_subjects do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.timestamps
    end
    add_index :teacher_subjects, [:user_id, :name], unique: true

    create_table :institutions do |t|
      t.string :name, null: false
      t.string :kind, null: false, default: "coaching" # school or coaching
      t.string :city
      t.string :join_code, null: false
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :institutions, :join_code, unique: true
    add_index :institutions, "lower(name), lower(coalesce(city, ''))", unique: true, name: "index_institutions_on_name_and_city"

    create_table :memberships do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :institution, null: false, foreign_key: { on_delete: :cascade }
      t.string :status, null: false, default: "pending" # pending or approved
      t.references :approved_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :approved_at
      t.timestamps
    end
    add_index :memberships, [:user_id, :institution_id], unique: true

    create_table :guardian_consents do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :parent_email, null: false
      t.string :parent_phone, null: false
      t.string :consent_version, null: false
      t.datetime :consented_at, null: false
      t.string :ip_address
      t.timestamps
    end

    # Under-18 signups wait here until the parent's code is entered; then the account is created
    create_table :pending_signups do |t|
      t.string :token, null: false            # in the URL of the "enter code" page
      t.string :email_address, null: false
      t.jsonb  :data, default: {}, null: false # signup details (password stored as a bcrypt digest only)
      t.string :code_digest, null: false
      t.integer :attempts, default: 0, null: false
      t.datetime :expires_at, null: false
      t.references :user, foreign_key: { on_delete: :cascade } # set when an existing account is getting consent
      t.timestamps
    end
    add_index :pending_signups, :token, unique: true

    # One row: outgoing email (SMTP) set up by the admin, with an on/off switch
    create_table :mail_settings do |t|
      t.boolean :enabled, default: false, null: false
      t.string  :address
      t.integer :port, default: 587
      t.string  :domain
      t.string  :user_name
      t.text    :encrypted_password
      t.string  :authentication, default: "plain"
      t.boolean :enable_starttls, default: true, null: false
      t.string  :from_address
      t.timestamps
    end

    reversible do |dir|
      dir.up do
        # Existing teachers were set up by you, so they count as approved; existing "Preparing for" becomes their exam
        execute "UPDATE users SET approved_at = NOW() WHERE role = 1"
        execute <<~SQL
          INSERT INTO user_exams (user_id, exam_type, created_at, updated_at)
          SELECT id, target_exam, NOW(), NOW() FROM users WHERE target_exam IS NOT NULL
        SQL
      end
    end
  end
end
