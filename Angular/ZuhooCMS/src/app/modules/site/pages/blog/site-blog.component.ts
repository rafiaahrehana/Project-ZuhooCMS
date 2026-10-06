import { Component, OnInit, ChangeDetectionStrategy, ChangeDetectorRef, inject } from '@angular/core';
import { SiteService } from '../../services/site.service';
import { BlogPost } from '../../models/site.model';
import { BreadcrumbComponent } from '../../components/breadcrumb/breadcrumb.component';
import { BlogCardComponent } from '../../components/blog-card/blog-card.component';
import { SiteNoticeComponent } from '../../components/notice/site-notice.component';

@Component({
  selector: 'app-site-blog',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [BreadcrumbComponent, BlogCardComponent, SiteNoticeComponent],
  template: `
    <div class="pt-5" style="margin-top: 72px">
      <div class="container">
        <app-breadcrumb [items]="[{ label: 'Blog' }]"></app-breadcrumb>
      </div>
    </div>

    <section class="py-5">
      <div class="container">
        <div class="text-center mb-5">
          <h1 class="fw-bold">Our <span style="color: var(--site-primary-ink)">Blog</span></h1>
          <p class="text-muted">Insights, tips and industry news.</p>
        </div>

        @if (loading) {
          <!-- The spinner is the page's only "still working" signal, so it is information, not ornament:
               its stroke is currentColor, which on a dark tenant was #6D28D9 on #0f172a, 2.51:1. -->
          <div class="text-center py-5"><div class="spinner-border" style="color: var(--site-primary-ink)"></div></div>
        } @else if (failed) {
          <!-- Distinct from "No posts yet" below: an unreachable list is not an empty one. -->
          <app-site-notice [compact]="true" (retry)="load()"></app-site-notice>
        } @else if (posts.length) {
          <div class="row g-4">
            @for (p of posts; track p.id) {
              <div class="col-md-6 col-lg-4"><app-blog-card [post]="p"></app-blog-card></div>
            }
          </div>
        } @else {
          <div class="text-center py-5 text-muted"><i class="bi bi-newspaper" style="font-size: 3rem; opacity: 0.3"></i><p class="mt-3">No posts yet.</p></div>
        }
      </div>
    </section>
  `,
  styles: [`.btn-primary { background: var(--site-primary); border-color: var(--site-primary); color: #fff; }`]
})
export class SiteBlogPage implements OnInit {
  private siteService = inject(SiteService);
  constructor(private cdr: ChangeDetectorRef) {}
  posts: BlogPost[] = [];
  loading = true;
  failed = false;

  ngOnInit(): void {
    this.load();
  }

  load(): void {
    this.loading = true;
    this.failed = false;
    this.cdr.markForCheck();
    this.siteService.getBlogs().subscribe({
      next: p => {
        this.posts = p;
        this.loading = false;
        this.cdr.markForCheck();
      },
      error: () => {
        this.posts = [];
        this.failed = true;
        this.loading = false;
        this.cdr.markForCheck();
      },
    });
  }
}
