require "test_helper"

class ExamTest < ActiveSupport::TestCase
  test "nine exams" do
    assert_equal %w[UPSC_PRELIMS JEE_MAIN JEE_ADVANCED NEET SSC_CHSL SSC_CGL CBSE_XII CBSE_X IBPS], Exam.codes
  end

  test "old labels, names and codes all map to a code" do
    assert_equal "UPSC_PRELIMS", Exam.normalize("UPSC")
    assert_equal "SSC_CGL",      Exam.normalize("SSC")
    assert_equal "CBSE_X",       Exam.normalize("cbse")
    assert_equal "IBPS",         Exam.normalize("BANKING")
    assert_equal "JEE_MAIN",     Exam.normalize("JEE Main")
    assert_equal "CBSE_XII",     Exam.normalize("cbse_xii")
    assert_nil Exam.normalize("GATE")
    assert_nil Exam.normalize("")
  end

  test "each exam has its own marking" do
    assert_equal 1.33, Exam.find("UPSC_PRELIMS").marks_for(1, 1)
    assert_equal 37.0, Exam.find("JEE_MAIN").marks_for(10, 3)
    assert_equal 5.0,  Exam.find("JEE_ADVANCED").marks_for(2, 1)
    assert_equal 7.5,  Exam.find("SSC_CGL").marks_for(4, 1)
    assert_equal 2.75, Exam.find("IBPS").marks_for(3, 1)
    assert_equal 3.0,  Exam.find("CBSE_X").marks_for(3, 5)
    assert_equal "+2 correct, −0.66 wrong, 0 skipped", Exam.find("UPSC_PRELIMS").marking_text
  end

  test "questions and tests store the code even when given an old label" do
    q = Question.create!(topic: "Polity", content: "Q", exam_type: "UPSC", correct_answer: "A", option_a: "x")
    assert_equal "UPSC_PRELIMS", q.exam_type

    t = test_sessions(:one)
    t.exam_type = "GATE"
    assert_not t.valid?
    assert t.errors[:exam_type].any?
  end
end
