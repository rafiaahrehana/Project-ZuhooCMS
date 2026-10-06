import { Pipe, PipeTransform } from '@angular/core';

/**
 * Always puts one space after the code: the built-in `currency` pipe glues unrecognized ISO codes to the number ("BDT20,000.00") in en-US.
 * Argument-compatible with `currency` (currencyCode, display, digitsInfo); display is accepted but ignored, digitsInfo's max-fraction-digits is honored.
 */
@Pipe({ name: 'bosCurrency', standalone: true })
export class BosCurrencyPipe implements PipeTransform {
  transform(
    value: number | string | null | undefined,
    currencyCode: string | null | undefined = 'BDT',
    displayOrDecimals?: string | number,
    digitsInfo?: string,
  ): string {
    const num = typeof value === 'string' ? parseFloat(value) : (value ?? 0);
    const code = (currencyCode || 'BDT').trim();

    let decimals = 2;
    if (typeof displayOrDecimals === 'number') {
      decimals = displayOrDecimals;
    } else if (typeof digitsInfo === 'string') {
      const match = digitsInfo.match(/\.\d+-(\d+)$/);
      if (match) decimals = parseInt(match[1], 10);
    }

    const formatted = new Intl.NumberFormat('en-US', {
      minimumFractionDigits: decimals,
      maximumFractionDigits: decimals,
    }).format(Number.isFinite(num) ? (num as number) : 0);
    return `${code} ${formatted}`;
  }
}
