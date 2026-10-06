import { Component, Input } from '@angular/core';
import { NgClass } from '@angular/common';
import { Service } from '../../models/site.model';

@Component({
  selector: 'app-service-card',
  standalone: true,
  imports: [NgClass],
  template: `
    <div class="service h-100">
      <i class="bi service-icon" [ngClass]="service.icon || 'bi-gear'"></i>
      <h3 class="service-title">{{ service.title }}</h3>
      <p class="service-text">{{ service.summary }}</p>
      @if (service.startingPrice) {
        <p class="service-price mb-0">From {{ service.startingPrice }}</p>
      }
      <a [href]="'/services/' + service.slug" class="stretched-link">
        <span class="visually-hidden">View {{ service.title }}</span>
      </a>
    </div>
  `,
  styles: [`
    /* Tokens, not ".theme-dark .service" rules: that selector is scoped to this component, while
       .theme-dark sits on the layout's wrapper, so it never matched and a dark tenant kept the light-mode
       values. Two dark triggers, because two theme systems reach this card: the tenant's own site theme
       (.theme-dark, set by ThemeDirective on the layout wrapper) and the app's data-theme, which
       /portal/{slug} is not exempt from in ThemeService.LIGHT_ONLY_ROUTES. */
    :host {
      --rule: rgba(20, 23, 26, 0.11);
      --ink-muted: #5c6570;
    }
    :host-context(.theme-dark),
    :host-context([data-theme='dark']) {
      --rule: rgba(255, 255, 255, 0.14);
      --ink-muted: rgba(255, 255, 255, 0.68);
    }

    /* Hover moves the border, not the panel: no 6-pixel jump or coloured shadow. */
    .service { position: relative; display: flex; flex-direction: column; padding: 1.5rem; border: 1px solid var(--rule); border-radius: var(--site-radius); transition: border-color 0.2s ease; }
    /* The hover border is the card's only "this is clickable" feedback, so it is information, not
       decoration: at 2.51:1 on a dark tenant it read as no change at all. */
    .service:hover { border-color: var(--site-primary-ink); }

    .service-icon { font-size: 1.35rem; color: var(--site-primary-ink); margin-bottom: 0.9rem; }
    .service-title { font-size: 1.05rem; font-weight: 600; margin: 0 0 0.5rem; }
    .service-text { color: var(--ink-muted); font-size: 0.94rem; line-height: 1.6; margin: 0; flex-grow: 1; }
    .service-price { margin-top: 0.9rem; font-size: 0.85rem; font-weight: 600; color: var(--site-primary-ink); }
  `]
})
export class ServiceCardComponent {
  @Input({ required: true }) service!: Service;
}
