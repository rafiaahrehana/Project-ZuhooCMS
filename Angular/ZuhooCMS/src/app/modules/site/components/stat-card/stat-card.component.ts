import { Component, Input } from '@angular/core';
import { NgClass } from '@angular/common';
import { Stat } from '../../models/site.model';

@Component({
  selector: 'app-stat-card',
  standalone: true,
  imports: [NgClass],
  template: `
    <div class="stat">
      <div class="stat-value">{{ stat.value }}</div>
      <div class="stat-label">
        @if (stat.icon) { <i class="bi" [ngClass]="stat.icon"></i> }
        <span>{{ stat.label }}</span>
      </div>
    </div>
  `,
  styles: [`
    /* A token, not a ".theme-dark .stat-label" rule: that selector is scoped to this component, while
       .theme-dark sits on the layout's wrapper, so it never matched and a dark tenant kept the light-mode
       value. Two dark triggers, because two theme systems reach this figure: the tenant's own site theme
       (.theme-dark, set by ThemeDirective on the layout wrapper) and the app's data-theme, which
       /portal/{slug} is not exempt from in ThemeService.LIGHT_ONLY_ROUTES. */
    :host { --ink-muted: #5c6570; }
    :host-context(.theme-dark),
    :host-context([data-theme='dark']) { --ink-muted: rgba(255, 255, 255, 0.65); }

    /* A figure and its caption, not a card; the admin's icon still shows, at caption size. */
    .stat { padding: 0.25rem 0; }
    /* The figure itself, and the whole point of the card: brand as ink on the page, 2.51:1 on a dark tenant.
       The .stat panel has no background of its own, so this sits straight on #0f172a. */
    .stat-value { font-size: clamp(1.75rem, 3.2vw, 2.4rem); font-weight: 600; letter-spacing: -0.02em; line-height: 1.1; color: var(--site-primary-ink); }
    .stat-label { display: flex; align-items: center; gap: 0.4rem; margin-top: 0.35rem; font-size: 0.9rem; color: var(--ink-muted); }
    .stat-label i { font-size: 0.85rem; opacity: 0.65; }
  `]
})
export class StatCardComponent {
  @Input({ required: true }) stat!: Stat;
}
