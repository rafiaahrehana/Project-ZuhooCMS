import { Component, ChangeDetectionStrategy, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AuthService } from '../../../core/services/auth.service';

/** A page rather than a modal: the Authentication nav group links straight here, so there is no page behind it to return to. */
@Component({
  selector: 'app-change-password',
  imports: [CommonModule, FormsModule],
  templateUrl: './change-password.html',
  styleUrl: './change-password.scss',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class ChangePassword {
  saving = false;
  error = '';
  success = '';

  showCurrent = false;
  showNew = false;
  showConfirm = false;

  form = { currentPassword: '', newPassword: '', confirmPassword: '' };

  constructor(
    private auth: AuthService,
    private cdr: ChangeDetectorRef,
  ) {}

  /** Five independent checks, so "Medium" means genuinely mixed, not just long. */
  get strength(): { label: string; class: string; bars: number } {
    const pw = this.form.newPassword;
    if (!pw) return { label: '', class: '', bars: 0 };
    let score = 0;
    if (pw.length >= 8) score++;
    if (/[A-Z]/.test(pw)) score++;
    if (/[a-z]/.test(pw)) score++;
    if (/[0-9]/.test(pw)) score++;
    if (/[!@#$%^&*()_+\-=\[\]{};':\\|,.<>\/?]/.test(pw)) score++;

    if (score <= 2) return { label: 'Weak', class: 'text-danger', bars: 1 };
    if (score <= 4) return { label: 'Medium', class: 'text-warning', bars: 3 };
    return { label: 'Strong', class: 'text-success', bars: 5 };
  }

  submit(): void {
    const { currentPassword, newPassword, confirmPassword } = this.form;

    if (!currentPassword || !newPassword || !confirmPassword) {
      this.error = 'All password fields are required';
      return;
    }
    if (newPassword.length < 8) {
      this.error = 'New password must be at least 8 characters';
      return;
    }
    if (newPassword !== confirmPassword) {
      this.error = 'New passwords do not match';
      return;
    }

    this.saving = true;
    this.error = '';
    this.success = '';
    this.cdr.markForCheck();

    this.auth.changePassword({ currentPassword, newPassword, confirmPassword }).subscribe({
      next: () => {
        this.saving = false;
        this.form = { currentPassword: '', newPassword: '', confirmPassword: '' };
        // The backend revokes every refresh token on a password change, so sign out rather than hit a silent 401 on the next request.
        this.success = 'Password changed successfully. Redirecting to sign in...';
        this.cdr.markForCheck();
        setTimeout(() => this.auth.logout(), 2000);
      },
      error: (err) => {
        this.saving = false;
        this.error = err?.error?.message || 'Failed to change password';
        this.cdr.markForCheck();
      },
    });
  }
}
