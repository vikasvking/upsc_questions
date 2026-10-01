# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_01_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "admin_logs", force: :cascade do |t|
    t.bigint "admin_id"
    t.string "admin_email", null: false
    t.string "action", null: false
    t.string "record_type"
    t.bigint "record_id"
    t.string "record_label"
    t.text "reason"
    t.jsonb "details", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["admin_id"], name: "index_admin_logs_on_admin_id"
    t.index ["created_at"], name: "index_admin_logs_on_created_at"
    t.index ["record_type", "record_id"], name: "index_admin_logs_on_record_type_and_record_id"
  end

  create_table "audience_grants", force: :cascade do |t|
    t.string "item_type", null: false
    t.bigint "item_id", null: false
    t.string "grantee_type", null: false
    t.bigint "grantee_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["grantee_type", "grantee_id"], name: "index_audience_grants_on_grantee_type_and_grantee_id"
    t.index ["item_type", "item_id", "grantee_type", "grantee_id"], name: "index_audience_grants_unique", unique: true
  end

  create_table "batch_members", force: :cascade do |t|
    t.bigint "batch_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["batch_id", "user_id"], name: "index_batch_members_on_batch_id_and_user_id", unique: true
    t.index ["batch_id"], name: "index_batch_members_on_batch_id"
    t.index ["user_id"], name: "index_batch_members_on_user_id"
  end

  create_table "batches", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "institution_id"
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["institution_id"], name: "index_batches_on_institution_id"
    t.index ["user_id"], name: "index_batches_on_user_id"
  end

  create_table "contact_messages", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.string "phone"
    t.string "organisation"
    t.string "topic", default: "other", null: false
    t.text "message", null: false
    t.string "status", default: "new", null: false
    t.bigint "handled_by_id"
    t.datetime "handled_at"
    t.string "ip_address"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["handled_by_id"], name: "index_contact_messages_on_handled_by_id"
    t.index ["status", "created_at"], name: "index_contact_messages_on_status_and_created_at"
  end

  create_table "device_tokens", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "token", null: false
    t.string "platform", default: "android", null: false
    t.datetime "last_seen_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token"], name: "index_device_tokens_on_token", unique: true
    t.index ["user_id"], name: "index_device_tokens_on_user_id"
  end

  create_table "guardian_consents", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "parent_email", null: false
    t.string "parent_phone", null: false
    t.string "consent_version", null: false
    t.datetime "consented_at", null: false
    t.string "ip_address"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_guardian_consents_on_user_id"
  end

  create_table "institutions", force: :cascade do |t|
    t.string "name", null: false
    t.string "kind", default: "coaching", null: false
    t.string "city"
    t.string "join_code", null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "plan_id"
    t.string "subscription_status", default: "none", null: false
    t.date "subscription_started_on"
    t.date "subscription_renews_on"
    t.integer "override_max_students"
    t.integer "override_max_teachers"
    t.integer "override_max_tests_per_month"
    t.text "billing_notes"
    t.string "payment_reference"
    t.index "lower((name)::text), lower((COALESCE(city, ''::character varying))::text)", name: "index_institutions_on_name_and_city", unique: true
    t.index ["created_by_id"], name: "index_institutions_on_created_by_id"
    t.index ["join_code"], name: "index_institutions_on_join_code", unique: true
    t.index ["plan_id"], name: "index_institutions_on_plan_id"
  end

  create_table "leaderboard_snapshots", force: :cascade do |t|
    t.jsonb "rows", default: [], null: false
    t.datetime "computed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "exam_type"
    t.index ["exam_type", "computed_at"], name: "index_leaderboard_snapshots_on_exam_type_and_computed_at"
  end

  create_table "mail_settings", force: :cascade do |t|
    t.boolean "enabled", default: false, null: false
    t.string "address"
    t.integer "port", default: 587
    t.string "domain"
    t.string "user_name"
    t.text "encrypted_password"
    t.string "authentication", default: "plain"
    t.boolean "enable_starttls", default: true, null: false
    t.string "from_address"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "memberships", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "institution_id", null: false
    t.string "status", default: "pending", null: false
    t.bigint "approved_by_id"
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["approved_by_id"], name: "index_memberships_on_approved_by_id"
    t.index ["institution_id"], name: "index_memberships_on_institution_id"
    t.index ["user_id", "institution_id"], name: "index_memberships_on_user_id_and_institution_id", unique: true
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "pending_signups", force: :cascade do |t|
    t.string "token", null: false
    t.string "email_address", null: false
    t.jsonb "data", default: {}, null: false
    t.string "code_digest", null: false
    t.integer "attempts", default: 0, null: false
    t.datetime "expires_at", null: false
    t.bigint "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token"], name: "index_pending_signups_on_token", unique: true
    t.index ["user_id"], name: "index_pending_signups_on_user_id"
  end

  create_table "plans", force: :cascade do |t|
    t.string "name", null: false
    t.string "kind", default: "school", null: false
    t.integer "price_month_inr", default: 0, null: false
    t.integer "price_year_inr", default: 0, null: false
    t.integer "price_month_upgrade_inr"
    t.integer "max_students"
    t.integer "max_teachers"
    t.integer "max_tests_per_month"
    t.string "member_tier", default: "plus"
    t.integer "member_max_exams", default: 2
    t.boolean "active", default: true, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_plans_on_name", unique: true
  end

  create_table "question_reports", force: :cascade do |t|
    t.bigint "question_id", null: false
    t.bigint "user_id", null: false
    t.string "kind", null: false
    t.text "message"
    t.string "status", default: "open", null: false
    t.text "response"
    t.bigint "resolved_by_id"
    t.datetime "resolved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["question_id"], name: "index_question_reports_on_question_id"
    t.index ["resolved_by_id"], name: "index_question_reports_on_resolved_by_id"
    t.index ["status", "created_at"], name: "index_question_reports_on_status_and_created_at"
    t.index ["user_id"], name: "index_question_reports_on_user_id"
  end

  create_table "questions", force: :cascade do |t|
    t.integer "year"
    t.string "q_no"
    t.string "topic"
    t.text "content"
    t.text "option_a"
    t.text "option_b"
    t.text "option_c"
    t.text "option_d"
    t.string "correct_answer"
    t.text "explanation"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "exam_type"
    t.bigint "user_id"
    t.string "visibility", default: "public", null: false
    t.bigint "institution_id"
    t.boolean "free_sample", default: false, null: false
    t.index ["exam_type", "topic"], name: "index_questions_on_exam_type_and_topic"
    t.index ["exam_type", "year", "id"], name: "index_questions_on_exam_type_and_year_and_id"
    t.index ["free_sample"], name: "index_questions_on_free_sample"
    t.index ["institution_id"], name: "index_questions_on_institution_id"
    t.index ["user_id"], name: "index_questions_on_user_id"
    t.index ["visibility"], name: "index_questions_on_visibility"
  end

  create_table "ratings", force: :cascade do |t|
    t.string "rateable_type", null: false
    t.bigint "rateable_id", null: false
    t.bigint "user_id", null: false
    t.integer "stars", null: false
    t.text "comment"
    t.datetime "comment_hidden_at"
    t.bigint "comment_hidden_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["comment_hidden_by_id"], name: "index_ratings_on_comment_hidden_by_id"
    t.index ["rateable_type", "rateable_id", "user_id"], name: "index_ratings_one_per_student", unique: true
    t.index ["rateable_type", "rateable_id"], name: "index_ratings_on_rateable_type_and_rateable_id"
    t.index ["user_id"], name: "index_ratings_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.binary "key", null: false
    t.binary "value", null: false
    t.datetime "created_at", null: false
    t.bigint "key_hash", null: false
    t.integer "byte_size", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_batch_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "batch_id", null: false
    t.datetime "created_at", null: false
    t.index ["batch_id"], name: "index_solid_queue_batch_executions_on_batch_id"
    t.index ["job_id"], name: "index_solid_queue_batch_executions_on_job_id", unique: true
  end

  create_table "solid_queue_batches", force: :cascade do |t|
    t.string "active_job_batch_id"
    t.string "description"
    t.text "on_finish"
    t.text "on_success"
    t.text "on_failure"
    t.text "metadata"
    t.integer "total_jobs", default: 0, null: false
    t.integer "completed_jobs", default: 0, null: false
    t.integer "failed_jobs", default: 0, null: false
    t.datetime "enqueued_at"
    t.datetime "finished_at"
    t.datetime "failed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_batch_id"], name: "index_solid_queue_batches_on_active_job_batch_id", unique: true
    t.index ["finished_at"], name: "index_solid_queue_batches_on_finished_at"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "batch_id"
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["batch_id"], name: "index_solid_queue_jobs_on_batch_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "teacher_subjects", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "name"], name: "index_teacher_subjects_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_teacher_subjects_on_user_id"
  end

  create_table "test_attempts", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "test_session_id"
    t.string "topic"
    t.string "token", null: false
    t.datetime "started_at", null: false
    t.datetime "deadline_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_seen_at"
    t.integer "leave_count", default: 0, null: false
    t.datetime "blocked_at"
    t.string "block_reason"
    t.boolean "retake", default: false, null: false
    t.index ["test_session_id", "blocked_at"], name: "index_test_attempts_on_test_session_id_and_blocked_at"
    t.index ["test_session_id"], name: "index_test_attempts_on_test_session_id"
    t.index ["token"], name: "index_test_attempts_on_token", unique: true
    t.index ["user_id", "test_session_id"], name: "index_test_attempts_on_user_id_and_test_session_id"
    t.index ["user_id"], name: "index_test_attempts_on_user_id"
  end

  create_table "test_pin_entries", force: :cascade do |t|
    t.bigint "test_session_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["test_session_id", "user_id"], name: "index_test_pin_entries_on_test_session_id_and_user_id", unique: true
    t.index ["test_session_id"], name: "index_test_pin_entries_on_test_session_id"
    t.index ["user_id"], name: "index_test_pin_entries_on_user_id"
  end

  create_table "test_questions", force: :cascade do |t|
    t.bigint "test_session_id", null: false
    t.bigint "question_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["question_id"], name: "index_test_questions_on_question_id"
    t.index ["test_session_id"], name: "index_test_questions_on_test_session_id"
  end

  create_table "test_sessions", force: :cascade do |t|
    t.bigint "user_id"
    t.string "title", null: false
    t.string "exam_type", null: false
    t.integer "duration_minutes", default: 60
    t.integer "pass_mark_percentage", default: 50
    t.string "pin_code", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "access_type", default: "pin", null: false
    t.datetime "starts_at"
    t.datetime "ends_at"
    t.boolean "strict_mode", default: false, null: false
    t.string "visibility", default: "public", null: false
    t.bigint "institution_id"
    t.boolean "free_sample", default: false, null: false
    t.datetime "new_test_notified_at"
    t.datetime "results_notified_at"
    t.index ["exam_type", "created_at"], name: "index_test_sessions_on_exam_type_and_created_at"
    t.index ["free_sample"], name: "index_test_sessions_on_free_sample"
    t.index ["institution_id"], name: "index_test_sessions_on_institution_id"
    t.index ["pin_code"], name: "index_test_sessions_on_pin_code", unique: true
    t.index ["user_id"], name: "index_test_sessions_on_user_id"
    t.index ["visibility"], name: "index_test_sessions_on_visibility"
  end

  create_table "user_exams", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "exam_type", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "exam_type"], name: "index_user_exams_on_user_id_and_exam_type", unique: true
    t.index ["user_id"], name: "index_user_exams_on_user_id"
  end

  create_table "user_responses", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "question_id", null: false
    t.string "chosen_option", null: false
    t.boolean "is_correct", default: false, null: false
    t.integer "duration_seconds", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "test_session_token"
    t.index ["question_id"], name: "index_user_responses_on_question_id"
    t.index ["test_session_token", "question_id"], name: "index_user_responses_on_test_session_token_and_question_id"
    t.index ["user_id", "question_id"], name: "index_user_responses_on_user_id_and_question_id"
    t.index ["user_id"], name: "index_user_responses_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "role", default: 0, null: false
    t.string "target_exam"
    t.string "name"
    t.date "date_of_birth"
    t.text "bio"
    t.datetime "approved_at"
    t.datetime "email_confirmed_at"
    t.jsonb "permissions", default: [], null: false
    t.string "membership_tier", default: "free", null: false
    t.date "tier_until"
    t.string "tier_source"
    t.string "payment_reference"
    t.boolean "push_new_tests", default: true, null: false
    t.boolean "push_results", default: true, null: false
    t.boolean "push_reminders", default: true, null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "admin_logs", "users", column: "admin_id", on_delete: :nullify
  add_foreign_key "batch_members", "batches", on_delete: :cascade
  add_foreign_key "batch_members", "users", on_delete: :cascade
  add_foreign_key "batches", "institutions", on_delete: :nullify
  add_foreign_key "batches", "users", on_delete: :cascade
  add_foreign_key "contact_messages", "users", column: "handled_by_id", on_delete: :nullify
  add_foreign_key "device_tokens", "users", on_delete: :cascade
  add_foreign_key "guardian_consents", "users", on_delete: :cascade
  add_foreign_key "institutions", "plans", on_delete: :nullify
  add_foreign_key "institutions", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "memberships", "institutions", on_delete: :cascade
  add_foreign_key "memberships", "users", column: "approved_by_id", on_delete: :nullify
  add_foreign_key "memberships", "users", on_delete: :cascade
  add_foreign_key "pending_signups", "users", on_delete: :cascade
  add_foreign_key "question_reports", "questions", on_delete: :cascade
  add_foreign_key "question_reports", "users", column: "resolved_by_id", on_delete: :nullify
  add_foreign_key "question_reports", "users", on_delete: :cascade
  add_foreign_key "questions", "institutions", on_delete: :nullify
  add_foreign_key "questions", "users", on_delete: :nullify
  add_foreign_key "ratings", "users", column: "comment_hidden_by_id", on_delete: :nullify
  add_foreign_key "ratings", "users", on_delete: :cascade
  add_foreign_key "sessions", "users"
  add_foreign_key "solid_queue_batch_executions", "solid_queue_batches", column: "batch_id", on_delete: :cascade
  add_foreign_key "solid_queue_batch_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "teacher_subjects", "users", on_delete: :cascade
  add_foreign_key "test_attempts", "test_sessions"
  add_foreign_key "test_attempts", "users"
  add_foreign_key "test_pin_entries", "test_sessions"
  add_foreign_key "test_pin_entries", "users"
  add_foreign_key "test_questions", "questions"
  add_foreign_key "test_questions", "test_sessions"
  add_foreign_key "test_sessions", "institutions", on_delete: :nullify
  add_foreign_key "test_sessions", "users", on_delete: :nullify
  add_foreign_key "user_exams", "users", on_delete: :cascade
  add_foreign_key "user_responses", "questions"
  add_foreign_key "user_responses", "users"
end
