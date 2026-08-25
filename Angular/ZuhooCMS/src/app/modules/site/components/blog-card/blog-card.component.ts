import { Component, Input } from '@angular/core';
import { BlogPost } from '../../models/site.model';

@Component({
  selector: 'app-blog-card',
  standalone: true,
  template: `
    <article class="post h-100">
      @if (post.coverImageUrl) {
        <img [src]="post.coverImageUrl" class="post-img" [alt]="post.title">
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
    .post { position: relative; display: flex; flex-direction: column; border: 1px solid rgba(20, 23, 26, 0.11); border-radius: var(--site-radius); overflow: hidden; transition: border-color 0.2s ease; }
    .post:hover { border-color: var(--site-primary); }
    .theme-dark .post { border-color: rgba(255, 255, 255, 0.14); }

    .post-img { width: 100%; height: 190px; object-fit: cover; }
    .post-body { padding: 1.25rem; display: flex; flex-direction: column; flex-grow: 1; }
    /* The category used to float over the image as a coloured pill. It reads
       just as well as a caption, and stops fighting the photograph. */
    .post-cat { font-size: 0.78rem; text-transform: uppercase; letter-spacing: 0.06em; color: #77808c; margin-bottom: 0.4rem; }
    .post-title { font-size: 1.05rem; font-weight: 600; margin: 0 0 0.5rem; }
    .post-excerpt { color: #5c6570; font-size: 0.94rem; line-height: 1.6; margin: 0; flex-grow: 1; }
    .post-meta { margin-top: 1rem; font-size: 0.83rem; color: #77808c; }
    .theme-dark .post-excerpt { color: rgba(255, 255, 255, 0.68); }
    .theme-dark .post-cat, .theme-dark .post-meta { color: rgba(255, 255, 255, 0.6); }
  `]
})
export class BlogCardComponent {
  @Input({ required: true }) post!: BlogPost;
}
