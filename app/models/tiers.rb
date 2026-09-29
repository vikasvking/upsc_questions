# Student membership tiers.
#   Free    -> only the admin-chosen sample tests and sample questions, each once
#   Plus    -> given by the student's school while its plan is active: school tests + public tests/practice in their exams
#   Warrior -> paid by the student: every exam
# Teachers and admins are never limited.
module Tiers
  NAMES = { "free" => "Free", "plus" => "Plus", "warrior" => "Warrior" }.freeze
  RANK  = { "free" => 0, "plus" => 1, "warrior" => 2 }.freeze
  ICONS = { "free" => "🌱", "plus" => "⭐", "warrior" => "⚔️" }.freeze

  FREE_SAMPLE_TESTS     = 4  # sample tests an admin can mark for free students
  FREE_SAMPLE_QUESTIONS = 50 # sample practice questions an admin can mark
  DEFAULT_PLUS_EXAMS    = 2  # exams a Plus student can use outside school tests, when the plan does not say

  def self.higher(a, b) = RANK[a.to_s].to_i >= RANK[b.to_s].to_i ? a.to_s : b.to_s
  def self.name(tier) = NAMES.fetch(tier.to_s, tier.to_s.capitalize)
  def self.label(tier) = "#{ICONS[tier.to_s]} #{name(tier)}"
end
