require "test_helper"

class QuestionOrderTest < ActiveSupport::TestCase
  test "questions no longer need a number and keep the order they were added" do
    a = Question.create!(topic: "Geography", content: "First added", exam_type: "UPSC", year: 2025, correct_answer: "a", option_a: "x")
    b = Question.create!(topic: "Geography", content: "Second added", exam_type: "UPSC", year: 2025, correct_answer: "B", option_b: "y")

    assert_nil a.q_no
    assert_equal "A", a.correct_answer
    assert_equal [a, b], Question.where(topic: "Geography").in_order.to_a
  end
end
