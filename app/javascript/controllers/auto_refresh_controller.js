import { Controller } from "@hotwired/stimulus"

// Reloads a <turbo-frame src="..."> every few seconds while the page is visible.
// Used by the teacher's live panel on a strict test's Results page.
export default class extends Controller {
  static values = { interval: { type: Number, default: 15000 } }

  connect() {
    this.timer = setInterval(() => {
      if (document.visibilityState === "visible" && typeof this.element.reload === "function") {
        this.element.reload()
      }
    }, this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }
}
