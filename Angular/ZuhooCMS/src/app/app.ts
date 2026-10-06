import { Component, ChangeDetectionStrategy, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { NavigationEnd, Router, RouterLink, RouterOutlet } from '@angular/router';
import { filter } from 'rxjs';
import { AuthService } from './core/services/auth.service';
import { NotificationService, Toast } from './shared/services/notification.service';
import { DialogA11yService } from './shared/a11y/dialog-a11y.service';
import { AccessibleNamesService } from './shared/a11y/accessible-names.service';
import { DialogDiscardGuardService } from './shared/a11y/dialog-discard-guard.service';
import { PermissionService } from './core/services/permission.service';
import { ThemeService } from './core/services/theme.service';
import { Navbar } from './shared/components/navbar/navbar';
import { Sidebar } from './shared/components/sidebar/sidebar';
import { PlatformSidebar } from './shared/components/platform-sidebar/platform-sidebar';
import { ClientSidebar } from './shared/components/client-sidebar/client-sidebar';
import { ImpersonationBanner } from './shared/components/impersonation-banner/impersonation-banner';

function isPortalUrl(url: string): boolean {
  return url.startsWith('/portal/');
}

@Component({
  selector: 'app-root',
  imports: [CommonModule, RouterOutlet, RouterLink, Navbar, Sidebar, PlatformSidebar, ClientSidebar, ImpersonationBanner],
  templateUrl: './app.html',
  changeDetection: ChangeDetectionStrategy.Eager,
  styleUrl: './app.scss',
})
export class App {
  private router = inject(Router);

  // Seeded from window.location, not router.url, which is still '/' until the first NavigationEnd and would render the authenticated shell around a portal page.
  isPortalRoute = signal(isPortalUrl(window.location.pathname));

  isDragging = false;
  hasDragged = false;
  dragStartX = 0;
  dragStartY = 0;
  posX = signal<number | null>(null);
  posY = signal<number | null>(null);

  constructor(
    public auth: AuthService,
    public notifications: NotificationService,
    public permissionService: PermissionService,
    // Injected for its constructor side effect: without it a visitor landing on /home with a dark OS keeps the pre-paint dark attributes over light sections.
    private themeService: ThemeService,
    // All three injected for their constructor side effects: they install one document-wide
    // observer each, which is what gives the app's 117 hand-rolled modals their dialog
    // semantics and its ~1040 form controls their labels, without per-template edits.
    private dialogA11y: DialogA11yService,
    private accessibleNames: AccessibleNamesService,
    // And the third: a part-filled dialog asks before it is thrown away.
    private dialogDiscardGuard: DialogDiscardGuardService,
  ) {
    this.router.events.pipe(filter((e) => e instanceof NavigationEnd)).subscribe((e) => {
      this.isPortalRoute.set(isPortalUrl((e as NavigationEnd).urlAfterRedirects));
      document.body.classList.remove('sidebar-open');
    });
  }

  /** A failure has to interrupt whatever is being read; a confirmation can wait. */
  isUrgentToast(toast: Toast): boolean {
    return toast.type === 'danger' || toast.type === 'warning';
  }

  onMouseDown(event: MouseEvent): void {
    if (event.button !== 0) return;
    this.startDrag(event.clientX, event.clientY);
    const onMouseMove = (e: MouseEvent) => this.onDrag(e.clientX, e.clientY);
    const onMouseUp = () => {
      window.removeEventListener('mousemove', onMouseMove);
      window.removeEventListener('mouseup', onMouseUp);
      this.endDrag();
    };
    window.addEventListener('mousemove', onMouseMove);
    window.addEventListener('mouseup', onMouseUp);
  }

  onTouchStart(event: TouchEvent): void {
    if (event.touches.length === 1) {
      const touch = event.touches[0];
      this.startDrag(touch.clientX, touch.clientY);
      const onTouchMove = (e: TouchEvent) => {
        if (e.touches.length === 1) {
          this.onDrag(e.touches[0].clientX, e.touches[0].clientY);
        }
      };
      const onTouchEnd = () => {
        window.removeEventListener('touchmove', onTouchMove);
        window.removeEventListener('touchend', onTouchEnd);
        this.endDrag();
      };
      window.addEventListener('touchmove', onTouchMove, { passive: true });
      window.addEventListener('touchend', onTouchEnd);
    }
  }

  private startDrag(clientX: number, clientY: number): void {
    this.isDragging = true;
    this.hasDragged = false;
    this.dragStartX = clientX;
    this.dragStartY = clientY;

    const btn = document.getElementById('ai-fab-btn');
    if (btn && (this.posX() === null || this.posY() === null)) {
      const rect = btn.getBoundingClientRect();
      this.posX.set(rect.left);
      this.posY.set(rect.top);
    }
  }

  private onDrag(clientX: number, clientY: number): void {
    if (!this.isDragging) return;
    const deltaX = clientX - this.dragStartX;
    const deltaY = clientY - this.dragStartY;

    if (Math.abs(deltaX) > 4 || Math.abs(deltaY) > 4) {
      this.hasDragged = true;
    }

    if (this.hasDragged) {
      let newX = (this.posX() ?? (window.innerWidth - 140)) + deltaX;
      let newY = (this.posY() ?? (window.innerHeight - 80)) + deltaY;

      newX = Math.max(10, Math.min(window.innerWidth - 130, newX));
      newY = Math.max(10, Math.min(window.innerHeight - 60, newY));

      this.posX.set(newX);
      this.posY.set(newY);

      this.dragStartX = clientX;
      this.dragStartY = clientY;
    }
  }

  private endDrag(): void {
    this.isDragging = false;
  }

  goToAi(): void {
    if (this.hasDragged) {
      this.hasDragged = false;
      return;
    }
    this.router.navigate(['/ai']);
  }
}
