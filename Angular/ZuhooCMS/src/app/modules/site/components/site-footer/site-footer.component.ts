import { SecureFilePipe } from '../../../../shared/pipes/secure-file.pipe';
import { Component, Input, inject } from '@angular/core';
import { NgClass } from '@angular/common';
import { RouterLink } from '@angular/router';
import { SiteSettings } from '../../models/site.model';
import { SiteService } from '../../services/site.service';
import { monogramOf } from '../../utils/monogram';

@Component({
  selector: 'app-site-footer',
  standalone: true,
  imports: [SecureFilePipe, NgClass, RouterLink],
  template: `
    <footer class="site-footer" [class.footer-dark]="settings?.theme?.footerStyle === 'dark'"
            [class.footer-light]="settings?.theme?.footerStyle !== 'dark'">
      <div class="container py-5">
        <div class="row g-5">
          <div class="col-lg-4 col-md-12">
            <div class="d-flex align-items-center gap-2 mb-3">
              @if (settings?.logoUrl) {
                <img [src]="settings!.logoUrl | secureFile" [alt]="settings!.companyName" height="30" class="brand-logo">
              } @else {
                <span class="brand-mark">{{ monogram }}</span>
              }
              <span class="brand-name">{{ settings?.companyName }}</span>
            </div>
            <p class="tagline mb-3">{{ settings?.tagline }}</p>
            @if (settings?.socialLinks?.length) {
              <div class="d-flex gap-3 social-row">
                @for (link of settings!.socialLinks; track link.platform) {
                  <a [href]="link.url" target="_blank" rel="noopener" [attr.aria-label]="link.platform">
                    <i class="bi" [ngClass]="link.icon || 'bi-link-45deg'"></i>
                  </a>
                }
              </div>
            }
          </div>
          <div class="col-lg-2 col-6">
            <h2 class="col-title">Company</h2>
            <ul class="list-unstyled mb-0">
              <li><a [routerLink]="basePath + '/about'">About</a></li>
              <li><a [routerLink]="basePath + '/services'">Services</a></li>
              <li><a [routerLink]="basePath + '/portfolio'">Portfolio</a></li>
              <li><a [routerLink]="basePath + '/careers'">Careers</a></li>
              <li><a [routerLink]="basePath + '/contact'">Contact</a></li>
            </ul>
          </div>
          <div class="col-lg-2 col-6">
            <h2 class="col-title">Resources</h2>
            <ul class="list-unstyled mb-0">
              <li><a [routerLink]="basePath + '/blog'">Blog</a></li>
              <li><a [routerLink]="basePath + '/pricing'">Pricing</a></li>
              <li><a [routerLink]="basePath + '/faq'">FAQ</a></li>
              <li><a [routerLink]="basePath + '/team'">Team</a></li>
              <li><a [routerLink]="basePath + '/book-consultation'">Book a consultation</a></li>
            </ul>
          </div>
          <div class="col-lg-4 col-md-12">
            <h2 class="col-title">Contact</h2>
            <ul class="list-unstyled contact-list mb-0">
              @if (settings?.address) { <li>{{ settings!.address }}</li> }
              @if (settings?.phone) { <li><a [href]="'tel:' + settings!.phone">{{ settings!.phone }}</a></li> }
              @if (settings?.email) { <li><a [href]="'mailto:' + settings!.email">{{ settings!.email }}</a></li> }
            </ul>
          </div>
        </div>
        <div class="footer-base">
          <small>&copy; {{ settings?.copyright || currentYear + ' All rights reserved.' }}</small>
          <div class="d-flex gap-3">
            <a [routerLink]="basePath + '/privacy'"><small>Privacy</small></a>
            <a [routerLink]="basePath + '/terms'"><small>Terms</small></a>
          </div>
        </div>
      </div>
    </footer>
  `,
  styles: [`
    /*
     * The footer picks its own surface from the tenant's footerStyle setting, independently of whether their
     * site is light or dark, so it is the one place where the wrapper's --site-primary-ink can be wrong in
     * both directions: a dark footer under a light site needs the lifted ink, and a light footer under a dark
     * site needs the raw brand back. Each surface therefore states the token for itself, in the same
     * mechanism and with the same mix as site-layout.component.ts, rather than inheriting a guess.
     */
    .footer-dark {
      background: #0f172a; color: #e2e8f0;
      --footer-rule: rgba(255, 255, 255, 0.14); --footer-muted: rgba(226, 232, 240, 0.7);
      /* Their hue and most of their saturation, lightness from the surface: #6D28D9 becomes #A884E7,
         2.51:1 -> 6.08:1. Without color-mix() support the token is invalid and links fall back to the
         footer's own ink, which is legible too. */
      --site-primary-ink: color-mix(in srgb, var(--site-primary) 55%, #f1f5f9);
    }
    .footer-light {
      background: #f7f8f9; color: #14171a;
      --footer-rule: rgba(20, 23, 26, 0.11); --footer-muted: #5c6570;
      /* A brand colour chosen against white already reads here (6.61:1 for the default), and the lifted
         ink would not - so this surface keeps the tenant's colour exactly, dark site or not. */
      --site-primary-ink: var(--site-primary);
    }

    .brand-mark { width: 30px; height: 30px; border-radius: calc(var(--site-radius) * 0.6); border: 1px solid currentColor; display: flex; align-items: center; justify-content: center; font-size: 0.78rem; font-weight: 600; opacity: 0.85; }
    .brand-logo { border-radius: calc(var(--site-radius) * 0.4); }
    .brand-name { font-weight: 600; font-size: 1.05rem; }
    .tagline { color: var(--footer-muted); max-width: 38ch; margin-bottom: 0; font-size: 0.94rem; line-height: 1.6; }

    /* Plain icons on a row, not the 36px tinted rounded-squares used elsewhere. */
    .social-row a { color: var(--footer-muted); font-size: 1.05rem; text-decoration: none; }
    /* The hover colour is the only thing marking these icons as links, so it reads from the surface's own
       ink token above rather than from the raw brand. */
    .social-row a:hover { color: var(--site-primary-ink, var(--site-primary)); }

    .col-title { font-size: 0.78rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.07em; color: var(--footer-muted); margin: 0 0 1rem; }

    .site-footer a { color: inherit; text-decoration: none; }
    /* Same as .social-row a:hover above. */
    .site-footer a:hover { color: var(--site-primary-ink, var(--site-primary)); }
    .list-unstyled li { margin-bottom: 0.5rem; font-size: 0.94rem; }
    .contact-list li { color: var(--footer-muted); line-height: 1.6; }

    .footer-base { display: flex; flex-wrap: wrap; justify-content: space-between; align-items: center; gap: 1rem; margin-top: 3rem; padding-top: 1.5rem; border-top: 1px solid var(--footer-rule); color: var(--footer-muted); }
  `]
})
export class SiteFooterComponent {
  @Input() settings: SiteSettings | null = null;
  currentYear = new Date().getFullYear();

  private siteService = inject(SiteService);
  basePath = this.siteService.getBasePath();

  get monogram(): string {
    return monogramOf(this.settings?.companyName);
  }
}
