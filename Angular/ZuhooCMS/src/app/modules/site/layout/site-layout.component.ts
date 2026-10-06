import { ChangeDetectorRef, Component, OnInit, inject } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { SiteService } from '../services/site.service';
import { ThemeDirective } from '../theme/theme.directive';
import { THEMES } from '../theme/themes';
import { SiteNavbarComponent } from '../components/site-navbar/site-navbar.component';
import { SiteFooterComponent } from '../components/site-footer/site-footer.component';
import { SiteNoticeComponent } from '../components/notice/site-notice.component';
import { NavItem, SiteSettings } from '../models/site.model';

@Component({
  selector: 'app-site-layout',
  standalone: true,
  imports: [RouterOutlet, ThemeDirective, SiteNavbarComponent, SiteFooterComponent, SiteNoticeComponent],
  template: `
    <div class="site-wrapper"
         [appTheme]="settings?.theme || fallbackTheme"
         [primaryOverride]="settings?.primaryColor"
         [secondaryOverride]="settings?.secondaryColor">
      <app-site-navbar [settings]="settings" [nav]="nav"></app-site-navbar>
      <main>
        <!-- Settings carry the company's name, branding and contact details, so a failure here means there is
             no tenant content to show at all: say so once, rather than letting each page render blanks. -->
        @if (settingsFailed) {
          <app-site-notice title="This site is unavailable" (retry)="loadSettings()"></app-site-notice>
        } @else {
          <router-outlet></router-outlet>
        }
      </main>
      <app-site-footer [settings]="settings"></app-site-footer>
    </div>
  `,
  styles: [`
    .site-wrapper {
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      font-family: var(--site-font);
      /* The tenant's brand colour used as TEXT, as opposed to as a fill. On a light page the two are the
         same thing, so this is exactly what the pages used before. */
      --site-primary-ink: var(--site-primary);
    }
    main { flex: 1; }
    /* The wrapper is where ThemeDirective puts .theme-dark, but nothing gave that class a surface, so a
       dark-mode tenant rendered light text on the light page background. */
    .site-wrapper.theme-dark {
      background: #0f172a;
      color: #e2e8f0;
      /* global.scss's h1..h6 and .page-title rules read --bos-heading-ink with a --bos-text fallback, and at
         (0,0,1)/(0,1,0) they beat the inherited colour above - so every heading on a dark tenant site was
         #111827 on #0f172a, 1.01:1. The token is defined here, next to the surface it belongs to, so the
         three values cannot drift apart. It is a single-consumer token: nothing else reads it.
         --bos-text itself is deliberately NOT redefined, because inside .site-wrapper it is also the ink of
         .form-control/.form-select and .form-label, which sit on a hard-coded white field. */
      --bos-heading-ink: #e2e8f0;
      /* Each page heading puts one word in the tenant's brand colour, which is picked against a white page:
         the default #6D28D9 reads 2.51:1 on #0f172a, so that word dropped out of its own heading. The
         tenant's colour is NOT changed - --site-primary still fills every button, pill and bar exactly as
         they chose. Only the brand-as-text token is lifted, by mixing their colour with the page's light ink:
         the hue and most of the saturation are still theirs, the lightness comes from the page. The default
         purple becomes #A884E7, 6.05:1. A browser without color-mix() makes this token invalid where it is
         used, so the word simply falls back to the heading's own ink - legible either way. */
      --site-primary-ink: color-mix(in srgb, var(--site-primary) 55%, #f1f5f9);
    }
    /* The one light surface inside a dark tenant: .card keeps var(--bos-bg-card) (white unless the browser is
       also in app dark mode), and contact / book-consultation / request-service / track-request each put a
       confirmation heading inside one. Those headings keep the light-surface ink. */
    .site-wrapper.theme-dark ::ng-deep .card { --bos-heading-ink: var(--bos-text); }
  `]
})
export class SiteLayoutComponent implements OnInit {
  private siteService = inject(SiteService);
  private cdr = inject(ChangeDetectorRef);

  /** Null until the tenant's real settings arrive. It is never a placeholder company: see SiteService. */
  settings: SiteSettings | null = null;
  nav: NavItem[] = [];
  settingsFailed = false;

  /** Colours, radii and fonts only, so the navbar and the failure notice are styled before/without settings. Carries no company content. */
  readonly fallbackTheme = THEMES['purple-enterprise'];

  ngOnInit(): void {
    this.loadSettings();
  }

  loadSettings(): void {
    this.settingsFailed = false;
    this.cdr.markForCheck();
    this.siteService.getSettings().subscribe({
      next: s => { this.settings = s; this.cdr.markForCheck(); },
      error: () => { this.settings = null; this.settingsFailed = true; this.cdr.markForCheck(); },
    });
    // The nav is decoration: a failure leaves the bar with just the brand and the quote button, which is honest.
    this.siteService.getNav().subscribe({
      next: n => { this.nav = n; this.cdr.markForCheck(); },
      error: () => { this.nav = []; this.cdr.markForCheck(); },
    });
  }
}
