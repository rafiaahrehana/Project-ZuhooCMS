import { ChangeDetectorRef, Component, OnInit, inject } from '@angular/core';
import { SiteService } from '../../services/site.service';
import { CmsPage, SiteSettings } from '../../models/site.model';
import { BreadcrumbComponent } from '../../components/breadcrumb/breadcrumb.component';
import { SiteNoticeComponent } from '../../components/notice/site-notice.component';

@Component({
  selector: 'app-site-careers',
  standalone: true,
  imports: [BreadcrumbComponent, SiteNoticeComponent],
  template: `
    <div class="pt-5" style="margin-top: 72px">
      <div class="container">
        <app-breadcrumb [items]="[{ label: 'Careers' }]"></app-breadcrumb>
      </div>
    </div>
    <section class="py-5">
      <div class="container" style="max-width: 800px">
        @if (failed) {
          <app-site-notice (retry)="load()"></app-site-notice>
        } @else {
          <h1 class="fw-bold mb-4">Careers at <span style="color: var(--site-primary-ink)">{{ settings?.companyName }}</span></h1>
          @if (page) {
            <div class="cms-body mb-5" [innerHTML]="page.body"></div>
          }
          <!-- Only offered once the real address has arrived: a mailto built from a placeholder would send
               applications into the void. -->
          @if (settings?.email) {
            <div class="text-center py-4">
              <p class="text-muted">Interested? Send your resume to
                <a [href]="'mailto:' + settings!.email" style="color: var(--site-primary-ink)">{{ settings!.email }}</a>
              </p>
            </div>
          }
        }
      </div>
    </section>
  `,
  styles: [`.cms-body ::ng-deep p { line-height: 1.8; color: #475569; }`]
})
export class SiteCareersPage implements OnInit {
  private siteService = inject(SiteService);
  private cdr = inject(ChangeDetectorRef);
  /** Null until the tenant's own settings arrive - never a placeholder company. */
  settings: SiteSettings | null = null;
  page: CmsPage | null = null;
  failed = false;

  ngOnInit(): void {
    this.load();
  }

  load(): void {
    this.failed = false;
    this.cdr.markForCheck();
    this.siteService.getSettings().subscribe({
      next: s => { this.settings = s; this.cdr.markForCheck(); },
      error: () => { this.settings = null; this.failed = true; this.cdr.markForCheck(); },
    });
    // A tenant with no careers page gets a 404, i.e. null: the heading and the mailto still stand on their own.
    this.siteService.getPage('careers').subscribe({
      next: p => { this.page = p; this.cdr.markForCheck(); },
      error: () => { this.page = null; this.cdr.markForCheck(); },
    });
  }
}
