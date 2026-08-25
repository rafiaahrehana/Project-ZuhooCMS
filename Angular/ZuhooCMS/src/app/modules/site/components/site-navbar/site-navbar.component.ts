import { Component, Input, HostListener, inject } from '@angular/core';
import { RouterLink, RouterLinkActive } from '@angular/router';
import { SiteSettings, NavItem } from '../../models/site.model';
import { SiteService } from '../../services/site.service';
import { monogramOf } from '../../utils/monogram';

@Component({
  selector: 'app-site-navbar',
  standalone: true,
  imports: [RouterLink, RouterLinkActive],
  template: `
    <nav class="navbar navbar-expand-lg fixed-top"
         [class.scrolled]="scrolled"
         [class.navbar-dark]="isDark"
         [class.navbar-light]="!isDark">
      <div class="container">
        <a class="navbar-brand d-flex align-items-center gap-2" [routerLink]="basePath || '/'">
          @if (settings?.logoUrl) {
            <img [src]="settings!.logoUrl" [alt]="settings!.companyName" height="32" class="brand-logo">
          } @else {
            <span class="brand-mark">{{ monogram }}</span>
          }
          <span class="brand-name">{{ settings?.companyName || 'Company' }}</span>
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
    .navbar { padding: 0.9rem 0; transition: background-color 0.2s ease, padding 0.2s ease; }
    /* A hairline once the page moves, not a 20px drop shadow. */
    .navbar.scrolled { background: rgba(255, 255, 255, 0.97) !important; border-bottom: 1px solid rgba(20, 23, 26, 0.1); padding: 0.6rem 0; }
    .theme-dark .navbar.scrolled { background: rgba(15, 23, 42, 0.97) !important; border-bottom-color: rgba(255, 255, 255, 0.12); }

    /* The old brand tile was a gradient-filled square holding bi-grid-3x3-gap —
       the default "startup logo" of every landing page template. Initials at
       least say which company this is. */
    .brand-mark { width: 32px; height: 32px; border-radius: calc(var(--site-radius) * 0.6); border: 1px solid var(--site-primary); color: var(--site-primary); display: flex; align-items: center; justify-content: center; font-size: 0.82rem; font-weight: 600; letter-spacing: 0.02em; }
    .brand-logo { border-radius: calc(var(--site-radius) * 0.4); }
    .brand-name { font-weight: 600; font-size: 1.05rem; letter-spacing: -0.01em; }

    .nav-link { font-size: 0.95rem; padding-left: 0.9rem !important; padding-right: 0.9rem !important; }
    .nav-link.active { color: var(--site-primary) !important; }

    .dropdown-menu { border: 1px solid rgba(20, 23, 26, 0.1); box-shadow: 0 6px 20px rgba(0, 0, 0, 0.06); border-radius: var(--site-radius); padding: 0.35rem; }
    .dropdown-item { padding: 0.45rem 0.75rem; border-radius: calc(var(--site-radius) * 0.5); font-size: 0.94rem; }
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
