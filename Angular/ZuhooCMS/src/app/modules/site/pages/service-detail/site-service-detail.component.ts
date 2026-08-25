import { Component, OnInit, ChangeDetectionStrategy, ChangeDetectorRef, DestroyRef, inject } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { NgClass } from '@angular/common';
import { switchMap } from 'rxjs';
import { SiteService } from '../../services/site.service';
import { Service } from '../../models/site.model';
import { BreadcrumbComponent } from '../../components/breadcrumb/breadcrumb.component';

@Component({
  selector: 'app-site-service-detail',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [BreadcrumbComponent, NgClass, RouterLink],
  template: `
    <div class="pt-5" style="margin-top: 72px">
      <div class="container">
        <app-breadcrumb [items]="[{ label: 'Services', url: '/services' }, { label: service?.title || 'Service' }]"></app-breadcrumb>
      </div>
    </div>

    <section class="band">
      <div class="container">
        @if (loading) {
          <p class="notice mb-0">Loading…</p>
        } @else if (!service) {
          <h1 class="page-title">Service not found</h1>
          <p class="notice mt-3 mb-0">
            That service is no longer listed.
            <a [routerLink]="basePath + '/services'" class="inline-link">See everything we offer</a>.
          </p>
        } @else {
          <div class="row g-5">
            <div class="col-lg-8">
              @if (service.categoryName) {
                <p class="category mb-2">{{ service.categoryName }}</p>
              }
              <h1 class="page-title">
                <i class="bi title-icon" [ngClass]="service.icon || 'bi-gear'"></i>{{ service.title }}
              </h1>
              <p class="lede mt-3">{{ service.summary }}</p>

              @if (service.imageUrl) {
                <img [src]="service.imageUrl" [alt]="service.title" class="service-img mt-4">
              }

              <div class="service-body mt-4" [innerHTML]="service.description"></div>

              @if (service.features?.length) {
                <h2 class="sub-title">What's included</h2>
                <ul class="included list-unstyled mb-0">
                  @for (f of service.features; track f) {
                    <li>{{ f }}</li>
                  }
                </ul>
              }

              @if (service.requirements) {
                <h2 class="sub-title">What we need from you</h2>
                <p class="body-copy mb-0">{{ service.requirements }}</p>
              }
            </div>

            <div class="col-lg-4">
              <aside class="panel">
                <h2 class="panel-title">This service</h2>
                <dl class="panel-rows mb-0">
                  @if (service.startingPrice) {
                    <div><dt>From</dt><dd class="price">{{ service.startingPrice }}</dd></div>
                  }
                  @if (service.estimatedTime) {
                    <div><dt>Timeline</dt><dd>{{ service.estimatedTime }}</dd></div>
                  }
                  @if (service.categoryName) {
                    <div><dt>Category</dt><dd>{{ service.categoryName }}</dd></div>
                  }
                </dl>
                <a [routerLink]="basePath + '/request-service'" class="btn btn-brand w-100 mt-4"
                   style="border-radius: var(--site-btn-radius)">Request this service</a>
                <a [routerLink]="basePath + '/contact'" class="panel-link">Or ask us a question first</a>
              </aside>
            </div>
          </div>
        }
      </div>
    </section>
  `,
  styles: [`
    :host { --rule: rgba(20, 23, 26, 0.11); --ink-muted: #5c6570; display: block; }
    :host-context(.theme-dark) { --rule: rgba(255, 255, 255, 0.14); --ink-muted: rgba(255, 255, 255, 0.68); }

    .band { padding: 40px 0 76px; }
    .notice { color: var(--ink-muted); }
    .inline-link { color: var(--site-primary); }

    .category { font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.07em; color: var(--ink-muted); font-weight: 600; }
    /* The icon sits inline with the title at text size. It used to be a 64px
       gradient-filled square, which made every service look like an app. */
    .page-title { font-size: clamp(1.9rem, 3.4vw, 2.6rem); font-weight: 600; letter-spacing: -0.02em; margin: 0; }
    .title-icon { color: var(--site-primary); font-size: 0.72em; margin-right: 0.5rem; }
    .lede { font-size: 1.08rem; line-height: 1.6; color: var(--ink-muted); max-width: 56ch; margin: 0; }

    .service-img { width: 100%; max-height: 380px; object-fit: cover; border-radius: var(--site-radius); }

    .sub-title { font-size: 1.15rem; font-weight: 600; margin: 2.5rem 0 1rem; }
    .body-copy { color: var(--ink-muted); line-height: 1.7; max-width: 62ch; }

    /* Ruled rows, not a grid of tinted chips with filled check circles. */
    .included li { padding: 0.7rem 0; border-top: 1px solid var(--rule); max-width: 62ch; }
    .included li:last-child { border-bottom: 1px solid var(--rule); }

    .panel { position: sticky; top: 100px; padding: 1.5rem; border: 1px solid var(--rule); border-radius: var(--site-radius); }
    .panel-title { font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.07em; color: var(--ink-muted); font-weight: 600; margin: 0 0 0.5rem; }
    .panel-rows > div { display: flex; justify-content: space-between; align-items: baseline; gap: 1rem; padding: 0.7rem 0; border-top: 1px solid var(--rule); }
    .panel-rows dt { font-size: 0.9rem; color: var(--ink-muted); font-weight: 400; }
    .panel-rows dd { margin: 0; font-weight: 600; text-align: right; }
    .panel-rows .price { color: var(--site-primary); }

    .btn-brand { background: var(--site-primary); border: 1px solid var(--site-primary); color: #fff; padding: 0.6rem 1rem; }
    .btn-brand:hover { background: var(--site-secondary); border-color: var(--site-secondary); color: #fff; }
    .panel-link { display: block; margin-top: 0.9rem; text-align: center; font-size: 0.9rem; color: var(--ink-muted); text-decoration: none; }
    .panel-link:hover { color: var(--site-primary); }

    .service-body ::ng-deep p { color: var(--ink-muted); line-height: 1.75; max-width: 62ch; }
    .service-body ::ng-deep h2, .service-body ::ng-deep h3 { font-size: 1.15rem; font-weight: 600; margin: 2rem 0 0.75rem; }
    .service-body ::ng-deep img { max-width: 100%; height: auto; border-radius: var(--site-radius); }
    .service-body ::ng-deep ul, .service-body ::ng-deep ol { color: var(--ink-muted); line-height: 1.75; max-width: 62ch; }

    @media (max-width: 991.98px) {
      .panel { position: static; }
    }
  `]
})
export class SiteServiceDetailPage implements OnInit {
  private route = inject(ActivatedRoute);
  private siteService = inject(SiteService);
  private destroyRef = inject(DestroyRef);
  basePath = this.siteService.getBasePath();
  constructor(private cdr: ChangeDetectorRef) {}
  service: Service | null = null;
  loading = true;

  ngOnInit(): void {
    // switchMap rather than a subscribe inside a subscribe: navigating straight
    // from one service to another reuses this component, and the nested version
    // left the previous request's subscription running to race the new one.
    this.route.params
      .pipe(
        switchMap((p) => this.siteService.getService(p['slug'])),
        takeUntilDestroyed(this.destroyRef),
      )
      .subscribe((s) => {
        this.service = s;
        this.loading = false;
        this.cdr.markForCheck();
      });
  }
}
