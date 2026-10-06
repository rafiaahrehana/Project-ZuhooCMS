import { SecureFilePipe } from '../../../../shared/pipes/secure-file.pipe';
import { Component, Input, HostListener, inject } from '@angular/core';
import { RouterLink, RouterLinkActive } from '@angular/router';
import { SiteSettings, NavItem } from '../../models/site.model';
import { SiteService } from '../../services/site.service';
import { monogramOf } from '../../utils/monogram';

@Component({
  selector: 'app-site-navbar',
  standalone: true,
  imports: [SecureFilePipe, RouterLink, RouterLinkActive],
  template: `
    <nav class="navbar navbar-expand-lg fixed-top"
         [class.scrolled]="scrolled"
         [class.navbar-dark]="isDark"
         [class.navbar-light]="!isDark">
      <div class="container">
        <a class="navbar-brand d-flex align-items-center gap-2" [routerLink]="basePath || '/'">
          @if (settings?.logoUrl) {
            <img [src]="settings!.logoUrl | secureFile" [alt]="settings!.companyName" height="32" class="brand-logo">
          } @else {
            <span class="brand-mark">{{ monogram }}</span>
          }
          <!-- No 'Company' fallback: with settings unavailable the page below already says the site is
               unavailable, and naming a company that does not exist contradicts it. Empty, plus the
               monogram's own em-dash placeholder, is what app-site-footer already does. -->
          <span class="brand-name">{{ settings?.companyName }}</span>
        </a>
        <button class="navbar-toggler border-0" type="button" (click)="collapsed = !collapsed"
                [attr.aria-expanded]="!collapsed" aria-label="Toggle navigation">
          <i class="bi" [class.bi-list]="collapsed" [class.bi-x-lg]="!collapsed"
             [style.font-size]="'1.4rem'"></i>
        </button>
        <div class="collapse navbar-collapse" [class.show]="!collapsed">
          <ul class="navbar-nav ms-auto">
            @for (item of nav; track item.id || item.label) {
              @if (item.children?.length) {
                <li class="nav-item dropdown">
                  <a class="nav-link dropdown-toggle" href="javascript:void(0)" role="button" data-bs-toggle="dropdown">
                    {{ item.label }}
                  </a>
                  <ul class="dropdown-menu dropdown-menu-end">
                    @for (child of item.children; track child.id || child.label) {
                      <li>
                        @if (child.external) {
                          <a class="dropdown-item" [href]="child.url" target="_blank">{{ child.label }}</a>
                        } @else {
                          <a class="dropdown-item" [routerLink]="basePath + child.url">{{ child.label }}</a>
                        }
                      </li>
                    }
                  </ul>
                </li>
              } @else {
                <li class="nav-item">
                  @if (item.external) {
                    <a class="nav-link" [href]="item.url" target="_blank">{{ item.label }}</a>
                  } @else {
                    <a class="nav-link" [routerLink]="basePath + item.url"
                       routerLinkActive="active" [routerLinkActiveOptions]="{ exact: true }">{{ item.label }}</a>
                  }
                </li>
              }
            }
            <li class="nav-item">
              <a class="btn btn-brand ms-lg-3 px-3" style="border-radius: var(--site-btn-radius)"
                 [routerLink]="basePath + '/request-service'">
                Request a quote
              </a>
            </li>
          </ul>
        </div>
      </div>
    </nav>
  `,
  styles: [`
    /* Tokens, not a ".theme-dark .navbar.scrolled" rule: that selector is scoped to this component, while
       .theme-dark sits on the layout's wrapper (this navbar's parent), so it never matched and a dark
       tenant got a near-white bar under light text as soon as the page scrolled. Two dark triggers,
       because two theme systems reach this bar: the tenant's own site theme (.theme-dark, set by
       ThemeDirective on the layout wrapper) and the app's data-theme, which /portal/{slug} is not
       exempt from in ThemeService.LIGHT_ONLY_ROUTES. */
    :host {
      --bar-bg: rgba(255, 255, 255, 0.97);
      --bar-rule: rgba(20, 23, 26, 0.1);
    }
    :host-context(.theme-dark),
    :host-context([data-theme='dark']) {
      --bar-bg: rgba(15, 23, 42, 0.97);
      --bar-rule: rgba(255, 255, 255, 0.12);
    }

    .navbar { padding: 0.9rem 0; transition: background-color 0.2s ease, padding 0.2s ease; }
    /* A hairline once the page moves, not a 20px drop shadow. */
    .navbar.scrolled { background: var(--bar-bg) !important; border-bottom: 1px solid var(--bar-rule); padding: 0.6rem 0; }

    /* Initials rather than a generic gradient-filled brand tile, so the mark says which company this is. */
    /* Brand as ink, not as a fill: the mark is an outlined box with the initials inside it, both drawn in
       the tenant's colour on the bar's own surface - on a dark tenant that was #6D28D9 on #0f172a, 2.51:1.
       The border is a longhand so that a browser without color-mix() falls back to currentColor (the bar's
       ink) instead of dropping the whole shorthand and losing the box. */
    .brand-mark { width: 32px; height: 32px; border-radius: calc(var(--site-radius) * 0.6); border: 1px solid; border-color: var(--site-primary-ink); color: var(--site-primary-ink); display: flex; align-items: center; justify-content: center; font-size: 0.82rem; font-weight: 600; letter-spacing: 0.02em; }
    .brand-logo { border-radius: calc(var(--site-radius) * 0.4); }
    .brand-name { font-weight: 600; font-size: 1.05rem; letter-spacing: -0.01em; }

    .nav-link { font-size: 0.95rem; padding-left: 0.9rem !important; padding-right: 0.9rem !important; }
    /* The current-page marker, so it has to be readable: brand as ink on the bar. */
    .nav-link.active { color: var(--site-primary-ink) !important; }

    .dropdown-menu { border: 1px solid rgba(20, 23, 26, 0.1); box-shadow: 0 6px 20px rgba(0, 0, 0, 0.06); border-radius: var(--site-radius); padding: 0.35rem; }
    .dropdown-item { padding: 0.45rem 0.75rem; border-radius: calc(var(--site-radius) * 0.5); font-size: 0.94rem; }
    /* Left on the tenant's own colour: the menu is a light panel even on a dark tenant, because
       .dropdown-menu sets no background and the site never sets data-bs-theme, so Bootstrap keeps its
       light --bs-dropdown-bg. Measured 6.61:1 there - the brand colour is correct and readable. */
    .dropdown-item:hover { background: rgba(var(--site-primary-rgb), 0.08); color: var(--site-primary); }

    .btn-brand { background: var(--site-primary); border: 1px solid var(--site-primary); color: #fff; font-size: 0.94rem; }
    .btn-brand:hover { background: var(--site-secondary); border-color: var(--site-secondary); color: #fff; }

    @media (max-width: 991.98px) {
      .btn-brand { display: inline-block; margin-top: 0.75rem; }
    }
  `]
})
export class SiteNavbarComponent {
  @Input() settings: SiteSettings | null = null;
  @Input() nav: NavItem[] = [];

  private siteService = inject(SiteService);
  basePath = this.siteService.getBasePath();

  collapsed = true;
  scrolled = false;

  get monogram(): string {
    return monogramOf(this.settings?.companyName);
  }

  get isDark(): boolean {
    return this.settings?.theme?.darkMode || false;
  }

  @HostListener('window:scroll')
  onScroll(): void {
    this.scrolled = window.scrollY > 50;
  }
}
