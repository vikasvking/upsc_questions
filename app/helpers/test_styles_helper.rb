# One look per kind of test, used on student cards, the teacher list and the admin list.
# Class names are written out in full so Tailwind finds them.
module TestStylesHelper
  TEST_KIND_STYLES = {
    strict: { label: "Strict", icon: "🛡️",
              stripe: "border-l-4 border-l-red-600",
              badge:  "bg-red-50 text-red-700 ring-1 ring-inset ring-red-200 dark:bg-red-950/40 dark:text-red-300 dark:ring-red-900/60",
              button: "bg-red-700 text-white hover:bg-red-800" },
    pin:    { label: "PIN", icon: "🔐",
              stripe: "border-l-4 border-l-sky-600",
              badge:  "bg-sky-50 text-sky-700 ring-1 ring-inset ring-sky-200 dark:bg-sky-950/40 dark:text-sky-300 dark:ring-sky-900/60",
              button: "bg-sky-700 text-white hover:bg-sky-800" },
    open:   { label: "Open to all", icon: "🟢",
              stripe: "border-l-4 border-l-emerald-600",
              badge:  "bg-emerald-50 text-emerald-700 ring-1 ring-inset ring-emerald-200 dark:bg-emerald-950/40 dark:text-emerald-300 dark:ring-emerald-900/60",
              button: "bg-emerald-700 text-white hover:bg-emerald-800" }
  }.freeze

  EXAM_CHIP_CLASSES = {
    "UPSC_PRELIMS" => "bg-indigo-50 text-indigo-700 dark:bg-indigo-950/40 dark:text-indigo-300",
    "JEE_MAIN"     => "bg-orange-50 text-orange-700 dark:bg-orange-950/40 dark:text-orange-300",
    "JEE_ADVANCED" => "bg-fuchsia-50 text-fuchsia-700 dark:bg-fuchsia-950/40 dark:text-fuchsia-300",
    "NEET"         => "bg-teal-50 text-teal-700 dark:bg-teal-950/40 dark:text-teal-300",
    "SSC_CHSL"     => "bg-violet-50 text-violet-700 dark:bg-violet-950/40 dark:text-violet-300",
    "SSC_CGL"      => "bg-purple-50 text-purple-700 dark:bg-purple-950/40 dark:text-purple-300",
    "CBSE_XII"     => "bg-cyan-50 text-cyan-700 dark:bg-cyan-950/40 dark:text-cyan-300",
    "CBSE_X"       => "bg-blue-50 text-blue-700 dark:bg-blue-950/40 dark:text-blue-300",
    "IBPS"         => "bg-yellow-50 text-yellow-800 dark:bg-yellow-950/40 dark:text-yellow-300"
  }.freeze

  def kind_of_test(test)
    if test.strict_mode? then :strict
    elsif test.pin_required? then :pin
    else :open
    end
  end

  def style_for_test(test) = TEST_KIND_STYLES.fetch(kind_of_test(test))

  # 🛡️ Strict / 🔐 PIN / 🟢 Open to all
  def kind_badge_for(test)
    style = style_for_test(test)
    tag.span("#{style[:icon]} #{style[:label]}", class: "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-semibold #{style[:badge]}")
  end

  # Exam name in the exam's own colour
  def exam_chip(code)
    klass = EXAM_CHIP_CLASSES.fetch(Exam.normalize(code).to_s, "bg-slate-100 text-slate-600 dark:bg-slate-800 dark:text-slate-300")
    tag.span(exam_name(code), class: "inline-flex items-center rounded-md px-2 py-0.5 text-xs font-semibold #{klass}")
  end
end
