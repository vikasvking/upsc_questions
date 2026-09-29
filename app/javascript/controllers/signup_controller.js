import { Controller } from "@hotwired/stimulus"

// Signup page: shows the fields for the chosen role, asks for a parent's contact when the
// date of birth is under 18, and shows password strength while typing. The server checks everything again.
export default class extends Controller {
  static targets = ["student", "teacher", "parent", "dob", "password", "meter", "meterText", "newInstitution", "institutionSelect", "joinCode"]
  static values = { adultAge: { type: Number, default: 18 }, minLength: { type: Number, default: 10 } }

  connect() {
    this.toggleRole()
    this.checkAge()
    this.checkPassword()
    this.toggleInstitution()
  }

  get role() {
    const checked = this.element.querySelector("input[name='signup[role]']:checked")
    return checked ? checked.value : "student"
  }

  toggleRole() {
    const teacher = this.role === "teacher"
    this.studentTargets.forEach((el) => this.show(el, !teacher))
    this.teacherTargets.forEach((el) => this.show(el, teacher))
    this.checkAge()
    this.toggleInstitution()
  }

  checkAge() {
    if (!this.hasParentTarget) return
    let minor = false
    if (this.role === "student" && this.hasDobTarget && this.dobTarget.value) {
      const dob = new Date(this.dobTarget.value)
      const now = new Date()
      let age = now.getFullYear() - dob.getFullYear()
      const birthdayPassed = now.getMonth() > dob.getMonth() || (now.getMonth() === dob.getMonth() && now.getDate() >= dob.getDate())
      if (!birthdayPassed) age -= 1
      minor = age < this.adultAgeValue
    }
    this.show(this.parentTarget, minor)
    this.parentTarget.querySelectorAll("input").forEach((input) => { input.required = minor })
  }

  toggleInstitution() {
    if (!this.hasInstitutionSelectTarget) return
    const value = this.institutionSelectTarget.value
    if (this.hasNewInstitutionTarget) this.show(this.newInstitutionTarget, value === "new" && this.role === "teacher")
    if (this.hasJoinCodeTarget) this.show(this.joinCodeTarget, value !== "" && value !== "new")
  }

  checkPassword() {
    if (!this.hasPasswordTarget || !this.hasMeterTarget) return
    const pw = this.passwordTarget.value
    let score = 0
    if (pw.length >= this.minLengthValue) score++
    if (/[A-Za-z]/.test(pw) && /\d/.test(pw)) score++
    if (/[^A-Za-z0-9]/.test(pw) || pw.length >= 14) score++
    if (/[a-z]/.test(pw) && /[A-Z]/.test(pw)) score++

    const levels = [
      ["w-1/12", "bg-red-500", "Too weak"],
      ["w-1/4", "bg-red-500", "Weak"],
      ["w-1/2", "bg-amber-500", "Okay"],
      ["w-3/4", "bg-emerald-500", "Strong"],
      ["w-full", "bg-emerald-600", "Very strong"]
    ]
    const [width, color, label] = pw.length === 0 ? ["w-0", "bg-slate-300", ""] : levels[score]
    this.meterTarget.className = `h-1.5 rounded-full transition-all ${width} ${color}`
    if (this.hasMeterTextTarget) {
      this.meterTextTarget.textContent = pw.length === 0 ? `At least ${this.minLengthValue} characters, with letters and numbers.` : label
    }
  }

  show(el, visible) {
    el.classList.toggle("hidden", !visible)
    el.querySelectorAll("input, select, textarea").forEach((input) => { input.disabled = !visible })
  }
}
