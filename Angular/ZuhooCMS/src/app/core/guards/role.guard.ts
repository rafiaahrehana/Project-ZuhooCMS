import { Injectable } from '@angular/core';
import { CanActivate, CanActivateChild, ActivatedRouteSnapshot, RouterStateSnapshot, Router } from '@angular/router';
import { Observable, map } from 'rxjs';
import { AuthService } from '../services/auth.service';
import { PermissionService } from '../services/permission.service';
import { NotificationService } from '../../shared/services/notification.service';

@Injectable({
  providedIn: 'root'
})
export class RoleGuard implements CanActivate, CanActivateChild {
  constructor(
    private authService: AuthService,
    private permissionService: PermissionService,
    private router: Router,
    private notificationService: NotificationService
  ) {}

  canActivate(route: ActivatedRouteSnapshot, state: RouterStateSnapshot): boolean | Observable<boolean> {
    return this.checkAccess(route);
  }

  canActivateChild(route: ActivatedRouteSnapshot, state: RouterStateSnapshot): boolean | Observable<boolean> {
    return this.checkAccess(route);
  }

  // Roles and permissions are checked independently; this, not the sidebar filter, is the real gate against typing a module's URL directly.
  private checkAccess(route: ActivatedRouteSnapshot): boolean | Observable<boolean> {
    const requiredRoles = route.data['roles'] as string[] | undefined;
    if (requiredRoles && requiredRoles.length > 0 && !this.authService.hasAnyRole(requiredRoles)) {
      return this.deny();
    }

    const requiredPermission = route.data['requiredPermission'] as string | undefined;
    if (!requiredPermission) {
      return true;
    }
    if (this.authService.isPlatformStaff()) {
      return true;
    }

    // ensureLoaded() waits for the in-flight load(); without it a hard reload into a gated route 403s on the stale cached permission set.
    return this.permissionService.ensureLoaded().pipe(
      map(() => {
        if (!this.permissionService.hasPermission(requiredPermission)) {
          return this.deny();
        }
        return true;
      }),
    );
  }

  private deny(): boolean {
    this.notificationService.error('Insufficient permissions');
    this.router.navigate(['/forbidden']);
    return false;
  }
}
