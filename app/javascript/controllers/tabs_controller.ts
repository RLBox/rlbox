import { Controller } from "@hotwired/stimulus"

/**
 * Tabs Controller
 * 
 * Handles tabbed feature navigation with animated content switch
 * 
 * HTML Structure:
 * <div data-controller="tabs">
 *   <div data-tabs-target="nav">
 *     <button data-action="click->tabs#switch" data-tabs-index-value="0">Tab 1</button>
 *     <button data-action="click->tabs#switch" data-tabs-index-value="1">Tab 2</button>
 *   </div>
 *   <div data-tabs-target="panel">Content 1</div>
 *   <div data-tabs-target="panel" class="hidden">Content 2</div>
 * </div>
 */
export default class extends Controller {
  static targets = ["nav", "panel", "tab"]
  
  declare readonly navTarget: HTMLElement
  declare readonly panelTargets: HTMLElement[]
  declare readonly tabTargets: HTMLElement[]

  connect(): void {
    // Show first panel by default
    this.showPanel(0)
  }

  switch(event: Event): void {
    const button = event.currentTarget as HTMLElement
    const index = parseInt(button.dataset.tabsIndexValue || "0")
    this.showPanel(index)
  }

  showPanel(index: number): void {
    // Update tab styles
    this.tabTargets.forEach((tab, i) => {
      if (i === index) {
        tab.classList.remove('bg-surface', 'text-secondary')
        tab.classList.add('bg-primary', 'text-surface')
      } else {
        tab.classList.remove('bg-primary', 'text-surface')
        tab.classList.add('bg-surface', 'text-secondary')
      }
    })

    // Update panel visibility with fade animation
    this.panelTargets.forEach((panel, i) => {
      if (i === index) {
        panel.classList.remove('hidden')
        panel.classList.add('fade-in')
      } else {
        panel.classList.add('hidden')
        panel.classList.remove('fade-in')
      }
    })
  }
}
