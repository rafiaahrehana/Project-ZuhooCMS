import { ChangeDetectorRef, Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { SiteService } from '../../services/site.service';
import { SiteSettings } from '../../models/site.model';
import { BreadcrumbComponent } from '../../components/breadcrumb/breadcrumb.component';

@Component({
  selector: 'app-site-contact',
  standalone: true,
  imports: [FormsModule, BreadcrumbComponent],
  template: `
    <div class="pt-5" style="margin-top: 72px">
      <div class="container">
        <app-breadcrumb [items]="[{ label: 'Contact' }]"></app-breadcrumb>
      </div>
    </div>
    <section class="py-5">
      <div class="container">
        <div class="row g-5">
          <div class="col-lg-5">
            <h1 class="fw-bold mb-3">Get in <span style="color: var(--site-primary-ink)">Touch</span></h1>
            <p class="text-muted mb-4">We'd love to hear from you. Reach out through any channel.</p>
            <!-- Only the tenant's real details, once they arrive: a placeholder address or phone number here
                 would be indistinguishable from the real thing. The form below still works either way. -->
            @if (settingsFailed) {
              <p class="text-muted small mb-0"><i class="bi bi-cloud-slash me-2"></i>Our contact details could not be loaded just now. The form opposite still reaches us.</p>
            }
            <div class="d-flex flex-column gap-3">
              @if (settings?.address) {
                <div class="d-flex align-items-start gap-3">
                  <div class="contact-icon"><i class="bi bi-geo-alt"></i></div>
                  <div><strong>Address</strong><p class="text-muted mb-0 small">{{ settings!.address }}</p></div>
                </div>
              }
              @if (settings?.phone) {
                <div class="d-flex align-items-start gap-3">
                  <div class="contact-icon"><i class="bi bi-telephone"></i></div>
                  <div><strong>Phone</strong><p class="text-muted mb-0 small">{{ settings!.phone }}</p></div>
                </div>
              }
              @if (settings?.email) {
                <div class="d-flex align-items-start gap-3">
                  <div class="contact-icon"><i class="bi bi-envelope"></i></div>
                  <div><strong>Email</strong><p class="text-muted mb-0 small">{{ settings!.email }}</p></div>
                </div>
              }
            </div>
          </div>
          <div class="col-lg-7">
            <div class="card border-0 shadow-sm p-4" style="border-radius: var(--site-radius)">
              @if (submitted) {
                <div class="text-center py-5">
                  <!-- Raw brand colour on purpose: inside a .card, which is white even on a dark tenant, 7.10:1. -->
                  <div class="mb-3"><i class="bi bi-check-circle" style="font-size: 3rem; color: var(--site-primary)"></i></div>
                  <h4 class="fw-bold">Message Sent!</h4>
                  <p class="text-muted">We'll get back to you shortly.</p>
                </div>
              } @else {
                <form (ngSubmit)="submit()">
                  <div class="row g-3">
                    <div class="col-md-6">
                      <label class="form-label fw-semibold">Name *</label>
                      <input type="text" class="form-control" [(ngModel)]="form.name" name="name" required>
                    </div>
                    <div class="col-md-6">
                      <label class="form-label fw-semibold">Email *</label>
                      <input type="email" class="form-control" [(ngModel)]="form.email" name="email" required>
                    </div>
                    <div class="col-md-6">
                      <label class="form-label fw-semibold">Phone</label>
                      <input type="tel" class="form-control" [(ngModel)]="form.phone" name="phone">
                    </div>
                    <div class="col-md-6">
                      <label class="form-label fw-semibold">Subject</label>
                      <input type="text" class="form-control" [(ngModel)]="form.subject" name="subject">
                    </div>
                    <div class="col-12">
                      <label class="form-label fw-semibold">Message *</label>
                      <textarea class="form-control" rows="5" [(ngModel)]="form.message" name="message" required></textarea>
                    </div>
                    <!-- submitContact used to swallow its error, so a failed send cleared the spinner and
                         showed "Message Sent!" over a message nobody received. -->
                    @if (sendError) {
                      <div class="col-12">
                        <div class="alert alert-danger mb-0" style="border-radius: var(--site-radius)">{{ sendError }}</div>
                      </div>
                    }
                    <div class="col-12">
                      <button type="submit" class="btn btn-primary px-5" [disabled]="submitting" style="border-radius: var(--site-btn-radius)">
                        @if (submitting) { <span class="spinner-border spinner-border-sm me-2"></span> }
                        Send Message
                      </button>
                    </div>
                  </div>
                </form>
              }
            </div>
          </div>
        </div>
      </div>
    </section>
  `,
  styles: [`
    /* Address / phone / e-mail markers in the left column, which is on the page, not in the form card.
       The tile is the brand at 8%, resolving to #171838 over #0f172a, so the glyph was 2.41:1. The tile
       keeps the tenant's tint; only the glyph moves to the ink. */
    .contact-icon { width: 44px; height: 44px; border-radius: 12px; background: rgba(var(--site-primary-rgb), 0.08); display: flex; align-items: center; justify-content: center; color: var(--site-primary-ink); font-size: 1.1rem; flex-shrink: 0; }
    .btn-primary { background: var(--site-primary); border-color: var(--site-primary); color: #fff; }
    .btn-primary:hover { background: var(--site-secondary); border-color: var(--site-secondary); }
  `]
})
export class SiteContactPage implements OnInit {
  private siteService = inject(SiteService);
  private cdr = inject(ChangeDetectorRef);
  /** Null until the tenant's own settings arrive - never a placeholder company. */
  settings: SiteSettings | null = null;
  settingsFailed = false;
  form = { name: '', email: '', phone: '', subject: '', message: '' };
  submitted = false;
  submitting = false;
  sendError = '';

  ngOnInit(): void {
    this.siteService.getSettings().subscribe({
      next: s => { this.settings = s; this.cdr.markForCheck(); },
      error: () => { this.settings = null; this.settingsFailed = true; this.cdr.markForCheck(); },
    });
  }

  submit(): void {
    this.submitting = true;
    this.sendError = '';
    this.cdr.markForCheck();
    this.siteService.submitContact(this.form).subscribe({
      next: () => {
        this.submitted = true;
        this.submitting = false;
        this.cdr.markForCheck();
      },
      error: () => {
        // The spinner has to stop and the form has to stay filled in, or the visitor retypes it all.
        this.sendError = 'We could not send your message just now. Please try again in a moment.';
        this.submitting = false;
        this.cdr.markForCheck();
      },
    });
  }
}
