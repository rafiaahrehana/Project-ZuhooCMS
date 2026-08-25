import { Component, Input } from '@angular/core';
import { Testimonial } from '../../models/site.model';

@Component({
  selector: 'app-testimonial-card',
  standalone: true,
  template: `
    <figure class="quote h-100 mb-0">
      <blockquote class="quote-text">{{ t.quote }}</blockquote>
      <figcaption class="d-flex align-items-center gap-3">
        @if (t.avatarUrl) {
          <img [src]="t.avatarUrl" [alt]="t.name" class="rounded-circle avatar" width="40" height="40">
        } @else {
          <div class="avatar avatar-placeholder">{{ t.name.charAt(0) }}</div>
        }
        <div>
          <div class="fw-semibold name">{{ t.name }}</div>
          <div class="role">{{ t.role }}{{ t.company ? ', ' + t.company : '' }}</div>
        </div>
        @if (t.rating) {
          <span class="rating ms-auto">{{ t.rating }}/5</span>
        }
      </figcaption>
    </figure>
  `,
  styles: [`
    /* Set as a pull-quote rather than a shadowed card with a row of gold stars
       — the name under the quote is what carries the credibility. */
    .quote { display: flex; flex-direction: column; gap: 1.25rem; padding: 0 0 0 1.25rem; border-left: 2px solid rgba(var(--site-primary-rgb), 0.35); }
    .quote-text { margin: 0; font-size: 1.03rem; line-height: 1.62; }
    .quote-text::before { content: '“'; }
    .quote-text::after { content: '”'; }
    figcaption { margin-top: auto; }
    .avatar { width: 40px; height: 40px; object-fit: cover; flex: 0 0 auto; }
    .avatar-placeholder { border-radius: 50%; background: rgba(var(--site-primary-rgb), 0.12); color: var(--site-primary); display: flex; align-items: center; justify-content: center; font-weight: 600; }
    .name { font-size: 0.95rem; }
    .role, .rating { font-size: 0.83rem; color: #77808c; }
    .theme-dark .role, .theme-dark .rating { color: rgba(255,255,255,0.6); }
  `]
})
export class TestimonialCardComponent {
  @Input({ required: true }) t!: Testimonial;
}
