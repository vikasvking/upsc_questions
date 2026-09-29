import { Controller } from "@hotwired/stimulus"

// "Visible to": shows the institution picker or the selected-audience lists for the chosen option
export default class extends Controller {
  static targets = ["institution", "selected"]

  connect() { this.toggle() }

  toggle() {
    const checked = this.element.querySelector("input[type=radio]:checked")
    const value = checked ? checked.value : "public"
    this.show(this.institutionTarget, value === "institution")
    this.show(this.selectedTarget, value === "selected")
  }

  show(el, visible) {
    el.classList.toggle("hidden", !visible)
    el.querySelectorAll("input, select, textarea").forEach((input) => { input.disabled = !visible })
  }
}
