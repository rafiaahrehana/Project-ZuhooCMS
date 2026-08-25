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
    /* A figure and its caption, not a card. The gradient-filled icon medallion
       that used to sit on top said nothing the number didn't already say — the
       admin's chosen icon still shows, at caption size. */
    .stat { padding: 0.25rem 0; }
    .stat-value { font-size: clamp(1.75rem, 3.2vw, 2.4rem); font-weight: 600; letter-spacing: -0.02em; line-height: 1.1; color: var(--site-primary); }
    .stat-label { display: flex; align-items: center; gap: 0.4rem; margin-top: 0.35rem; font-size: 0.9rem; color: #5c6570; }
    .stat-label i { font-size: 0.85rem; opacity: 0.65; }
    .theme-dark .stat-label { color: rgba(255,255,255,0.65); }
  `]
})
export class StatCardComponent {
  @Input({ required: true }) stat!: Stat;
}
