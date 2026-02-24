import { Controller } from "@hotwired/stimulus"

/**
 * Navbar Scroll Controller
 * 
 * Handles sticky navigation with smooth hide/show on scroll
 * 
 * HTML Structure:
 * <nav data-controller="navbar-scroll">
 *   <!-- navbar content -->
 * </nav>
 */
export default class extends Controller {
  static values = {
    threshold: { type: Number, default: 100 }
  }

  declare thresholdValue: number
  lastScrollTop: number = 0
  isHidden: boolean = false

  connect(): void {
    this.handleScroll = this.handleScroll.bind(this)
    window.addEventListener('scroll', this.handleScroll, { passive: true })
    this.element.classList.add('transition-transform', 'duration-300')
  }

  disconnect(): void {
    window.removeEventListener('scroll', this.handleScroll)
  }

  handleScroll(): void {
    const currentScroll = window.pageYOffset || document.documentElement.scrollTop

    if (currentScroll > this.lastScrollTop && currentScroll > this.thresholdValue) {
      // Scrolling down
      if (!this.isHidden) {
        this.element.classList.add('-translate-y-full')
        this.isHidden = true
      }
    } else {
      // Scrolling up
      if (this.isHidden) {
        this.element.classList.remove('-translate-y-full')
        this.isHidden = false
      }
    }

    this.lastScrollTop = currentScroll <= 0 ? 0 : currentScroll
  }
}
