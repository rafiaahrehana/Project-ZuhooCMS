import { Component, OnInit, ChangeDetectionStrategy, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { PortalService, MyCompany, UpdateMyCompanyRequest } from '../../../portal/portal.service';
import { Loader } from '../../../../shared/components/loader/loader';

@Component({
  selector: 'app-company-settings',
  imports: [CommonModule, FormsModule, Loader],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './company-settings.html',
})
export class CompanySettings implements OnInit {
  loading = false;
  saving = false;
  error = '';
  success = '';

  form: UpdateMyCompanyRequest = { locationDetail: {} };

  /**
   * True only while the company has never had a base currency. The "Not set" option is offered on that strength
   * alone, because there is no clearing path on the server: an absent or blank currency leaves newCurrency null,
   * and the setter sits behind a check that requires it. So choosing "Not set" on a company that already has one
   * would be a 200 that changes nothing - the silent no-op this module has already produced four times.
   */
  currencyNeverSet = false;

  /** The form lives in a modal; the page itself is a read-only summary. */
  editing = false;

  readonly monthNames = ['January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'];

  monthName(m?: number | null): string {
    return m ? this.monthNames[m - 1] : this.monthNames[0];
  }

  /** One-line address for the summary card. */
  get addressSummary(): string {
    const l = this.form.locationDetail || {};
    return [l.streetAddress, l.level3, l.level2, l.level1, l.postalCode, l.country]
      .filter(Boolean).join(', ');
  }

  openEdit(): void {
    this.success = '';
    this.error = '';
    this.editing = true;
  }

  constructor(private portalService: PortalService, private cdr: ChangeDetectorRef) {}

  ngOnInit(): void {
    this.load();
  }

  load(): void {
    this.loading = true;
    this.error = '';
    this.cdr.markForCheck();
    this.portalService.getMyCompany().subscribe({
      next: (c: MyCompany) => {
        this.form = {
          companyName: c.companyName,
          companyPhone: c.companyPhone,
          website: c.website,
          portalAbout: c.portalAbout,
          taxRegistrationNumber: c.taxRegistrationNumber,
          bankName: c.bankName,
          bankAccountName: c.bankAccountName,
          bankAccountNumber: c.bankAccountNumber,
          bankBranch: c.bankBranch,
          fiscalYearStartMonth: c.fiscalYearStartMonth ?? 1,
          // NOT defaulted to BDT. AddressMapper aside, the company update assigns baseCurrency straight from the
          // request, so seeding a default meant any save - of the logo, of the phone number - pinned the currency
          // for a company that had never chosen one. Once there are ledger rows, that is not a field to set by
          // accident. Left undefined when the server has none, so the key is omitted.
          baseCurrency: c.baseCurrency,
          // All EIGHT address fields, because AddressMapper assigns every one unconditionally: a field missing
          // here was blanked on the server on every save. apartment was the missing one, and level4 being present
          // despite having no input of its own is the tell that somebody hit this once and fixed one of the two.
          locationDetail: {
            country: c.locationDetail?.country,
            level1: c.locationDetail?.level1,
            level2: c.locationDetail?.level2,
            level3: c.locationDetail?.level3,
            level4: c.locationDetail?.level4,
            postalCode: c.locationDetail?.postalCode,
            streetAddress: c.locationDetail?.streetAddress,
            apartment: c.locationDetail?.apartment,
          },
        };
        this.currencyNeverSet = !c.baseCurrency;
        this.loading = false;
        this.cdr.markForCheck();
      },
      error: () => {
        this.error = 'Failed to load company settings';
        this.loading = false;
        this.cdr.markForCheck();
      },
    });
  }

  save(): void {
    this.saving = true;
    this.error = '';
    this.success = '';
    this.cdr.markForCheck();
    this.portalService.updateMyCompany(this.form).subscribe({
      next: () => {
        this.saving = false;
        this.editing = false;
        this.success = 'Company settings saved';
        this.cdr.markForCheck();
      },
      error: (err) => {
        this.saving = false;
        this.error = err?.error?.message || 'Failed to save company settings';
        this.cdr.markForCheck();
      },
    });
  }
}
