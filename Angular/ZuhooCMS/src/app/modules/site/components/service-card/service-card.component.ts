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
    /* A bordered panel that responds to hover with its border, not with a
       6-pixel jump and a coloured shadow. */
    .service { position: relative; display: flex; flex-direction: column; padding: 1.5rem; border: 1px solid rgba(20, 23, 26, 0.11); border-radius: var(--site-radius); transition: border-color 0.2s ease; }
    .service:hover { border-color: var(--site-primary); }
    .theme-dark .service { border-color: rgba(255, 255, 255, 0.14); }

    .service-icon { font-size: 1.35rem; color: var(--site-primary); margin-bottom: 0.9rem; }
    .service-title { font-size: 1.05rem; font-weight: 600; margin: 0 0 0.5rem; }
    .service-text { color: #5c6570; font-size: 0.94rem; line-height: 1.6; margin: 0; flex-grow: 1; }
    .service-price { margin-top: 0.9rem; font-size: 0.85rem; font-weight: 600; color: var(--site-primary); }
    .theme-dark .service-text { color: rgba(255, 255, 255, 0.68); }
  `]
})
export class ServiceCardComponent {
  @Input({ required: true }) service!: Service;
}
