import { Controller } from "@hotwired/stimulus"

/**
 * Scroll Reveal Controller
 * 
 * Handles fade-in animation on scroll
 * 
 * HTML Structure:
 * <div data-controller="scroll-reveal">
 *   <!-- content to reveal -->
 * </div>
 */
export default class extends Controller {
  observer: IntersectionObserver | null = null

  connect(): void {
    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach(entry => {
          if (entry.isIntersecting) {
            this.element.classList.add('fade-in')
            this.observer?.unobserve(this.element)
          }
        })
      },
      {
        threshold: 0.1,
        rootMargin: '0px 0px -100px 0px'
      }
    )

    this.element.classList.add('opacity-0')
    this.observer.observe(this.element)
  }

  disconnect(): void {
    this.observer?.disconnect()
  }
}
