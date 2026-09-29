import { Controller } from "@hotwired/stimulus"

// Strict-mode tests (attached to the quiz arena page only when the test has strict mode on).
//
// How "leaving" is detected:
//  - switching tab/app or minimising  -> page becomes hidden; reported when the student comes back
//  - opening another page in the app  -> reported after the grace period if they have not returned
//  - closing / reloading / navigating away -> remembered in sessionStorage and reported when the
//    test page loads again in this tab (a quick refresh stays under the grace period and is ignored)
//  - never coming back at all        -> the heartbeat stops; the server blocks after its timeout
//
// Everything is decided on the server; this only reports what happened.
export default class extends Controller {
  static values = {
    token: String,
    heartbeatUrl: String,
    leaveUrl: String,
    heartbeatMs: { type: Number, default: 15000 },
    graceMs: { type: Number, default: 5000 }
  }
  static targets = ["banner"]

  connect() {
    // Back from another page of the app within the grace period: not counted
    if (window.__strictNavTimer) {
      clearTimeout(window.__strictNavTimer)
      window.__strictNavTimer = null
    }

    this.onVisibility = this.onVisibility.bind(this)
    this.onPageHide = this.onPageHide.bind(this)
    document.addEventListener("visibilitychange", this.onVisibility)
    window.addEventListener("pagehide", this.onPageHide)

    const leftAt = this.takeStoredLeave()
    const away = leftAt ? Date.now() - leftAt : 0
    if (away >= this.graceMsValue) {
      this.report("reloaded", away)
    } else {
      this.beat()
    }

    this.heartbeatTimer = setInterval(() => this.beat(), this.heartbeatMsValue)
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.onVisibility)
    window.removeEventListener("pagehide", this.onPageHide)
    clearInterval(this.heartbeatTimer)

    // Turbo moved to another page. If it is the next question, the new page's connect() cancels
    // this. If the student really left the test, it is reported after the grace period.
    const payload = { url: this.leaveUrlValue, token: this.tokenValue, seconds: Math.round(this.graceMsValue / 1000) }
    window.__strictNavTimer = setTimeout(() => {
      window.__strictNavTimer = null
      send(payload.url, { token: payload.token, kind: "navigated", seconds: payload.seconds })
    }, this.graceMsValue)
  }

  onVisibility() {
    if (document.visibilityState === "hidden") {
      this.hiddenAt = Date.now()
      return
    }
    const away = this.hiddenAt ? Date.now() - this.hiddenAt : 0
    this.hiddenAt = null
    if (away >= this.graceMsValue) {
      this.report("hidden", away)
    } else {
      this.beat()
    }
  }

  onPageHide() {
    try { sessionStorage.setItem(this.storageKey, String(Date.now())) } catch (_) { /* storage blocked */ }
  }

  takeStoredLeave() {
    try {
      const value = sessionStorage.getItem(this.storageKey)
      sessionStorage.removeItem(this.storageKey)
      return value ? parseInt(value, 10) : null
    } catch (_) {
      return null
    }
  }

  get storageKey() {
    return `strict-left-at:${this.tokenValue}`
  }

  beat() {
    if (document.visibilityState !== "visible") return // a hidden page does not count as present
    send(this.heartbeatUrlValue, { token: this.tokenValue }).then((data) => this.handle(data))
  }

  report(kind, awayMs) {
    send(this.leaveUrlValue, { token: this.tokenValue, kind, seconds: Math.round(awayMs / 1000) })
      .then((data) => this.handle(data, true))
  }

  handle(data, afterLeaving = false) {
    if (!data) return

    if (data.status === "blocked" || data.status === "finished") {
      if (data.message) window.alert(data.message)
      window.location.assign(data.redirect_to)
      return
    }

    if (afterLeaving && data.leave_count > 0 && this.hasBannerTarget && !this.warned) {
      this.warned = true
      this.bannerTarget.className = "rounded-xl p-3 border text-xs font-bold bg-red-50 dark:bg-red-950/40 border-red-200 dark:border-red-900/40 text-red-800 dark:text-red-300"
      this.bannerTarget.textContent = "⚠️ You left the test once. This was your only warning — if you leave again you will be blocked."
      window.alert("You left the test. This is your only warning — if you leave again you will be blocked.")
    }
  }
}

// POST JSON with the Rails CSRF token. keepalive lets the request finish while the page changes.
function send(url, body) {
  const token = document.querySelector('meta[name="csrf-token"]')?.content
  return fetch(url, {
    method: "POST",
    keepalive: true,
    credentials: "same-origin",
    headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": token || "" },
    body: JSON.stringify(body)
  })
    .then((response) => (response.ok ? response.json() : null))
    .catch(() => null) // offline: the server-side timeout still applies
}
