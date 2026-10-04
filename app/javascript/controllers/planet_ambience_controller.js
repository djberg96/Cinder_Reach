import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["audio", "control", "label"]

  connect() {
    this.playing = false
    this.hasPlayed = false
    this.audioTarget.volume = 1
    this.updateControl()
  }

  disconnect() {
    this.audioTarget.pause()
  }

  toggle() {
    if (this.pending) return

    if (this.playing) {
      this.audioTarget.pause()
      this.audioTarget.currentTime = 0
      this.playing = false
      this.updateControl()
      return
    }

    this.pending = true
    this.controlTarget.classList.remove("has-error")
    this.labelTarget.textContent = "Loading atmosphere…"
    if (this.audioTarget.ended) this.audioTarget.currentTime = 0

    const playback = this.audioTarget.play()
    if (!playback || !playback.then) {
      this.started()
      return
    }

    playback.then(() => this.started()).catch(() => this.showError())
  }

  started() {
    this.pending = false
    this.playing = true
    this.hasPlayed = true
    this.updateControl()
  }

  ended() {
    this.pending = false
    this.playing = false
    this.updateControl()
  }

  failed() {
    this.showError()
  }

  updateControl() {
    this.controlTarget.classList.toggle("is-playing", this.playing)
    this.controlTarget.classList.remove("has-error")
    this.controlTarget.setAttribute("aria-pressed", this.playing ? "true" : "false")
    this.labelTarget.textContent = this.playing ? "Stop atmosphere" : this.hasPlayed ? "Replay atmosphere" : "Play atmosphere"
  }

  showError() {
    this.pending = false
    this.playing = false
    this.controlTarget.classList.remove("is-playing")
    this.controlTarget.classList.add("has-error")
    this.controlTarget.setAttribute("aria-pressed", "false")
    this.labelTarget.textContent = "Sound unavailable"
  }
}
