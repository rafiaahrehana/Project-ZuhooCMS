import { Injectable, signal } from '@angular/core';
import { NavigationEnd, Router } from '@angular/router';
import { filter } from 'rxjs/operators';

export type Theme = 'light' | 'dark';

/** localStorage key. Shared with the pre-paint script in index.html. */
const STORAGE_KEY = 'bos-theme';

/** Always light: the marketing page has ~450 literal hexes, so a token swap breaks it rather than darkening it. */
const LIGHT_ONLY_ROUTES = ['/home'];

/**
 * Writes two <html> attributes: data-theme for the --bos-* palette (styles/_dark.scss) and data-bs-theme for Bootstrap 5.3's dark mode.
 * Bootstrap's own dark palette recolours cards, modals, tables and forms, leaving only our tokens and literal utilities (.bg-white, .text-dark, .table-light).
 * index.html sets both before first paint; without that, dark mode shows a white flash while Angular boots.
 */
@Injectable({ providedIn: 'root' })
export class ThemeService {

  readonly theme = signal<Theme>('light');

  /** True once the user has picked a side; until then we follow the OS. */
  private explicit = false;

  /** What the user actually wants, as opposed to what a light-only route forces. */
  private preferred: Theme = 'light';

  constructor(private router: Router) {
    const stored = this.read();
    this.explicit = stored !== null;
    this.preferred = stored ?? (this.systemPrefersDark() ? 'dark' : 'light');
    this.apply(this.preferred);
    this.watchSystem();
    this.watchRoutes();
  }

  toggle(): void {
    this.set(this.theme() === 'dark' ? 'light' : 'dark');
  }

  /** An explicit choice; from here on the OS setting no longer overrides it. */
  set(theme: Theme): void {
    this.explicit = true;
    this.preferred = theme;
    try { localStorage.setItem(STORAGE_KEY, theme); } catch { /* private mode */ }
    this.applyForRoute(this.router.url);
  }

  /** Forget the choice and follow the OS again. */
  clear(): void {
    this.explicit = false;
    try { localStorage.removeItem(STORAGE_KEY); } catch { /* private mode */ }
    this.preferred = this.systemPrefersDark() ? 'dark' : 'light';
    this.applyForRoute(this.router.url);
  }

  private apply(theme: Theme): void {
    const root = document.documentElement;
    root.setAttribute('data-theme', theme);
    root.setAttribute('data-bs-theme', theme);
    this.theme.set(theme);
  }

  private read(): Theme | null {
    try {
      const v = localStorage.getItem(STORAGE_KEY);
      return v === 'dark' || v === 'light' ? v : null;
    } catch {
      return null;
    }
  }

  private systemPrefersDark(): boolean {
    return typeof matchMedia === 'function'
      && matchMedia('(prefers-color-scheme: dark)').matches;
  }

  /** Follows the OS only while the user has not chosen, so an explicit pick is not flipped at sunset. */
  private watchSystem(): void {
    if (typeof matchMedia !== 'function') return;
    matchMedia('(prefers-color-scheme: dark)').addEventListener('change', e => {
      if (this.explicit) return;
      this.preferred = e.matches ? 'dark' : 'light';
      this.applyForRoute(this.router.url);
    });
  }

  /** Forces light on /home without touching the stored preference, so returning from it does not reset the user to light. */
  private watchRoutes(): void {
    this.applyForRoute(this.router.url);
    this.router.events
      .pipe(filter((e): e is NavigationEnd => e instanceof NavigationEnd))
      .subscribe(e => this.applyForRoute(e.urlAfterRedirects));
  }

  private applyForRoute(url: string): void {
    const lightOnly = LIGHT_ONLY_ROUTES.some(r => url === r || url.startsWith(r + '/') || url.startsWith(r + '?'));
    this.apply(lightOnly ? 'light' : this.preferred);
  }
}
