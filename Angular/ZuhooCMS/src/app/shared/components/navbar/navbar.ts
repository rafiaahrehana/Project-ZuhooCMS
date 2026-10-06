import { SecureFilePipe } from '../../pipes/secure-file.pipe';
import { ChangeDetectorRef, Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { AuthService } from '../../../core/services/auth.service';
import { ThemeService } from '../../../core/services/theme.service';
import { NotificationBell } from '../notification-bell/notification-bell';

@Component({
  selector: 'app-navbar',
  imports: [SecureFilePipe, CommonModule, FormsModule, NotificationBell, RouterLink],
  templateUrl: './navbar.html',
  styleUrl: './navbar.scss',
})
export class Navbar {
  searchQuery = '';
  breadcrumb: string[] = [];
  isFullscreen = false;

  constructor(
    public auth: AuthService,
    public theme: ThemeService,
    private router: Router,
    private cdr: ChangeDetectorRef,
  ) {
    this.router.events.subscribe(() => this.buildBreadcrumb());
    this.buildBreadcrumb();

    // Esc leaves fullscreen without the button, so the icon must follow the document or it goes stale.
    document.addEventListener('fullscreenchange', () => {
      this.isFullscreen = !!document.fullscreenElement;
      // Zoneless: a raw DOM listener schedules no change detection, so the icon stayed stale anyway.
      this.cdr.markForCheck();
    });

    this.restoreSidebarState();
  }

  /** Reapply the remembered desktop collapse, but never on a narrow viewport. */
  private restoreSidebarState(): void {
    try {
      if (localStorage.getItem('sidebar-collapsed') === 'true' && window.innerWidth >= 992) {
        document.body.classList.add('sidebar-collapsed');
      }
    } catch {
      // Storage unavailable - start expanded.
    }
  }

  /** Second line of the workspace label in the header. */
  get workspaceName(): string {
    if (this.auth.hasRole('CLIENT')) return 'Client Portal';
    if (this.auth.isPlatformUser()) return 'Platform Admin';
    return 'Command Center';
  }

  toggleFullscreen(): void {
    if (!document.fullscreenElement) {
      document.documentElement.requestFullscreen().catch(() => {
        // Rejected outside a user gesture or when embedded with fullscreen disallowed; nothing to do.
      });
    } else {
      document.exitFullscreen();
    }
  }

  private buildBreadcrumb(): void {
    const segments = this.router.url.split('?')[0].split('/').filter(Boolean);
    this.breadcrumb = segments.map((s) =>
      s.replace(/-/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase()),
    );
  }

  /** Wide viewport: collapse the rail in place and remember it. Narrow: slide a drawer over the content, unremembered, since a drawer left open across navigations is in the way. */
  toggleSidebar(): void {
    if (window.innerWidth >= 992) {
      const collapsed = document.body.classList.toggle('sidebar-collapsed');
      try {
        localStorage.setItem('sidebar-collapsed', String(collapsed));
      } catch {
        // Private-mode browsers throw on write; collapsing still works, it just will not survive a reload.
      }
    } else {
      document.body.classList.toggle('sidebar-open');
    }
  }

  goSearch(): void {
    if (this.searchQuery && this.searchQuery.trim().length > 0) {
      this.router.navigate(['/search'], { queryParams: { q: this.searchQuery.trim() } });
      this.searchQuery = '';
    } else {
      this.router.navigate(['/search']);
    }
  }

  goSearchAi(): void {
    if (this.searchQuery && this.searchQuery.trim().length > 0) {
      this.router.navigate(['/search'], { queryParams: { q: this.searchQuery.trim(), ai: 'true' } });
      this.searchQuery = '';
    } else {
      this.router.navigate(['/ai']);
    }
  }

  roleLabel(roles: string[] | undefined | null): string {
    const role = roles?.[0];
    if (!role) return '';
    return role
      .toLowerCase()
      .split('_')
      .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
      .join(' ');
  }

  // Clients stay on /client/profile: the generic /profile would drop them outside the client portal shell.
  // Platform staff have no Employee HR record, so /my-profile (GET /api/employees/me) would error for them.
  settingsLink(): string {
    if (this.auth.hasRole('CLIENT')) return '/client/profile';
    if (this.auth.isPlatformUser()) return '/profile';
    return '/my-profile';
  }

  // Clients already manage notification/security settings inside /client/profile, so only tenant/platform users get a distinct destination.
  accountSettingsLink(): string {
    if (this.auth.hasRole('CLIENT')) return '/client/profile';
    return '/profile';
  }
}
