class DashboardsController < ApplicationController
  def show
    # Pluck all unique topics/subjects currently loaded into your Question dataset
    @subjects = Question.pluck(:topic).uniq.compact

    # Track student progress matrices (Mocked values to hook into your data model attributes later)
    @progress_map = {
      "Indian Polity" => { mastered: 78, icon: "⚖️", count: Question.where(topic: "Indian Polity").count },
      "Ancient History" => { mastered: 42, icon: "🏺", count: Question.where(topic: "Ancient History").count },
      "Medieval History" => { mastered: 15, icon: "🏰", count: Question.where(topic: "Medieval History").count },
      "Macro Economics" => { mastered: 60, icon: "📈", count: Question.where(topic: "Macro Economics").count }
    }
  end
end
