import { Injectable } from '@angular/core';
import { CanActivate, Router } from '@angular/router';
import { AuthService } from '../services/auth.service';

/** A plain EMPLOYEE lands on the Employee Dashboard whatever permissions they hold; platform staff and CLIENT keep their own landing flows. */
@Injectable({ providedIn: 'root' })
export class DashboardAccessGuard implements CanActivate {
  constructor(
    private authService: AuthService,
    private router: Router,
  ) {}

  canActivate(): boolean {
    const roles = this.authService.getCurrentUser()?.roles ?? [];
    const isRestrictedEmployee = roles.includes('EMPLOYEE') && !roles.includes('COMPANY_OWNER');

    if (isRestrictedEmployee) {
      this.router.navigate(['/employee-dashboard']);
      return false;
    }
    return true;
  }
}
