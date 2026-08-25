import { Component, OnInit, ChangeDetectionStrategy, ChangeDetectorRef, inject } from '@angular/core';
import { SiteService } from '../../services/site.service';
import { SiteSettings, TeamMember } from '../../models/site.model';
import { DEFAULT_SITE } from '../../services/default-site.config';
import { BreadcrumbComponent } from '../../components/breadcrumb/breadcrumb.component';
import { TeamCardComponent } from '../../components/team-card/team-card.component';

@Component({
  selector: 'app-site-team',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [BreadcrumbComponent, TeamCardComponent],
  template: `
    <div class="pt-5" style="margin-top: 72px">
      <div class="container">
        <app-breadcrumb [items]="[{ label: 'Team' }]"></app-breadcrumb>
      </div>
    </div>

    <section class="band">
      <div class="container">
        <h1 class="page-title">The team</h1>
        <p class="page-lede">The people you will be dealing with at {{ settings?.companyName || 'our company' }}.</p>

        @if (loading) {
          <p class="loading mt-5 mb-0">Loading…</p>
        } @else if (!members.length) {
          <p class="loading mt-5 mb-0">No one has been added to the team page yet.</p>
        } @else {
          <div class="row g-5 mt-1">
            @for (m of members; track m.id) {
              <div class="col-6 col-lg-3"><app-team-card [member]="m" [showEmail]="true"></app-team-card></div>
            }
          </div>
        }
      </div>
    </section>
  `,
  styles: [`
    :host { --ink-muted: #5c6570; display: block; }
    :host-context(.theme-dark) { --ink-muted: rgba(255, 255, 255, 0.68); }

    .band { padding: 64px 0 76px; }
    .page-title { font-size: clamp(1.9rem, 3.4vw, 2.6rem); font-weight: 600; letter-spacing: -0.02em; margin: 0; }
    .page-lede { margin: 0.75rem 0 0; color: var(--ink-muted); max-width: 52ch; }
    .loading { color: var(--ink-muted); }

    @media (max-width: 767.98px) { .band { padding: 40px 0 56px; } }
  `]
})
export class SiteTeamPage implements OnInit {
  private siteService = inject(SiteService);
  constructor(private cdr: ChangeDetectorRef) {}

  settings: SiteSettings = DEFAULT_SITE;
  members: TeamMember[] = [];
  loading = true;

  ngOnInit(): void {
    this.siteService.getSettings().subscribe(s => {
      this.settings = s;
      this.cdr.markForCheck();
    });
    this.siteService.getTeam().subscribe(t => {
      this.members = t;
      this.loading = false;
      this.cdr.markForCheck();
    });
  }
}
