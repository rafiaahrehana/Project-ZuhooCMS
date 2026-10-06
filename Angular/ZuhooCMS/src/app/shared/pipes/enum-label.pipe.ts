import { Pipe, PipeTransform } from '@angular/core';

/**
 * Turns a backend enum constant into something a person reads: OFFER_ACCEPTED -> "Offer Accepted".
 *
 * Angular's own `titlecase` only capitalises after whitespace, so an underscored constant came out as
 * "Offer_accepted" - one capital and a visible underscore. Thirteen application statuses, every attendance
 * method, every shift type and every notification type are underscored, so the fault showed up wherever one
 * was rendered. Several screens had already worked around it inline with replaceAll('_', ' '), which is how
 * the same value ended up formatted two ways in one app.
 *
 * On a value with no underscore this is exactly `titlecase`, which is why replacing that pipe with this one is
 * safe everywhere rather than only on the enums.
 */
/** Words that are acronyms in this product and read wrong title-cased: QR_CODE must not become "Qr Code". */
const ACRONYMS = new Set(['QR', 'ATS', 'SLA', 'KPI', 'PDF', 'CSV', 'HR', 'ID', 'AI', 'GPS', 'RFID', 'CRM', 'OTP']);

@Pipe({ name: 'enumLabel' })
export class EnumLabelPipe implements PipeTransform {
  transform(value: string | null | undefined): string {
    if (!value) return '';
    return value
      .replace(/_/g, ' ')
      .split(' ')
      .filter((w) => w.length > 0)
      .map((w) => (ACRONYMS.has(w.toUpperCase()) ? w.toUpperCase() : w.charAt(0).toUpperCase() + w.slice(1).toLowerCase()))
      .join(' ');
  }
}
