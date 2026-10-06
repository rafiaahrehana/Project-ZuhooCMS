import { ChangeDetectorRef, Component, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DatePipe } from '@angular/common';
import { SiteService } from '../../services/site.service';
import { TrackedRequest } from '../../models/site.model';
import { BreadcrumbComponent } from '../../components/breadcrumb/breadcrumb.component';

@Component({
  selector: 'app-site-track-request',
  standalone: true,
  imports: [FormsModule, BreadcrumbComponent, DatePipe],
  template: `
    <div class="pt-5" style="margin-top: 72px">
      <div class="container">
        <app-breadcrumb [items]="[{ label: 'Track Request' }]"></app-breadcrumb>
      </div>
    </div>
    <section class="py-5">
      <div class="container" style="max-width: 600px">
        <h1 class="fw-bold mb-4 text-center">Track Your <span style="color: var(--site-primary-ink)">Request</span></h1>
        <div class="card border-0 shadow-sm p-4 mb-4" style="border-radius: var(--site-radius)">
          <form (ngSubmit)="track()" class="d-flex flex-wrap gap-3">
            <input type="text" class="form-control" [(ngModel)]="code" name="code" placeholder="Enter tracking code" required
                   style="border-radius: var(--site-btn-radius); flex: 1 1 200px">
            <input type="email" class="form-control" [(ngModel)]="email" name="email" placeholder="Email used for the request" required
                   style="border-radius: var(--site-btn-radius); flex: 1 1 200px">
            <button type="submit" class="btn btn-primary px-4" [disabled]="!code || !email" style="border-radius: var(--site-btn-radius)">
              <i class="bi bi-search"></i>
            </button>
          </form>
        </div>

        @if (error) {
          <div class="alert alert-warning text-center" style="border-radius: var(--site-radius)">{{ error }}</div>
        }

        @if (tracked) {
          <div class="card border-0 shadow-sm p-4" style="border-radius: var(--site-radius)">
            <div class="d-flex justify-content-between align-items-start mb-3">
              <div>
                <h5 class="fw-bold mb-1">{{ tracked.service }}</h5>
                <small class="text-muted">Code: {{ tracked.code }}</small>
              </div>
              <span class="badge" [class.bg-success]="tracked.status === 'COMPLETED'" [class.bg-primary]="tracked.status !== 'COMPLETED'"
                    style="border-radius: var(--site-btn-radius)">{{ tracked.status }}</span>
            </div>
            <small class="text-muted d-block mb-3">Submitted: {{ tracked.submittedAt | date:'medium' }}</small>
            <div class="timeline">
              @for (step of tracked.steps; track step.label) {
                <div class="timeline-step" [class.done]="step.done">
                  <div class="step-dot"></div>
                  <div class="step-label">{{ step.label }}</div>
                </div>
              }
            </div>
          </div>
        }
      </div>
    </section>
  `,
  styles: [`
    .btn-primary { background: var(--site-primary); border-color: var(--site-primary); }
    .timeline { position: relative; padding-left: 30px; }
    .timeline-step { position: relative; padding-bottom: 20px; padding-left: 20px; border-left: 2px solid #e2e8f0; }
    .timeline-step:last-child { border-left-color: transparent; }
    .timeline-step .step-dot { position: absolute; left: -8px; top: 2px; width: 14px; height: 14px; border-radius: 50%; background: #e2e8f0; }
    .timeline-step.done .step-dot { background: var(--site-primary); }
    /* Also on the white .card, so also left alone - 7.10:1 where it actually sits. */
    .timeline-step.done { border-left-color: var(--site-primary); }
    .step-label { font-size: 0.9rem; color: #64748b; }
    /* Left on the raw brand colour: this whole timeline lives inside a .card, which keeps
       var(--bos-bg-card) - white - even on a dark tenant, so measured on the surface it actually sits on
       this is #6D28D9 on #ffffff, 7.10:1. Switching it to the ink would put the lifted dark-page tone on
       a white card and make it worse. */
    .timeline-step.done .step-label { color: var(--site-primary); font-weight: 600; }
  `]
})
export class SiteTrackRequestPage {
  private siteService = inject(SiteService);
  // Zoneless app: the async result must trigger change detection explicitly.
  private cdr = inject(ChangeDetectorRef);
  code = '';
  email = '';
  tracked: TrackedRequest | null = null;
  error = '';

  track(): void {
    this.error = '';
    this.tracked = null;
    // null is a 404 - a wrong code/email pair. An error is the lookup itself failing, which must not be
    // reported as "not found", or a visitor with a valid code is told their request does not exist.
    this.siteService.trackRequest(this.code, this.email).subscribe({
      next: r => {
        if (r) this.tracked = r;
        else this.error = 'Request not found. Please check the code and the email address.';
        this.cdr.markForCheck();
      },
      error: () => {
        this.error = 'We could not look that up just now. Please try again in a moment.';
        this.cdr.markForCheck();
      },
    });
  }
}
