import { ChangeDetectorRef, Component, OnInit, inject } from '@angular/core';
import { ActivatedRoute } from '@angular/router';
import { SiteService } from '../../services/site.service';
import { CmsPage } from '../../models/site.model';
import { BreadcrumbComponent } from '../../components/breadcrumb/breadcrumb.component';
import { SiteNoticeComponent } from '../../components/notice/site-notice.component';

@Component({
  selector: 'app-site-cms-page',
  standalone: true,
  imports: [BreadcrumbComponent, SiteNoticeComponent],
  template: `
    <div class="pt-5" style="margin-top: 72px">
      <div class="container">
        <app-breadcrumb [items]="[{ label: page?.title || slug }]"></app-breadcrumb>
      </div>
    </div>
    <section class="py-5">
      <div class="container" style="max-width: 800px">
        @if (loading) {
          <!-- Brand as ink: the spinner's stroke is currentColor, 2.51:1 on a dark tenant before this. -->
          <div class="text-center py-5"><div class="spinner-border" style="color: var(--site-primary-ink)"></div></div>
        } @else if (failed) {
          <app-site-notice (retry)="load()"></app-site-notice>
        } @else if (page) {
          <h1 class="fw-bold mb-4">{{ page.title }}</h1>
          <div class="cms-body" [innerHTML]="page.body"></div>
        } @else {
          <!-- A 404 on the slug. This route is also the catch-all for /portal/{slug}/{anything}, and the
               service used to hand back a DEFAULT_PAGES entry (or an empty page) instead of saying so. -->
          <app-site-notice
            title="Page not found"
            message="There is no page at this address."
            icon="bi-file-earmark-x"
            [retryable]="false"></app-site-notice>
        }
      </div>
    </section>
  `,
  styles: [`.cms-body ::ng-deep p { line-height: 1.8; color: #475569; } .cms-body ::ng-deep h2, .cms-body ::ng-deep h3 { font-weight: 700; }`]
})
export class SiteCmsPageComponent implements OnInit {
  private route = inject(ActivatedRoute);
  private siteService = inject(SiteService);
  private cdr = inject(ChangeDetectorRef);
  slug = '';
  page: CmsPage | null = null;
  loading = true;
  failed = false;

  ngOnInit(): void {
    this.route.params.subscribe(p => {
      // /privacy and /terms route here with no :slug param.
      this.slug = p['slug'] || this.route.snapshot.routeConfig?.path || '';
      this.load();
    });
  }

  load(): void {
    this.loading = true;
    this.failed = false;
    this.cdr.markForCheck();
    this.siteService.getPage(this.slug).subscribe({
      next: pg => { this.page = pg; this.loading = false; this.cdr.markForCheck(); },
      error: () => { this.page = null; this.failed = true; this.loading = false; this.cdr.markForCheck(); },
    });
  }
}
