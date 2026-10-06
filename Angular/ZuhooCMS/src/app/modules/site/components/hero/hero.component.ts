import { SecureFilePipe } from '../../../../shared/pipes/secure-file.pipe';
import { ChangeDetectorRef, Component, Input, OnInit, OnDestroy, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { SiteSettings } from '../../models/site.model';
import { SiteService } from '../../services/site.service';
import { monogramOf } from '../../utils/monogram';

@Component({
  selector: 'app-site-hero',
  standalone: true,
  imports: [SecureFilePipe, RouterLink],
  template: `
    <section class="site-hero">
      <div class="container">
        <div class="row align-items-center g-5">
          <div class="col-lg-6">
            <h1 class="hero-heading mb-3">{{ settings?.heroHeading || 'Welcome' }}</h1>
            <p class="hero-sub mb-4">{{ settings?.heroSubheading }}</p>
            <div class="d-flex align-items-center gap-4 flex-wrap">
              <a [routerLink]="basePath + '/request-service'" class="btn btn-primary px-4 py-2"
                 style="border-radius: var(--site-btn-radius)">
                Request a service
              </a>
              <a [routerLink]="basePath + '/about'" class="hero-link">
                About {{ settings?.companyName || 'us' }}
              </a>
            </div>
            @if (settings?.phone) {
              <p class="hero-meta mt-4 mb-0">
                Or call <a [href]="'tel:' + settings!.phone">{{ settings!.phone }}</a>
              </p>
            }
          </div>
          <div class="col-lg-6">
            @if (settings?.heroImages?.length) {
              <div class="hero-frame">
                @for (img of settings!.heroImages; track img; let i = $index) {
                  <img [src]="img | secureFile" [class.active]="i === currentSlide"
                       class="hero-img" [alt]="settings!.companyName">
                }
              </div>
            } @else if (settings?.heroImageUrl) {
              <div class="hero-frame">
                <img [src]="settings!.heroImageUrl | secureFile" class="hero-img active" [alt]="settings!.companyName">
              </div>
            } @else {
              <div class="hero-frame hero-frame-empty">
                <span class="hero-monogram">{{ monogram }}</span>
              </div>
            }
          </div>
        </div>
      </div>
    </section>
  `,
  styles: [`
    /* Tokens, not ".theme-dark .hero-sub" rules: that selector is scoped to this component, while
       .theme-dark sits on the layout's wrapper, so it never matched and a dark tenant kept the light-mode
       values. Two dark triggers, because two theme systems reach this hero: the tenant's own site theme
       (.theme-dark, set by ThemeDirective on the layout wrapper) and the app's data-theme, which
       /portal/{slug} is not exempt from in ThemeService.LIGHT_ONLY_ROUTES. */
    :host {
      --ink-muted: #5c6570;
      --ink-subtle: #77808c;
      --meta-underline: rgba(0, 0, 0, 0.2);
    }
    :host-context(.theme-dark),
    :host-context([data-theme='dark']) {
      --ink-muted: rgba(255, 255, 255, 0.7);
      --ink-subtle: rgba(255, 255, 255, 0.6);
      --meta-underline: rgba(255, 255, 255, 0.28);
    }

    /* Top padding clears the fixed-top navbar; height follows the content, since a full 100vh pushed everything below out of sight on laptops. */
    .site-hero { padding: 132px 0 72px; }

    .hero-heading { font-size: clamp(2rem, 4.2vw, 3rem); font-weight: 600; line-height: 1.12; letter-spacing: -0.02em; max-width: 15ch; }
    .hero-sub { font-size: 1.075rem; line-height: 1.6; color: var(--ink-muted); max-width: 46ch; }

    /* Brand as ink on the page: 2.51:1 on a dark tenant. The underline is already currentColor, so it
       follows the ink without a second declaration. */
    .hero-link { color: var(--site-primary-ink); text-decoration: none; font-weight: 500; border-bottom: 1px solid currentColor; padding-bottom: 2px; }
    .hero-link:hover { opacity: 0.7; }

    .hero-meta { font-size: 0.9rem; color: var(--ink-subtle); }
    /* The underline was a fixed rgba(0,0,0,0.2), i.e. invisible on a dark surface, so the phone number
       stopped reading as a link the moment the dark rules above started applying. */
    .hero-meta a { color: inherit; text-decoration: none; border-bottom: 1px solid var(--meta-underline); }

    /* Slides are stacked absolutely inside one fixed frame: in normal flow every extra hero image added its own height to the page. */
    .hero-frame { position: relative; width: 100%; aspect-ratio: 4 / 3; border-radius: var(--site-radius); overflow: hidden; background: rgba(var(--site-primary-rgb), 0.05); }
    .hero-img { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; opacity: 0; transition: opacity 0.7s ease; }
    .hero-img.active { opacity: 1; }

    /* With no image, the frame drops 4:3 so an empty hero isn't half a screen of tint. */
    .hero-frame-empty { aspect-ratio: auto; height: clamp(200px, 26vw, 320px); display: flex; align-items: center; justify-content: center; border: 1px solid rgba(var(--site-primary-rgb), 0.18); }
    /* The initials shown when a tenant has uploaded no hero image. The frame behind them is the brand at
       5% over the page, so on a dark tenant this was #6D28D9 over #141833 at 0.55 opacity: 1.54:1. The
       frame tint is the tenant's and stays; only the lettering moves to the ink. */
    .hero-monogram { font-size: clamp(3rem, 8vw, 5rem); font-weight: 600; letter-spacing: 0.06em; color: var(--site-primary-ink); opacity: 0.55; }

    .btn-primary { background: var(--site-primary); border-color: var(--site-primary); }
    .btn-primary:hover { background: var(--site-secondary); border-color: var(--site-secondary); }

    @media (max-width: 991.98px) {
      .site-hero { padding: 108px 0 56px; }
      .hero-heading { max-width: none; }
    }
  `]
})
export class SiteHeroComponent implements OnInit, OnDestroy {
  @Input() settings: SiteSettings | null = null;
  currentSlide = 0;
  private interval: any;

  private siteService = inject(SiteService);
  private cdr = inject(ChangeDetectorRef);
  basePath = this.siteService.getBasePath();

  // Initials stand in for a missing hero image.
  get monogram(): string {
    return monogramOf(this.settings?.companyName);
  }

  ngOnInit(): void {
    if ((this.settings?.heroImages?.length || 0) > 1) {
      this.interval = setInterval(() => {
        this.currentSlide = (this.currentSlide + 1) % (this.settings!.heroImages.length);
        // Zoneless: a timer tick schedules no change detection of its own, so the slide never advanced.
        this.cdr.markForCheck();
      }, 6000);
    }
  }

  ngOnDestroy(): void {
    if (this.interval) clearInterval(this.interval);
  }
}
