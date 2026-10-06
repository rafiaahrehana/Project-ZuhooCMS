import { Component, OnInit, ChangeDetectionStrategy, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { FeatureFlag } from '../../models/platform-admin.model';
import { FeatureFlagService } from '../../services/feature-flag.service';
import { Loader } from '../../../../shared/components/loader/loader';
import { AuthService } from '../../../../core/services/auth.service';
import { HasRoleDirective } from '../../../../shared/directives/has-role.directive';


@Component({
  selector: 'app-feature-flags',
  imports: [CommonModule, FormsModule, Loader, HasRoleDirective],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './feature-flags.html',
})
export class FeatureFlags implements OnInit {
  flags: FeatureFlag[] = [];
  loading = false;
  seeding = false;
  error = '';
  success = '';

  // FeatureFlagController lets anyone authenticated read flags but only SUPER_ADMIN/SYSTEM_ADMIN change them.
  // The switch is disabled rather than hidden because it also shows the row's state; the seed buttons are pure actions, so they are hidden.
  readonly canToggle: boolean;

  constructor(
    private flagService: FeatureFlagService,
    private cdr: ChangeDetectorRef,
    auth: AuthService,
  ) {
    this.canToggle = auth.hasAnyRole(['SUPER_ADMIN', 'SYSTEM_ADMIN']);
  }

  ngOnInit(): void { this.load(); }

  load(): void {
    this.loading = true;
    this.error = '';
    this.cdr.markForCheck();
    this.flagService.list().subscribe({
      next: (res) => { this.flags = res || []; this.loading = false; this.cdr.markForCheck(); },
      error: () => { this.error = 'Failed to load feature flags'; this.loading = false; this.cdr.markForCheck(); }
    });
  }

  toggle(flag: FeatureFlag): void {
    const previous = flag.enabled;
    flag.enabled = !previous;
    this.flagService.toggle(flag.flagKey).subscribe({
      next: (res) => {
        flag.enabled = res.enabled;
        flag.updatedAt = res.updatedAt;
        this.success = `${flag.flagKey} ${flag.enabled ? 'enabled' : 'disabled'}`;
        this.cdr.markForCheck();
      },
      error: (err) => {
        flag.enabled = previous;
        this.error = err?.error?.message || 'Failed to toggle flag';
        this.cdr.markForCheck();
      }
    });
  }

  seed(): void {
    this.seeding = true;
    this.cdr.markForCheck();
    this.flagService.seed().subscribe({
      next: () => { this.seeding = false; this.success = 'Default feature flags seeded'; this.cdr.markForCheck(); this.load(); },
      error: (err) => { this.seeding = false; this.error = err?.error?.message || 'Failed to seed flags'; this.cdr.markForCheck(); }
    });
  }

  get enabledCount(): number {
    return this.flags.filter(f => f.enabled).length;
  }
}
