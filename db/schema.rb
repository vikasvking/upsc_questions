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

ActiveRecord::Schema[8.1].define(version: 2026_09_27_095931) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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
    t.index ["user_id"], name: "index_questions_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
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
    t.bigint "user_id", null: false
    t.string "title", null: false
    t.string "exam_type", null: false
    t.integer "duration_minutes", default: 60
    t.integer "pass_mark_percentage", default: 50
    t.string "pin_code", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pin_code"], name: "index_test_sessions_on_pin_code", unique: true
    t.index ["user_id"], name: "index_test_sessions_on_user_id"
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
    t.index ["user_id", "question_id"], name: "index_user_responses_on_user_id_and_question_id"
    t.index ["user_id"], name: "index_user_responses_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "role", default: 0, null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "questions", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "test_questions", "questions"
  add_foreign_key "test_questions", "test_sessions"
  add_foreign_key "test_sessions", "users"
  add_foreign_key "user_responses", "questions"
  add_foreign_key "user_responses", "users"
end
