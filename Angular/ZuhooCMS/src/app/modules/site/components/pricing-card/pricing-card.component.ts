import { Component, Input, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { PricingPlan } from '../../models/site.model';
import { SiteService } from '../../services/site.service';

@Component({
  selector: 'app-pricing-card',
  standalone: true,
  imports: [RouterLink],
  template: `
    <div class="plan h-100" [class.featured]="plan.featured">
      @if (plan.featured) {
        <p class="plan-flag mb-2">Most chosen</p>
      }
      <h3 class="plan-name">{{ plan.name }}</h3>
      <p class="plan-desc">{{ plan.description }}</p>
      <p class="plan-price mb-4">
        <span class="amount">{{ plan.price }}</span>
        @if (plan.period) { <span class="period">{{ plan.period }}</span> }
      </p>
      <ul class="plan-features list-unstyled flex-grow-1 mb-4">
        @for (f of plan.features; track f) {
          <li>{{ f }}</li>
        }
      </ul>
      <a [routerLink]="basePath + '/request-service'" class="btn w-100 fw-semibold"
         [class.btn-primary]="plan.featured"
         [class.btn-outline-brand]="!plan.featured"
         style="border-radius: var(--site-btn-radius)">
        {{ plan.cta }}
      </a>
    </div>
  `,
  styles: [`
    /* The featured plan is marked by a heavier border and a plain line of text.
       The old rotated "Most Popular" corner ribbon is the single most reused
       ornament in template landing pages. */
    .plan { display: flex; flex-direction: column; padding: 1.75rem; border: 1px solid rgba(20, 23, 26, 0.11); border-radius: var(--site-radius); }
    .plan.featured { border-color: var(--site-primary); box-shadow: inset 0 0 0 1px var(--site-primary); }
    .theme-dark .plan { border-color: rgba(255, 255, 255, 0.14); }

    .plan-flag { font-size: 0.78rem; text-transform: uppercase; letter-spacing: 0.07em; font-weight: 600; color: var(--site-primary); }
    .plan-name { font-size: 1.1rem; font-weight: 600; margin: 0 0 0.35rem; }
    .plan-desc { color: #5c6570; font-size: 0.92rem; margin: 0; }
    .plan-price { margin-top: 1.25rem; }
    .plan-price .amount { font-size: 2.1rem; font-weight: 600; letter-spacing: -0.02em; }
    .plan-price .period { color: #77808c; font-size: 0.92rem; margin-left: 0.25rem; }

    .plan-features li { padding: 0.55rem 0; border-top: 1px solid rgba(20, 23, 26, 0.08); font-size: 0.94rem; }
    .theme-dark .plan-features li { border-color: rgba(255, 255, 255, 0.1); }
    .theme-dark .plan-desc { color: rgba(255, 255, 255, 0.68); }

    .btn-primary { background: var(--site-primary); border-color: var(--site-primary); color: #fff; }
    .btn-primary:hover { background: var(--site-secondary); border-color: var(--site-secondary); }
    .btn-outline-brand { border: 1px solid var(--site-primary); color: var(--site-primary); background: transparent; }
    .btn-outline-brand:hover { background: var(--site-primary); color: #fff; }
  `]
})
export class PricingCardComponent {
  @Input({ required: true }) plan!: PricingPlan;

  private siteService = inject(SiteService);
  basePath = this.siteService.getBasePath();
}
