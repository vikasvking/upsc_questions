import { Controller } from "@hotwired/stimulus"

// A question visitors answer on the home page by filling a bubble (free samples only: their answer is in the page).
// Filling a bubble marks it, shows which answer is right and the explanation; "Clear my answer" starts again.
export default class extends Controller {
  static targets = ["bubble", "option", "right", "wrong", "after"]
  static values = { correct: String }

  pick(event) {
    const letter = event.currentTarget.dataset.letter
    this.bubbleTargets.forEach((b) => {
      b.setAttribute("aria-pressed", String(b.dataset.letter === letter))
      b.dataset.correct = String(b.dataset.letter === this.correctValue)
    })
    this.optionTargets.forEach((o) => { o.dataset.correct = String(o.dataset.letter === this.correctValue) })

    const right = letter === this.correctValue
    this.rightTargets.forEach((el) => { el.hidden = !right })
    this.wrongTargets.forEach((el) => { el.hidden = right })
    this.afterTargets.forEach((el) => { el.hidden = false })
  }

  clear() {
    this.bubbleTargets.forEach((b) => {
      b.setAttribute("aria-pressed", "false")
      delete b.dataset.correct
    })
    this.optionTargets.forEach((o) => { delete o.dataset.correct })
    ;[...this.rightTargets, ...this.wrongTargets, ...this.afterTargets].forEach((el) => { el.hidden = true })
    this.bubbleTargets[0]?.focus()
  }
}
