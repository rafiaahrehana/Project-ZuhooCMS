import { Component, OnInit, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { SiteService } from '../../services/site.service';
import { SiteSettings, TeamMember } from '../../models/site.model';
import { DEFAULT_SITE } from '../../services/default-site.config';
import { BreadcrumbComponent } from '../../components/breadcrumb/breadcrumb.component';
import { TeamCardComponent } from '../../components/team-card/team-card.component';

@Component({
  selector: 'app-site-about',
  standalone: true,
  imports: [RouterLink, BreadcrumbComponent, TeamCardComponent],
  template: `
    <div class="pt-5" style="margin-top: 72px">
      <div class="container">
        <app-breadcrumb [items]="[{ label: 'About' }]"></app-breadcrumb>
      </div>
    </div>

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
              <img [src]="settings!.heroImageUrl" class="about-img" [alt]="settings?.companyName || ''">
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
  `,
  styles: [`
    :host {
      --rule: rgba(20, 23, 26, 0.11);
      --ink-muted: #5c6570;
      display: block;
    }
    :host-context(.theme-dark) {
      --rule: rgba(255, 255, 255, 0.14);
      --ink-muted: rgba(255, 255, 255, 0.68);
    }

    .band { padding: 64px 0 76px; }
    .band + .band { border-top: 1px solid var(--rule); }
    .band-muted { background: #f7f8f9; }
    .theme-dark .band-muted { background: rgba(255, 255, 255, 0.03); }

    .page-title { font-size: clamp(1.9rem, 3.4vw, 2.6rem); font-weight: 600; letter-spacing: -0.02em; margin: 0; }
    .sec-title { font-size: clamp(1.5rem, 2.4vw, 1.95rem); font-weight: 600; letter-spacing: -0.015em; margin: 0; }
    .sec-head { display: flex; align-items: baseline; justify-content: space-between; gap: 1.5rem; flex-wrap: wrap; }
    .sec-link { color: var(--site-primary); text-decoration: none; font-weight: 500; font-size: 0.95rem; white-space: nowrap; }
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
  basePath = this.siteService.getBasePath();

  settings: SiteSettings = DEFAULT_SITE;
  team: TeamMember[] = [];

  ngOnInit(): void {
    this.siteService.getSettings().subscribe(s => this.settings = s);
    this.siteService.getTeam().subscribe(t => this.team = t);
  }
}
