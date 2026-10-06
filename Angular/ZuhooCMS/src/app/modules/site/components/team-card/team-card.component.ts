import { SecureFilePipe } from '../../../../shared/pipes/secure-file.pipe';
import { Component, Input } from '@angular/core';
import { TeamMember } from '../../models/site.model';

// Shared by the about and team pages, which previously kept near-identical copies that drifted apart (100px vs 120px avatars, email shown or not).
@Component({
  selector: 'app-team-card',
  standalone: true,
  imports: [SecureFilePipe],
  template: `
    <div class="member h-100">
      @if (member.photoUrl) {
        <img [src]="member.photoUrl | secureFile" [alt]="member.name" class="portrait">
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
    /* Tokens, not ".theme-dark .member-bio" rules: that selector is scoped to this component, while
       .theme-dark sits on the layout's wrapper, so it never matched and a dark tenant kept the light-mode
       values. Two dark triggers, because two theme systems reach this card: the tenant's own site theme
       (.theme-dark, set by ThemeDirective on the layout wrapper) and the app's data-theme, which
       /portal/{slug} is not exempt from in ThemeService.LIGHT_ONLY_ROUTES. */
    :host {
      --ink-muted: #5c6570;
      --email-underline: rgba(20, 23, 26, 0.2);
    }
    :host-context(.theme-dark),
    :host-context([data-theme='dark']) {
      --ink-muted: rgba(255, 255, 255, 0.68);
      --email-underline: rgba(255, 255, 255, 0.28);
    }

    /* Left-aligned with a square portrait, not a centred circle on a shadowed card. */
    .member { display: flex; flex-direction: column; }
    .portrait { width: 100%; aspect-ratio: 1; object-fit: cover; border-radius: var(--site-radius); margin-bottom: 0.9rem; }
    /* The initial shown when a member has no photo. The tile is the brand at 8%, which over #0f172a
       resolves to #171838, so the letter was #6D28D9 on #171838: 2.41:1. The tile keeps the tenant's
       tint; only the letter moves to the ink. */
    .portrait-empty { display: flex; align-items: center; justify-content: center; background: rgba(var(--site-primary-rgb), 0.08); color: var(--site-primary-ink); font-size: 2.25rem; font-weight: 600; }

    .member-name { font-size: 1.02rem; font-weight: 600; margin: 0 0 0.15rem; }
    .member-role { font-size: 0.88rem; color: var(--site-primary-ink); margin: 0 0 0.6rem; }
    .member-bio { font-size: 0.92rem; line-height: 1.6; color: var(--ink-muted); margin: 0; }
    /* The underline was a fixed rgba(20, 23, 26, 0.2), i.e. invisible on a dark surface, so the address
       stopped reading as a link the moment the dark rule above started applying. */
    .member-email { display: inline-block; margin-top: 0.75rem; font-size: 0.86rem; color: var(--ink-muted); text-decoration: none; border-bottom: 1px solid var(--email-underline); }
    .member-email:hover { color: var(--site-primary-ink); border-color: currentColor; }
  `]
})
export class TeamCardComponent {
  @Input({ required: true }) member!: TeamMember;
  @Input() showEmail = false;
}
