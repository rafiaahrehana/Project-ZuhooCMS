import { Component, OnInit, ChangeDetectionStrategy, ChangeDetectorRef, inject } from '@angular/core';
import { SiteService } from '../../services/site.service';
import { PricingPlan } from '../../models/site.model';
import { BreadcrumbComponent } from '../../components/breadcrumb/breadcrumb.component';
import { PricingCardComponent } from '../../components/pricing-card/pricing-card.component';
import { SiteNoticeComponent } from '../../components/notice/site-notice.component';

@Component({
  selector: 'app-site-pricing',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [BreadcrumbComponent, PricingCardComponent, SiteNoticeComponent],
  template: `
    <div class="pt-5" style="margin-top: 72px">
      <div class="container">
        <app-breadcrumb [items]="[{ label: 'Pricing' }]"></app-breadcrumb>
      </div>
    </div>
    <section class="py-5">
      <div class="container">
        <div class="text-center mb-5">
          <h1 class="fw-bold">Pricing <span style="color: var(--site-primary-ink)">Plans</span></h1>
          <p class="text-muted" style="max-width: 600px; margin: 0 auto">Simple, transparent pricing for every business size.</p>
        </div>
        @if (loading) {
          <!-- Brand as ink: the spinner's stroke is currentColor, 2.51:1 on a dark tenant before this. -->
          <div class="text-center py-5"><div class="spinner-border" style="color: var(--site-primary-ink)"></div></div>
        } @else if (failed) {
          <!-- Prices in particular must never be guessed at, so a failure says so instead of showing nothing. -->
          <app-site-notice [compact]="true" (retry)="load()"></app-site-notice>
        } @else {
          <div class="row g-4 justify-content-center">
            @for (p of plans; track p.id) {
              <div class="col-md-6 col-lg-4"><app-pricing-card [plan]="p"></app-pricing-card></div>
            }
          </div>
          @if (!plans.length) {
            <p class="text-center text-muted py-5 mb-0">No plans are published yet. Ask us for a quote.</p>
          }
        }
      </div>
    </section>
  `
})
export class SitePricingPage implements OnInit {
  private siteService = inject(SiteService);
  constructor(private cdr: ChangeDetectorRef) {}
  plans: PricingPlan[] = [];
  loading = true;
  failed = false;

  ngOnInit(): void {
    this.load();
  }

  load(): void {
    this.loading = true;
    this.failed = false;
    this.cdr.markForCheck();
    this.siteService.getPricing().subscribe({
      next: p => {
        this.plans = p;
        this.loading = false;
        this.cdr.markForCheck();
      },
      error: () => {
        this.plans = [];
        this.failed = true;
        this.loading = false;
        this.cdr.markForCheck();
      },
    });
  }
}
