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
    /* Ruled rows rather than a stack of grey rounded slabs. */
    .accordion-item { background: transparent; border: 0; border-top: 1px solid rgba(20, 23, 26, 0.11); border-radius: 0; }
    .theme-dark .accordion-item { border-color: rgba(255, 255, 255, 0.14); }

    .accordion-button { background: transparent; box-shadow: none; padding: 1.15rem 0; font-size: 1.02rem; font-weight: 500; }
    .accordion-button:not(.collapsed) { background: transparent; color: var(--site-primary); box-shadow: none; }
    .accordion-button:focus { box-shadow: none; }
    .accordion-button::after { background-image: url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' fill='%23334155'%3e%3cpath d='M1.646 4.646a.5.5 0 0 1 .708 0L8 10.293l5.646-5.647a.5.5 0 0 1 .708.708l-6 6a.5.5 0 0 1-.708 0l-6-6a.5.5 0 0 1 0-.708z'/%3e%3c/svg%3e"); }

    .accordion-body { padding: 0 0 1.25rem; color: #5c6570; line-height: 1.66; max-width: 62ch; }
    .theme-dark .accordion-body { color: rgba(255, 255, 255, 0.68); }
  `]
})
export class FaqItemComponent {
  @Input({ required: true }) faq!: { id: number; question: string; answer: string };
}
