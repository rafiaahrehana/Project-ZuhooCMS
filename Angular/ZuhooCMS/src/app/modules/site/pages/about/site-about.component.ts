import { SecureFilePipe } from '../../../../shared/pipes/secure-file.pipe';
import { Component, OnInit, ChangeDetectorRef, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { SiteService } from '../../services/site.service';
import { SiteSettings, TeamMember } from '../../models/site.model';
import { SiteNoticeComponent } from '../../components/notice/site-notice.component';
import { BreadcrumbComponent } from '../../components/breadcrumb/breadcrumb.component';
import { TeamCardComponent } from '../../components/team-card/team-card.component';

@Component({
  selector: 'app-site-about',
  standalone: true,
  imports: [SecureFilePipe, RouterLink, BreadcrumbComponent, TeamCardComponent, SiteNoticeComponent],
  template: `
    <div class="pt-5" style="margin-top: 72px">
      <div class="container">
        <app-breadcrumb [items]="[{ label: 'About' }]"></app-breadcrumb>
      </div>
    </div>

    @if (failed) {
      <app-site-notice (retry)="load()"></app-site-notice>
    } @else {
    <section class="band">
      <div class="container">
        <div class="row g-5">
          <div class="col-lg-7">
            <h1 class="page-title">About {{ settings?.companyName }}</h1>
            <p class="body-copy mt-3">{{ settings?.aboutText }}</p>
            <dl class="mission-list mt-4 mb-0">
              @if (settings?.mission) {
                <div class="mission-item">
                  <dt>Mission</dt>
                  <dd>{{ settings!.mission }}</dd>
                </div>
              }
              @if (settings?.vision) {
                <div class="mission-item">
                  <dt>Vision</dt>
                  <dd>{{ settings!.vision }}</dd>
                </div>
              }
            </dl>
          </div>
          <div class="col-lg-5">
            @if (settings?.heroImageUrl) {
              <img [src]="settings!.heroImageUrl | secureFile" class="about-img" [alt]="settings?.companyName || ''">
            }
          </div>
        </div>
      </div>
    </section>

    @if (team.length) {
      <section class="band band-muted">
        <div class="container">
          <div class="sec-head">
            <h2 class="sec-title">The team</h2>
            <a [routerLink]="basePath + '/team'" class="sec-link">Everyone at {{ settings?.companyName }}</a>
          </div>
          <div class="row g-4 mt-1">
            @for (m of team.slice(0, 4); track m.id) {
              <div class="col-6 col-lg-3"><app-team-card [member]="m"></app-team-card></div>
            }
          </div>
        </div>
      </section>
    }
    }
  `,
  styles: [`
    :host {
      --rule: rgba(20, 23, 26, 0.11);
      --ink-muted: #5c6570;
      --band-muted-bg: #f7f8f9;
      display: block;
    }
    /* Two dark triggers, because two theme systems reach this page: the tenant's own site theme
       (.theme-dark, set by ThemeDirective on the layout wrapper) and the app's data-theme, which
       /portal/{slug} is not exempt from in ThemeService.LIGHT_ONLY_ROUTES. */
    :host-context(.theme-dark),
    :host-context([data-theme='dark']) {
      --rule: rgba(255, 255, 255, 0.14);
      --ink-muted: rgba(255, 255, 255, 0.68);
      --band-muted-bg: rgba(255, 255, 255, 0.03);
    }

    .band { padding: 64px 0 76px; }
    .band + .band { border-top: 1px solid var(--rule); }
    /* A token, not a ".theme-dark .band-muted" rule: that selector is scoped to this component, while
       .theme-dark sits on the layout's wrapper, so it never matched and the band stayed near-white
       under light ink at 1.28:1. */
    .band-muted { background: var(--band-muted-bg); }

    .page-title { font-size: clamp(1.9rem, 3.4vw, 2.6rem); font-weight: 600; letter-spacing: -0.02em; margin: 0; }
    .sec-title { font-size: clamp(1.5rem, 2.4vw, 1.95rem); font-weight: 600; letter-spacing: -0.015em; margin: 0; }
    .sec-head { display: flex; align-items: baseline; justify-content: space-between; gap: 1.5rem; flex-wrap: wrap; }
    /* Same section link as the home page: brand as ink on the page, 2.34:1 on the muted band. */
    .sec-link { color: var(--site-primary-ink); text-decoration: none; font-weight: 500; font-size: 0.95rem; white-space: nowrap; }
    .sec-link:hover { text-decoration: underline; }

    .body-copy { color: var(--ink-muted); line-height: 1.68; max-width: 62ch; font-size: 1.03rem; }

    .mission-list { display: grid; gap: 1rem; }
    .mission-item { display: grid; grid-template-columns: 96px 1fr; gap: 1rem; padding-top: 1rem; border-top: 1px solid var(--rule); }
    .mission-item dt { font-size: 0.82rem; text-transform: uppercase; letter-spacing: 0.06em; color: var(--ink-muted); font-weight: 600; }
    .mission-item dd { margin: 0; color: var(--ink-muted); line-height: 1.6; }

    .about-img { width: 100%; max-height: 420px; object-fit: cover; border-radius: var(--site-radius); }

    @media (max-width: 767.98px) {
      .band { padding: 40px 0 56px; }
      .mission-item { grid-template-columns: 1fr; gap: 0.35rem; }
    }
  `]
})
export class SiteAboutPage implements OnInit {
  private siteService = inject(SiteService);
  constructor(private cdr: ChangeDetectorRef) {}
  basePath = this.siteService.getBasePath();

  /** Null until the tenant's own settings arrive - never a placeholder company. */
  settings: SiteSettings | null = null;
  team: TeamMember[] = [];
  failed = false;

  ngOnInit(): void {
    this.load();
  }

  load(): void {
    this.failed = false;
    this.cdr.markForCheck();
    // Settings carry everything this page is about, so a failure there replaces the page rather than
    // leaving empty headings that read as "this company has nothing to say".
    // Zoneless: each callback runs outside change detection, so it has to ask for a pass itself.
    this.siteService.getSettings().subscribe({
      next: s => { this.settings = s; this.cdr.markForCheck(); },
      error: () => { this.failed = true; this.cdr.markForCheck(); },
    });
    this.siteService.getTeam().subscribe({
      next: t => { this.team = t; this.cdr.markForCheck(); },
      error: () => { this.team = []; this.cdr.markForCheck(); },
    });
  }
}
