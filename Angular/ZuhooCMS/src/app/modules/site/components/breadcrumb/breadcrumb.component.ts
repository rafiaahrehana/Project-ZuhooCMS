import { Component, Input, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { SiteService } from '../../services/site.service';

@Component({
  selector: 'app-breadcrumb',
  standalone: true,
  imports: [RouterLink],
  template: `
    <nav aria-label="breadcrumb" class="py-3">
      <ol class="breadcrumb mb-0">
        <li class="breadcrumb-item"><a [routerLink]="basePath || '/'" class="text-decoration-none">Home</a></li>
        @for (item of items; track item.label; let last = $last) {
          @if (last) {
            <li class="breadcrumb-item active" aria-current="page">{{ item.label }}</li>
          } @else {
            <li class="breadcrumb-item"><a [routerLink]="basePath + (item.url || '')" class="text-decoration-none">{{ item.label }}</a></li>
          }
        }
      </ol>
    </nav>
  `,
  styles: [`
    .breadcrumb { background: transparent; }
    /* --site-primary-ink is --site-primary itself on a light tenant, and the lifted brand tone on a dark one,
       where the raw brand reads 2.51:1 on #0f172a. See site-layout.component.ts. */
    a { color: var(--site-primary-ink, var(--site-primary)); }

    /* On a dark tenant (.theme-dark on the layout wrapper - this component sets no data-bs-theme, so
       Bootstrap keeps its light-mode breadcrumb variables) the current crumb stayed at
       --bs-breadcrumb-item-active-color, rgba(33,37,41,0.75) on #0f172a = 1.11:1, and the "/" separator
       with it. Set through Bootstrap's own custom properties rather than a colour rule, so there is no
       specificity fight with _breadcrumb.scss. */
    :host-context(.theme-dark) .breadcrumb {
      --bs-breadcrumb-item-active-color: #cbd5e1;      /* 11.9:1 on #0f172a; muted against the wrapper's
                                                          #e2e8f0 body ink the way rgba(...,0.75) is in light */
      --bs-breadcrumb-divider-color: rgba(226, 232, 240, 0.45);  /* 3.8:1 - decorative, not content */
    }
  `]
})
export class BreadcrumbComponent {
  @Input() items: { label: string; url?: string }[] = [];

  private siteService = inject(SiteService);
  basePath = this.siteService.getBasePath();
}
