import { ChangeDetectorRef, Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { ApiService } from '../../../../core/services/api.service';

/** Posts to the anonymous lead-capture endpoint so a submission becomes a Lead in the platform company's CRM. */
@Component({
  selector: 'app-contact-sales',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink],
  templateUrl: './contact-sales.html',
  styleUrls: ['./contact-sales.scss']
})
export class ContactSales {
  form = {
    name: '',
    email: '',
    phone: '',
    companyName: '',
    message: '',
    // Honeypot - stays empty for humans; the server drops filled ones.
    website: '',
  };

  sending = false;
  sent = false;
  error = '';

  constructor(private api: ApiService, private cdr: ChangeDetectorRef) {}

  submitForm(event: Event): void {
    event.preventDefault();
    if (this.sending || !this.form.name.trim() || !this.form.email.trim()) return;

    this.sending = true;
    this.error = '';

    // Zoneless: the response lands outside change detection, so without markForCheck the button keeps
    // spinning and neither the thank-you nor the error is ever painted.
    this.cdr.markForCheck();

    this.api.post('/public/crm/leads', this.form).subscribe({
      next: () => {
        this.sending = false;
        this.sent = true;
        this.cdr.markForCheck();
      },
      error: (err) => {
        this.sending = false;
        this.error = err?.error?.message || 'Something went wrong - please try again.';
        this.cdr.markForCheck();
      },
    });
  }
}
