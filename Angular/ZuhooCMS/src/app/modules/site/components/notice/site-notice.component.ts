import { Component, EventEmitter, Input, Output } from '@angular/core';

/**
 * The public site's honest failure state, shown wherever a load fails.
 *
 * It replaces the DEFAULT_SITE / DEFAULT_SERVICES fixtures SiteService used to substitute on any error,
 * which rendered an invented company (and, for an unknown slug, a plausible wrong service) that a visitor
 * could not tell from the tenant's real content.
 *
 * Same centred block as site-not-found.component - glyph, heading, muted line, one brand-coloured action -
 * so a failure, a 404 and an empty section all read as the same page furniture.
 */
@Component({
  selector: 'app-site-notice',
  standalone: true,
  template: `
    <div class="site-notice text-center" [class.site-notice--full]="!compact">
      <div>
        <i class="bi notice-mark d-block mb-3" [class]="icon"></i>
        <h3 class="fw-bold mb-3">{{ title }}</h3>
        <p class="notice-text mb-4">{{ message }}</p>
        @if (retryable) {
          <button type="button" class="btn btn-brand px-4" style="border-radius: var(--site-btn-radius)" (click)="retry.emit()">
            <i class="bi bi-arrow-clockwise me-2"></i>Try again
          </button>
        }
      </div>
    </div>
  `,
  styles: [`
    :host { display: block; }
    .site-notice { display: flex; align-items: center; justify-content: center; padding: 2.5rem 0; }
    .site-notice--full { min-height: 60vh; }
    /* The glyph above "this could not be loaded". At 0.4 opacity on a dark tenant it was 1.33:1 - present
       in the DOM and invisible on screen, which is the worst outcome for an error state. */
    .notice-mark { font-size: 2.6rem; color: var(--site-primary-ink); opacity: 0.4; }
    .notice-text { color: var(--ink-muted, #5c6570); max-width: 46ch; margin-inline: auto; }
    :host-context(.theme-dark) .notice-text,
    :host-context([data-theme='dark']) .notice-text { color: rgba(255, 255, 255, 0.68); }
    .btn-brand { background: var(--site-primary); border: 1px solid var(--site-primary); color: #fff; }
    .btn-brand:hover { background: var(--site-secondary); border-color: var(--site-secondary); color: #fff; }
  `]
})
export class SiteNoticeComponent {
  @Input() title = 'Content unavailable';
  /** Says plainly that nothing loaded, rather than letting a blank or placeholder page imply this is the real content. */
  @Input() message = 'We could not load this from the server just now, so there is nothing to show. This is not the page’s real content - please try again in a moment.';
  @Input() icon = 'bi-cloud-slash';
  @Input() retryable = true;
  /** Inline inside a section that has other content, rather than standing in for a whole page. */
  @Input() compact = false;
  @Output() retry = new EventEmitter<void>();
}
