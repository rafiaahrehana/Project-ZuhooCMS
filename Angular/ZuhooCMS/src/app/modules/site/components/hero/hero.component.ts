import { Component, Input, OnInit, OnDestroy, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { SiteSettings } from '../../models/site.model';
import { SiteService } from '../../services/site.service';
import { monogramOf } from '../../utils/monogram';

@Component({
  selector: 'app-site-hero',
  standalone: true,
  imports: [RouterLink],
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
                  <img [src]="img" [class.active]="i === currentSlide"
                       class="hero-img" [alt]="settings!.companyName">
                }
              </div>
            } @else if (settings?.heroImageUrl) {
              <div class="hero-frame">
                <img [src]="settings!.heroImageUrl" class="hero-img active" [alt]="settings!.companyName">
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
    /* The navbar is fixed-top, so the first screenful has to clear it. The old
       hero also claimed a full 100vh, which pushed everything below it out of
       sight on laptops for no reason — height now follows the content. */
    .site-hero { padding: 132px 0 72px; }

    .hero-heading { font-size: clamp(2rem, 4.2vw, 3rem); font-weight: 600; line-height: 1.12; letter-spacing: -0.02em; max-width: 15ch; }
    .hero-sub { font-size: 1.075rem; line-height: 1.6; color: #5c6570; max-width: 46ch; }
    .theme-dark .hero-sub { color: rgba(255,255,255,0.7); }

    .hero-link { color: var(--site-primary); text-decoration: none; font-weight: 500; border-bottom: 1px solid currentColor; padding-bottom: 2px; }
    .hero-link:hover { opacity: 0.7; }

    .hero-meta { font-size: 0.9rem; color: #77808c; }
    .hero-meta a { color: inherit; text-decoration: none; border-bottom: 1px solid rgba(0,0,0,0.2); }

    /* One fixed frame with the slides stacked inside it. Previously the slides
       were laid out in normal flow and merely faded, so every extra hero image
       added its own height to the page. */
    .hero-frame { position: relative; width: 100%; aspect-ratio: 4 / 3; border-radius: var(--site-radius); overflow: hidden; background: rgba(var(--site-primary-rgb), 0.05); }
    .hero-img { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; opacity: 0; transition: opacity 0.7s ease; }
    .hero-img.active { opacity: 1; }

    /* With no image to hold, the frame drops the 4:3 shape — a company that
       hasn't uploaded one shouldn't get half a screen of empty tint. */
    .hero-frame-empty { aspect-ratio: auto; height: clamp(200px, 26vw, 320px); display: flex; align-items: center; justify-content: center; border: 1px solid rgba(var(--site-primary-rgb), 0.18); }
    .hero-monogram { font-size: clamp(3rem, 8vw, 5rem); font-weight: 600; letter-spacing: 0.06em; color: var(--site-primary); opacity: 0.55; }

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
  basePath = this.siteService.getBasePath();

  // Initials stand in for a missing hero image.
  get monogram(): string {
    return monogramOf(this.settings?.companyName);
  }

  ngOnInit(): void {
    if ((this.settings?.heroImages?.length || 0) > 1) {
      this.interval = setInterval(() => {
        this.currentSlide = (this.currentSlide + 1) % (this.settings!.heroImages.length);
      }, 6000);
    }
  }

  ngOnDestroy(): void {
    if (this.interval) clearInterval(this.interval);
  }
}
