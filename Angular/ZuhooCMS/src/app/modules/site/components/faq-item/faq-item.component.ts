import { Component, Input } from '@angular/core';

@Component({
  selector: 'app-faq-item',
  standalone: true,
  template: `
    <div class="accordion-item">
      <h3 class="accordion-header">
        <button class="accordion-button collapsed" [attr.data-bs-toggle]="'collapse'"
                [attr.data-bs-target]="'#faq' + faq.id" type="button">
          {{ faq.question }}
        </button>
      </h3>
      <div [id]="'faq' + faq.id" class="accordion-collapse collapse" data-bs-parent="#faqAccordion">
        <div class="accordion-body">{{ faq.answer }}</div>
      </div>
    </div>
  `,
  styles: [`
    /* Tokens, not ".theme-dark .accordion-item" rules: that selector is scoped to this component, while
       .theme-dark sits on the layout's wrapper, so it never matched and a dark tenant kept the light-mode
       values. Two dark triggers, because two theme systems reach this item: the tenant's own site theme
       (.theme-dark, set by ThemeDirective on the layout wrapper) and the app's data-theme, which
       /portal/{slug} is not exempt from in ThemeService.LIGHT_ONLY_ROUTES. */
    :host {
      --rule: rgba(20, 23, 26, 0.11);
      --ink-muted: #5c6570;
    }
    :host-context(.theme-dark),
    :host-context([data-theme='dark']) {
      --rule: rgba(255, 255, 255, 0.14);
      --ink-muted: rgba(255, 255, 255, 0.68);
    }

    /* Ruled rows rather than a stack of grey rounded slabs. */
    .accordion-item { background: transparent; border: 0; border-top: 1px solid var(--rule); border-radius: 0; }

    .accordion-button { background: transparent; box-shadow: none; padding: 1.15rem 0; font-size: 1.02rem; font-weight: 500; }
    .accordion-button:not(.collapsed) { background: transparent; color: var(--site-primary); box-shadow: none; }
    .accordion-button:focus { box-shadow: none; }
    .accordion-button::after { background-image: url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' fill='%23334155'%3e%3cpath d='M1.646 4.646a.5.5 0 0 1 .708 0L8 10.293l5.646-5.647a.5.5 0 0 1 .708.708l-6 6a.5.5 0 0 1-.708 0l-6-6a.5.5 0 0 1 0-.708z'/%3e%3c/svg%3e"); }
    /* The chevron is a fixed slate fill baked into a data URI, and this rule outranks Bootstrap's own
       --bs-accordion-btn-icon, so it stayed near-invisible (about 1.5:1) on either dark surface. A var()
       cannot be interpolated into a url() string, so the dark icon is a second whole declaration. */
    :host-context(.theme-dark) .accordion-button::after,
    :host-context([data-theme='dark']) .accordion-button::after { background-image: url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' fill='%23cbd5e1'%3e%3cpath d='M1.646 4.646a.5.5 0 0 1 .708 0L8 10.293l5.646-5.647a.5.5 0 0 1 .708.708l-6 6a.5.5 0 0 1-.708 0l-6-6a.5.5 0 0 1 0-.708z'/%3e%3c/svg%3e"); }
    /* Only the tenant's own dark theme: it sets no data-bs-theme, so Bootstrap keeps its light
       --bs-accordion-btn-color and the question read at 1.42:1 on #0f172a, under an answer that the
       rules above had just made legible. The app's dark mode does set data-bs-theme and needs nothing. */
    :host-context(.theme-dark) .accordion-button { color: #e2e8f0; }
    /* ...but that rule also swallowed the expanded question's brand colour, which is why the open FAQ row
       never showed the tenant's colour on a dark tenant. No !important is involved: Angular's emulated
       encapsulation adds an attribute to every selector, so .accordion-button:not(.collapsed) above
       compiles to (0,3,0) while the :host-context rule compiles to (0,4,0) and simply outranks it. This
       restores the brand on the open row, as ink rather than the raw colour, at (0,5,0).
       Dark only - on a light tenant the rule above never matches and the brand already showed. */
    :host-context(.theme-dark) .accordion-button:not(.collapsed) { color: var(--site-primary-ink); }

    .accordion-body { padding: 0 0 1.25rem; color: var(--ink-muted); line-height: 1.66; max-width: 62ch; }
  `]
})
export class FaqItemComponent {
  @Input({ required: true }) faq!: { id: number; question: string; answer: string };
}
