# app/models/exam.rb
# The exams Rankwise supports, with each exam's marking scheme for single-correct MCQs.
# exam_type columns (questions, test_sessions, users.target_exam) store the code.
#
# Marking (checked Sep 2026 against published 2026 exam patterns):
#   UPSC Prelims GS +2 / -0.66 · JEE Main +4 / -1 · JEE Advanced (single-correct) +3 / -1
#   NEET +4 / -1 · SSC CGL and CHSL Tier 1 +2 / -0.5 · IBPS Prelims +1 / -0.25
#   CBSE: +1, no negative marking (assumption: board papers do not use negative marking)
class Exam
  Info = Struct.new(:code, :name, :correct, :wrong, keyword_init: true) do
    def to_s = name

    # Marks for a set of answers, rounded like a result sheet
    def marks_for(correct_count, wrong_count)
      (correct_count * correct - wrong_count * wrong).round(2)
    end

    def marking_text
      penalty = wrong.zero? ? "no negative marking" : "−#{format_mark(wrong)} wrong"
      "+#{format_mark(correct)} correct, #{penalty}, 0 skipped"
    end

    private

    def format_mark(value)
      return value.round.to_s if value == value.round
      ((value * 100).floor / 100.0).to_s # 2/3 shows as 0.66, as exam notices print it
    end
  end

  ALL = [
    Info.new(code: "UPSC_PRELIMS", name: "UPSC Prelims", correct: 2.0, wrong: 2.0 / 3),
    Info.new(code: "JEE_MAIN",     name: "JEE Main",     correct: 4.0, wrong: 1.0),
    Info.new(code: "JEE_ADVANCED", name: "JEE Advanced", correct: 3.0, wrong: 1.0),
    Info.new(code: "NEET",         name: "NEET",         correct: 4.0, wrong: 1.0),
    Info.new(code: "SSC_CHSL",     name: "SSC CHSL",     correct: 2.0, wrong: 0.5),
    Info.new(code: "SSC_CGL",      name: "SSC CGL",      correct: 2.0, wrong: 0.5),
    Info.new(code: "CBSE_XII",     name: "CBSE XII",     correct: 1.0, wrong: 0.0),
    Info.new(code: "CBSE_X",       name: "CBSE X",       correct: 1.0, wrong: 0.0),
    Info.new(code: "IBPS",         name: "IBPS",         correct: 1.0, wrong: 0.25)
  ].freeze

  BY_CODE = ALL.to_h { |e| [e.code, e] }.freeze
  DEFAULT = BY_CODE.fetch("UPSC_PRELIMS")

  # Labels used before September 2026, and other spellings teachers may type in Excel sheets
  LEGACY = {
    "UPSC" => "UPSC_PRELIMS", "UPSC CIVIL SERVICES" => "UPSC_PRELIMS",
    "JEE" => "JEE_MAIN", "IIT JEE MAIN" => "JEE_MAIN", "JEE ADVANCE" => "JEE_ADVANCED",
    "SSC" => "SSC_CGL", "CGL" => "SSC_CGL", "CHSL" => "SSC_CHSL",
    "CBSE" => "CBSE_X", "CBSE CLASS X" => "CBSE_X", "CBSE 10" => "CBSE_X", "CBSE CLASS XII" => "CBSE_XII", "CBSE 12" => "CBSE_XII",
    "BANKING" => "IBPS", "IBPS PO" => "IBPS", "IBPS CLERK" => "IBPS"
  }.freeze

  def self.all = ALL
  def self.codes = BY_CODE.keys

  # [["UPSC Prelims", "UPSC_PRELIMS"], ...] for select boxes
  def self.options = ALL.map { |e| [e.name, e.code] }

  # Accepts a code, a display name or an old label ("UPSC", "JEE Main", "jee_main"); nil if unknown
  def self.normalize(value)
    key = value.to_s.strip.upcase
    return nil if key.empty?
    return key if BY_CODE.key?(key)

    spaced = key.tr("_", " ").squeeze(" ")
    ALL.find { |e| e.name.upcase == spaced }&.code || LEGACY[spaced]
  end

  # Exam info for a stored value; old or unknown values fall back to UPSC Prelims marking
  def self.find(value)
    BY_CODE[normalize(value)] || DEFAULT
  end

  def self.name_for(value)
    code = normalize(value)
    code ? BY_CODE[code].name : value.to_s
  end
end
