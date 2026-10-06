import { SecureFilePipe } from '../../../../shared/pipes/secure-file.pipe';
import { Component, Input } from '@angular/core';
import { BlogPost } from '../../models/site.model';

@Component({
  selector: 'app-blog-card',
  standalone: true,
  imports: [SecureFilePipe],
  template: `
    <article class="post h-100">
      @if (post.coverImageUrl) {
        <img [src]="post.coverImageUrl | secureFile" class="post-img" [alt]="post.title">
      }
      <div class="post-body">
        @if (post.category) { <span class="post-cat">{{ post.category }}</span> }
        <h3 class="post-title">{{ post.title }}</h3>
        <p class="post-excerpt">{{ post.excerpt }}</p>
        <p class="post-meta mb-0">
          {{ post.author }}@if (post.readMinutes) { <span> &middot; {{ post.readMinutes }} min read</span> }
        </p>
      </div>
      <a [href]="'/blog/' + post.slug" class="stretched-link"><span class="visually-hidden">Read {{ post.title }}</span></a>
    </article>
  `,
  styles: [`
    /* Tokens, not ".theme-dark .post" rules: that selector is scoped to this component, while .theme-dark
       sits on the layout's wrapper, so it never matched and a dark tenant kept the light-mode values.
       Two dark triggers, because two theme systems reach this card: the tenant's own site theme
       (.theme-dark, set by ThemeDirective on the layout wrapper) and the app's data-theme, which
       /portal/{slug} is not exempt from in ThemeService.LIGHT_ONLY_ROUTES. */
    :host {
      --rule: rgba(20, 23, 26, 0.11);
      --ink-muted: #5c6570;
      --ink-subtle: #77808c;
    }
    :host-context(.theme-dark),
    :host-context([data-theme='dark']) {
      --rule: rgba(255, 255, 255, 0.14);
      --ink-muted: rgba(255, 255, 255, 0.68);
      --ink-subtle: rgba(255, 255, 255, 0.6);
    }

    .post { position: relative; display: flex; flex-direction: column; border: 1px solid var(--rule); border-radius: var(--site-radius); overflow: hidden; transition: border-color 0.2s ease; }
    /* Same as the service card: the hover border is the only affordance, so it has to be visible. */
    .post:hover { border-color: var(--site-primary-ink); }

    .post-img { width: 100%; height: 190px; object-fit: cover; }
    .post-body { padding: 1.25rem; display: flex; flex-direction: column; flex-grow: 1; }
    /* A caption, not a coloured pill over the image, which fought the photograph. */
    .post-cat { font-size: 0.78rem; text-transform: uppercase; letter-spacing: 0.06em; color: var(--ink-subtle); margin-bottom: 0.4rem; }
    .post-title { font-size: 1.05rem; font-weight: 600; margin: 0 0 0.5rem; }
    .post-excerpt { color: var(--ink-muted); font-size: 0.94rem; line-height: 1.6; margin: 0; flex-grow: 1; }
    .post-meta { margin-top: 1rem; font-size: 0.83rem; color: var(--ink-subtle); }
  `]
})
export class BlogCardComponent {
  @Input({ required: true }) post!: BlogPost;
}
