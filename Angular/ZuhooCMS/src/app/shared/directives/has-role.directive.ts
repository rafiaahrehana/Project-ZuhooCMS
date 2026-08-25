import { Directive, Input, OnDestroy, OnInit, TemplateRef, ViewContainerRef, inject } from '@angular/core';
import { Subscription } from 'rxjs';
import { AuthService } from '../../core/services/auth.service';

/**
 * Structural sibling of HasPermissionDirective, for actions the backend gates by
 * role rather than by permission.
 *
 * The two axes are not interchangeable and the backend uses both: most tenant
 * modules check a PermissionCode, while the platform console, the support desk
 * and a handful of company-level actions check a role. Until this existed there
 * was no way to express the second kind in a template, so those controls were
 * shown to everyone who could open the screen and failed with a 403 on click.
 *
 * Usage mirrors the permission directive - one role or several, any of which
 * grants:
 *
 *   <button *appHasRole="'SUPER_ADMIN'">Seed flags</button>
 *   <button *appHasRole="['SUPER_ADMIN', 'SYSTEM_ADMIN']">Toggle</button>
 *
 * Copy the role list from the endpoint's own @PreAuthorize rather than from a
 * nearby screen: the lists differ by a role or two in almost every case, which
 * is exactly why this cannot be collapsed into a single "is an admin" check.
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
    // Subscribed to the user rather than read once, because roles change
    // underneath a live view: signing in, signing out, and - the case that
    // actually bites - starting or ending an impersonation session, which
    // swaps the caller's roles for COMPANY_OWNER and back again without a
    // navigation. A one-shot read would leave the previous identity's controls
    // on screen.
    this.sub = this.auth.currentUser$.subscribe(() => this.updateView());
  }

  ngOnDestroy(): void {
    this.sub?.unsubscribe();
  }

  private updateView(): void {
    // An empty list denies - deliberately the opposite of
    // PermissionService.hasAnyPermission([]), which returns true so that "no
    // required permission" can mean "no restriction" for things like nav items.
    // That reading does not transfer here: nobody writes *appHasRole with an
    // empty binding to mean unrestricted, they just omit the directive. So an
    // empty list is a typo or an unresolved expression, and denying is the safe
    // direction - a control that wrongly fails to appear gets reported, one
    // that wrongly appears does not.
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
