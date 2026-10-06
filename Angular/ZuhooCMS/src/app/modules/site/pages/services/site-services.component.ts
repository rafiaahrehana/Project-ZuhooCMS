import { Component, OnInit, ChangeDetectionStrategy, ChangeDetectorRef, inject } from '@angular/core';
import { SiteService } from '../../services/site.service';
import { Service, ServiceCategory } from '../../models/site.model';
import { BreadcrumbComponent } from '../../components/breadcrumb/breadcrumb.component';
import { ServiceCardComponent } from '../../components/service-card/service-card.component';
import { SiteNoticeComponent } from '../../components/notice/site-notice.component';

@Component({
  selector: 'app-site-services',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [BreadcrumbComponent, ServiceCardComponent, SiteNoticeComponent],
  template: `
    <div class="pt-5" style="margin-top: 72px">
      <div class="container">
        <app-breadcrumb [items]="[{ label: 'Services' }]"></app-breadcrumb>
      </div>
    </div>

    <section class="py-5">
      <div class="container">
        <div class="text-center mb-5">
          <h1 class="fw-bold">Our <span style="color: var(--site-primary-ink)">Services</span></h1>
          <p class="text-muted" style="max-width: 600px; margin: 0 auto">Comprehensive solutions designed to help your business thrive.</p>
        </div>

        <div class="d-flex justify-content-center gap-2 mb-5 flex-wrap">
          <button class="btn" [class.btn-primary]="!selectedCategory" [class.btn-outline-dark]="!!selectedCategory"
                  style="border-radius: var(--site-btn-radius)" (click)="filterCategory(null)">All</button>
          @for (cat of categories; track cat.id) {
            <button class="btn" [class.btn-primary]="selectedCategory === cat.slug" [class.btn-outline-dark]="selectedCategory !== cat.slug"
                    style="border-radius: var(--site-btn-radius)" (click)="filterCategory(cat.slug)">{{ cat.name }}</button>
          }
        </div>

        @if (loading) {
          <!-- Brand as ink: the spinner's stroke is currentColor, 2.51:1 on a dark tenant before this. -->
          <div class="text-center py-5"><div class="spinner-border" style="color: var(--site-primary-ink)"></div></div>
        } @else if (failed) {
          <!-- Distinct from "No services found" below: an unreachable list is not an empty one. -->
          <app-site-notice [compact]="true" (retry)="load()"></app-site-notice>
        } @else {
          <div class="row g-4">
            @for (s of filteredServices; track s.id) {
              <div class="col-md-6 col-lg-4"><app-service-card [service]="s"></app-service-card></div>
            }
          </div>
          @if (!filteredServices.length) {
            <div class="text-center py-5 text-muted"><i class="bi bi-inbox" style="font-size: 3rem; opacity: 0.3"></i><p class="mt-3">No services found.</p></div>
          }
        }
      </div>
    </section>
  `,
  styles: [`.btn-primary { background: var(--site-primary); border-color: var(--site-primary); color: #fff; }`]
})
export class SiteServicesPage implements OnInit {
  private siteService = inject(SiteService);
  constructor(private cdr: ChangeDetectorRef) {}
  services: Service[] = [];
  filteredServices: Service[] = [];
  categories: ServiceCategory[] = [];
  selectedCategory: string | null = null;
  loading = true;
  failed = false;

  ngOnInit(): void {
    this.load();
  }

  load(): void {
    this.loading = true;
    this.failed = false;
    this.cdr.markForCheck();
    this.siteService.getServices().subscribe({
      next: s => {
        this.services = s;
        this.filteredServices = s;
        this.loading = false;
        this.cdr.markForCheck();
      },
      error: () => {
        this.services = [];
        this.filteredServices = [];
        this.failed = true;
        this.loading = false;
        this.cdr.markForCheck();
      },
    });
  }

  filterCategory(slug: string | null): void {
    this.selectedCategory = slug;
    this.filteredServices = slug ? this.services.filter(s => s.categoryName === slug || s.categoryName?.toLowerCase() === slug) : this.services;
  }
}
