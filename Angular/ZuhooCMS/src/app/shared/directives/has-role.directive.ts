import { Directive, Input, OnDestroy, OnInit, TemplateRef, ViewContainerRef, inject } from '@angular/core';
import { Subscription } from 'rxjs';
import { AuthService } from '../../core/services/auth.service';

/**
 * Sibling of HasPermissionDirective for actions the backend gates by role, not by PermissionCode; without it such controls showed to everyone and 403'd on click.
 * Takes one role or several, any of which grants: <button *appHasRole="['SUPER_ADMIN', 'SYSTEM_ADMIN']">.
 * Copy the role list from the endpoint's own @PreAuthorize: the lists differ by a role or two, so this cannot collapse into one "is an admin" check.
 */
@Directive({
  selector: '[appHasRole]',
})
export class HasRoleDirective implements OnInit, OnDestroy {
  private templateRef = inject(TemplateRef<unknown>);
  private viewContainer = inject(ViewContainerRef);
  private auth = inject(AuthService);
  private sub?: Subscription;
  private roles: string[] = [];
  private hasView = false;

  @Input()
  set appHasRole(value: string | string[] | null | undefined) {
    this.roles = value == null ? [] : Array.isArray(value) ? value : [value];
    this.updateView();
  }

  ngOnInit(): void {
    // Subscribed, not read once: impersonation swaps roles for COMPANY_OWNER and back without a navigation, so a one-shot read leaves the old identity's controls on screen.
    this.sub = this.auth.currentUser$.subscribe(() => this.updateView());
  }

  ngOnDestroy(): void {
    this.sub?.unsubscribe();
  }

  private updateView(): void {
    // An empty list denies, unlike PermissionService.hasAnyPermission([]): here an empty binding means a typo or unresolved expression, so denying is the safe direction.
    const allowed = this.roles.length > 0 && this.auth.hasAnyRole(this.roles);
    if (allowed && !this.hasView) {
      this.viewContainer.createEmbeddedView(this.templateRef);
      this.hasView = true;
    } else if (!allowed && this.hasView) {
      this.viewContainer.clear();
      this.hasView = false;
    }
  }
}
