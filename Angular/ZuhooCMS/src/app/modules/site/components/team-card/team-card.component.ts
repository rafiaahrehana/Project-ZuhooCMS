import { Component, Input } from '@angular/core';
import { TeamMember } from '../../models/site.model';

// The about page and the team page were carrying two near-identical copies of
// this markup, which is how they drifted apart (100px vs 120px avatars, one
// showing the email and the other not). One card, one look.
@Component({
  selector: 'app-team-card',
  standalone: true,
  template: `
    <div class="member h-100">
      @if (member.photoUrl) {
        <img [src]="member.photoUrl" [alt]="member.name" class="portrait">
      } @else {
        <div class="portrait portrait-empty">{{ member.name.charAt(0) }}</div>
      }
      <h3 class="member-name">{{ member.name }}</h3>
      <p class="member-role">{{ member.role }}</p>
      @if (member.bio) {
        <p class="member-bio">{{ member.bio }}</p>
      }
      @if (showEmail && member.email) {
        <a [href]="'mailto:' + member.email" class="member-email">{{ member.email }}</a>
      }
    </div>
  `,
  styles: [`
    /* Left-aligned with a square portrait, rather than a centred circle on a
       shadowed card — the gradient-filled initials were the giveaway. */
    .member { display: flex; flex-direction: column; }
    .portrait { width: 100%; aspect-ratio: 1; object-fit: cover; border-radius: var(--site-radius); margin-bottom: 0.9rem; }
    .portrait-empty { display: flex; align-items: center; justify-content: center; background: rgba(var(--site-primary-rgb), 0.08); color: var(--site-primary); font-size: 2.25rem; font-weight: 600; }

    .member-name { font-size: 1.02rem; font-weight: 600; margin: 0 0 0.15rem; }
    .member-role { font-size: 0.88rem; color: var(--site-primary); margin: 0 0 0.6rem; }
    .member-bio { font-size: 0.92rem; line-height: 1.6; color: #5c6570; margin: 0; }
    .member-email { display: inline-block; margin-top: 0.75rem; font-size: 0.86rem; color: #5c6570; text-decoration: none; border-bottom: 1px solid rgba(20, 23, 26, 0.2); }
    .member-email:hover { color: var(--site-primary); border-color: currentColor; }

    .theme-dark .member-bio, .theme-dark .member-email { color: rgba(255, 255, 255, 0.68); }
  `]
})
export class TeamCardComponent {
  @Input({ required: true }) member!: TeamMember;
  @Input() showEmail = false;
}
