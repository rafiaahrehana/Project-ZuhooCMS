import { Component, OnInit, ChangeDetectionStrategy, ChangeDetectorRef, inject } from '@angular/core';
import { SiteService } from '../../services/site.service';
import { Faq } from '../../models/site.model';
import { BreadcrumbComponent } from '../../components/breadcrumb/breadcrumb.component';
import { FaqItemComponent } from '../../components/faq-item/faq-item.component';
import { SiteNoticeComponent } from '../../components/notice/site-notice.component';

@Component({
  selector: 'app-site-faq',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [BreadcrumbComponent, FaqItemComponent, SiteNoticeComponent],
  template: `
    <div class="pt-5" style="margin-top: 72px">
      <div class="container">
        <app-breadcrumb [items]="[{ label: 'FAQ' }]"></app-breadcrumb>
      </div>
    </div>
    <section class="py-5">
      <div class="container" style="max-width: 800px">
        <div class="text-center mb-5">
          <h1 class="fw-bold">Frequently Asked <span style="color: var(--site-primary-ink)">Questions</span></h1>
        </div>
        @if (loading) {
          <!-- Brand as ink: the spinner's stroke is currentColor, 2.51:1 on a dark tenant before this. -->
          <div class="text-center py-5"><div class="spinner-border" style="color: var(--site-primary-ink)"></div></div>
        } @else if (failed) {
          <!-- Distinct from "No FAQs yet" below: an unreachable list is not an empty one. -->
          <app-site-notice [compact]="true" (retry)="load()"></app-site-notice>
        } @else {
          <div class="accordion" id="faqAccordion">
            @for (f of faqs; track f.id) {
              <app-faq-item [faq]="f"></app-faq-item>
            }
          </div>
          @if (!faqs.length) {
            <div class="text-center py-5 text-muted"><p>No FAQs yet. Contact us for any questions.</p></div>
          }
        }
      </div>
    </section>
  `
})
export class SiteFaqPage implements OnInit {
  private siteService = inject(SiteService);
  constructor(private cdr: ChangeDetectorRef) {}
  faqs: Faq[] = [];
  loading = true;
  failed = false;

  ngOnInit(): void {
    this.load();
  }

  load(): void {
    this.loading = true;
    this.failed = false;
    this.cdr.markForCheck();
    this.siteService.getFaqs().subscribe({
      next: f => {
        this.faqs = f;
        this.loading = false;
        this.cdr.markForCheck();
      },
      error: () => {
        this.faqs = [];
        this.failed = true;
        this.loading = false;
        this.cdr.markForCheck();
      },
    });
  }
}
