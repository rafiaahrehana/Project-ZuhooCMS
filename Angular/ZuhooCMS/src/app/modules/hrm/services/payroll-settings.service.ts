import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';
import { ApiService } from '../../../core/services/api.service';

/** Company payroll policy: the percentages salary structures are built from (e.g. house rent 40% of basic) and the per-day/overtime rates payroll prices absence and extra hours with. */
export interface PayrollSettings {
  perDayBasis: 'CALENDAR_DAYS' | 'FIXED_30' | 'FIXED_26' | 'ACTUAL_WORKING_DAYS';
  absenceDeductionBase: 'BASIC' | 'GROSS';
  overtimeEnabled: boolean;
  overtimeMultiplier: number;
  overtimeBase: 'BASIC' | 'GROSS';
  standardHoursPerDay: number;

  houseRentPercent: number;
  medicalPercent: number;
  transportPercent: number;
  foodPercent: number;
  providentFundPercent: number;
  taxPercent: number;
}

@Injectable({ providedIn: 'root' })
export class PayrollSettingsService {
  private readonly endpoint = '/hr/payroll-settings';

  constructor(private api: ApiService) {}

  get(): Observable<PayrollSettings> {
    return this.api.get<PayrollSettings>(this.endpoint);
  }

  update(payload: PayrollSettings): Observable<PayrollSettings> {
    return this.api.put<PayrollSettings>(this.endpoint, payload);
  }
}
