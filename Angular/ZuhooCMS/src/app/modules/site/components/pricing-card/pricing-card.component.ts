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
    /* Tokens, not ".theme-dark .plan" rules: that selector is scoped to this component, while .theme-dark
       sits on the layout's wrapper, so it never matched and a dark tenant kept the light-mode values.
       Two dark triggers, because two theme systems reach this card: the tenant's own site theme
       (.theme-dark, set by ThemeDirective on the layout wrapper) and the app's data-theme, which
       /portal/{slug} is not exempt from in ThemeService.LIGHT_ONLY_ROUTES. */
    :host {
      --rule: rgba(20, 23, 26, 0.11);
      --rule-soft: rgba(20, 23, 26, 0.08);
      --ink-muted: #5c6570;
      --ink-subtle: #77808c;
    }
    :host-context(.theme-dark),
    :host-context([data-theme='dark']) {
      --rule: rgba(255, 255, 255, 0.14);
      --rule-soft: rgba(255, 255, 255, 0.1);
      --ink-muted: rgba(255, 255, 255, 0.68);
      --ink-subtle: rgba(255, 255, 255, 0.6);
    }

    /* The featured plan is marked by a heavier border and plain text, not a rotated "Most Popular" corner ribbon. */
    .plan { display: flex; flex-direction: column; padding: 1.75rem; border: 1px solid var(--rule); border-radius: var(--site-radius); }
    /* Left on the tenant's own colour: this ring is brand-as-emphasis, the nearest thing here to a fill,
       and the .plan-flag above it says "Most popular" in words. It does measure 2.51:1 on a dark tenant,
       which is under WCAG 1.4.11's 3:1 for a UI boundary - noted rather than changed, because lightening
       the ring would repaint the one element on the page that is meant to be the tenant's colour. */
    .plan.featured { border-color: var(--site-primary); box-shadow: inset 0 0 0 1px var(--site-primary); }

    .plan-flag { font-size: 0.78rem; text-transform: uppercase; letter-spacing: 0.07em; font-weight: 600; color: var(--site-primary-ink); }
    .plan-name { font-size: 1.1rem; font-weight: 600; margin: 0 0 0.35rem; }
    .plan-desc { color: var(--ink-muted); font-size: 0.92rem; margin: 0; }
    .plan-price { margin-top: 1.25rem; }
    .plan-price .amount { font-size: 2.1rem; font-weight: 600; letter-spacing: -0.02em; }
    .plan-price .period { color: var(--ink-subtle); font-size: 0.92rem; margin-left: 0.25rem; }

    .plan-features li { padding: 0.55rem 0; border-top: 1px solid var(--rule-soft); font-size: 0.94rem; }

    .btn-primary { background: var(--site-primary); border-color: var(--site-primary); color: #fff; }
    .btn-primary:hover { background: var(--site-secondary); border-color: var(--site-secondary); }
    /* The "Start" button on a non-featured plan is an outline, i.e. brand as ink on the page rather than a
       fill, so both the label and the outline move to the ink. Longhand border-color, so a browser without
       color-mix() falls back to currentColor and keeps the outline instead of losing the shorthand.
       :hover is a real fill and stays the tenant's colour. */
    .btn-outline-brand { border: 1px solid; border-color: var(--site-primary-ink); color: var(--site-primary-ink); background: transparent; }
    .btn-outline-brand:hover { background: var(--site-primary); border-color: var(--site-primary); color: #fff; }
  `]
})
export class PricingCardComponent {
  @Input({ required: true }) plan!: PricingPlan;

  private siteService = inject(SiteService);
  basePath = this.siteService.getBasePath();
}
