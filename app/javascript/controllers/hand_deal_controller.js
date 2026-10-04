import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["card", "deck"]
  static values = { key: String }

  connect() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches || this.alreadyDealt()) return

    this.rememberDeal()
    this.frame = requestAnimationFrame(() => this.deal())
  }

  disconnect() {
    cancelAnimationFrame(this.frame)
    clearTimeout(this.timer)
    this.finish()
  }

  deal() {
    if (!this.hasDeckTarget || this.cardTargets.length === 0) return

    const deck = this.deckTarget.getBoundingClientRect()

    this.cardTargets.forEach((card, index) => {
      const destination = card.getBoundingClientRect()
      const restingTransform = getComputedStyle(card).transform

      card.style.setProperty("--deal-index", index)
      card.style.setProperty("--deal-x", `${deck.left + deck.width / 2 - destination.left - destination.width / 2}px`)
      card.style.setProperty("--deal-y", `${deck.top + deck.height / 2 - destination.top - destination.height / 2}px`)
      card.style.setProperty("--rest-transform", restingTransform === "none" ? "translateY(0)" : restingTransform)
    })

    this.element.classList.add("is-dealing")
    this.deckTarget.classList.add("is-dealing")
    this.timer = setTimeout(() => this.finish(), 650 + (this.cardTargets.length - 1) * 115)
  }

  finish() {
    this.element.classList.remove("is-dealing")
    if (this.hasDeckTarget) this.deckTarget.classList.remove("is-dealing")
    this.cardTargets.forEach(card => {
      ["--deal-index", "--deal-x", "--deal-y", "--rest-transform"].forEach(property => card.style.removeProperty(property))
    })
  }

  alreadyDealt() {
    try {
      return sessionStorage.getItem(this.storageKey) === this.keyValue
    } catch (_) {
      return false
    }
  }

  rememberDeal() {
    try {
      sessionStorage.setItem(this.storageKey, this.keyValue)
    } catch (_) {
      // The animation can still run when session storage is unavailable.
    }
  }

  get storageKey() {
    return `cinder-reach:deal:${this.keyValue.split(":")[0]}`
  }
}
