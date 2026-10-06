import { SecureFilePipe } from '../../../../shared/pipes/secure-file.pipe';
import { Component, Input } from '@angular/core';
import { Testimonial } from '../../models/site.model';

@Component({
  selector: 'app-testimonial-card',
  standalone: true,
  imports: [SecureFilePipe],
  template: `
    <figure class="quote h-100 mb-0">
      <blockquote class="quote-text">{{ t.quote }}</blockquote>
      <figcaption class="d-flex align-items-center gap-3">
        @if (t.avatarUrl) {
          <img [src]="t.avatarUrl | secureFile" [alt]="t.name" class="rounded-circle avatar" width="40" height="40">
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
    /* A token, not a ".theme-dark .role" rule: that selector is scoped to this component, while
       .theme-dark sits on the layout's wrapper, so it never matched and a dark tenant kept the light-mode
       value. Two dark triggers, because two theme systems reach this quote: the tenant's own site theme
       (.theme-dark, set by ThemeDirective on the layout wrapper) and the app's data-theme, which
       /portal/{slug} is not exempt from in ThemeService.LIGHT_ONLY_ROUTES. */
    :host { --ink-subtle: #77808c; }
    :host-context(.theme-dark),
    :host-context([data-theme='dark']) { --ink-subtle: rgba(255, 255, 255, 0.6); }

    /* A pull-quote rather than a shadowed card with gold stars: the name under the quote carries the credibility. */
    /* Left as it is. The rule is decoration - it marks a pull-quote that the text and the name already
       identify - and it is built from --site-primary-rgb, which has no ink counterpart; expressing it as a
       color-mix() of the ink would make the border vanish entirely in a browser without color-mix(),
       instead of falling back to the ink the way a color declaration does. It measures 1.26:1 on a dark
       tenant and 1.83:1 on a light one, i.e. it was already faint before this pass. */
    .quote { display: flex; flex-direction: column; gap: 1.25rem; padding: 0 0 0 1.25rem; border-left: 2px solid rgba(var(--site-primary-rgb), 0.35); }
    .quote-text { margin: 0; font-size: 1.03rem; line-height: 1.62; }
    .quote-text::before { content: '“'; }
    .quote-text::after { content: '”'; }
    figcaption { margin-top: auto; }
    .avatar { width: 40px; height: 40px; object-fit: cover; flex: 0 0 auto; }
    /* The initial shown when a testimonial has no avatar. The disc is the brand at 12%, which over #0f172a
       resolves to #211f45, so the letter was #6D28D9 on #211f45: 2.20:1. The disc stays the tenant's tint. */
    .avatar-placeholder { border-radius: 50%; background: rgba(var(--site-primary-rgb), 0.12); color: var(--site-primary-ink); display: flex; align-items: center; justify-content: center; font-weight: 600; }
    .name { font-size: 0.95rem; }
    .role, .rating { font-size: 0.83rem; color: var(--ink-subtle); }
  `]
})
export class TestimonialCardComponent {
  @Input({ required: true }) t!: Testimonial;
}
