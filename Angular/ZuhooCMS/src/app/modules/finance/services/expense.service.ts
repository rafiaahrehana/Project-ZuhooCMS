import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';
import { ApiService, PagedResponse } from '../../../core/services/api.service';
import { Expense } from '../models/finance.model';

@Injectable({ providedIn: 'root' })
export class ExpenseService {
  private readonly endpoint = '/company/finance/expenses';
  constructor(private api: ApiService) {}
  list(page = 0, size = 20): Observable<PagedResponse<Expense>> {
    return this.api.getPaged<Expense>(this.endpoint, page, size);
  }
  listByStatus(status: string, page = 0): Observable<PagedResponse<Expense>> {
    return this.api.getPaged<Expense>(`${this.endpoint}/status/${status}`, page, 20);
  }
  // Matches the free-text vendorName column on Expense itself, exactly. It is NOT a lookup against the Vendor
  // master - there IS a Vendor entity (finance/vendor/Vendor.java, with its own controller and this file's
  // sibling vendor.service.ts), and Expense has no foreign key to it - so one supplier typed two ways on two
  // claims is two vendors to this endpoint.
  getByVendor(vendorName: string, page = 0): Observable<PagedResponse<Expense>> {
    return this.api.getPaged<Expense>(`${this.endpoint}/vendor/${encodeURIComponent(vendorName)}`, page, 20);
  }
  myExpenses(employeeId?: number, page = 0): Observable<PagedResponse<Expense>> {
    return this.api.getPaged<Expense>(`${this.endpoint}/my-expenses`, page, 20, employeeId ? { employeeId } : undefined);
  }
  getById(id: number): Observable<Expense> {
    return this.api.get<Expense>(`${this.endpoint}/${id}`);
  }
  create(payload: Partial<Expense>): Observable<Expense> {
    return this.api.post<Expense>(this.endpoint, payload);
  }
  composeEntry(payload: { vendorName?: string; amount?: string; category?: string; roughNotes: string }): Observable<{ title: string; description: string }> {
    return this.api.post<{ title: string; description: string }>(`${this.endpoint}/ai-compose`, payload);
  }
  update(id: number, payload: Partial<Expense>): Observable<Expense> {
    return this.api.patch<Expense>(`${this.endpoint}/${id}`, payload);
  }
  // notes/reason go as @RequestParam query params, not a JSON body; the reply's budgetWarning is set when approval pushes the category over or near its budget.
  approve(id: number, notes: string): Observable<{ message: string; budgetWarning?: string }> {
    return this.api.post<{ message: string; budgetWarning?: string }>(
      `${this.endpoint}/${id}/approve?notes=${encodeURIComponent(notes)}`, {});
  }
  reject(id: number, reason: string): Observable<void> {
    return this.api.post<void>(`${this.endpoint}/${id}/reject?reason=${encodeURIComponent(reason)}`, {});
  }
  markAsPaid(id: number, reimbursementMethod?: string, referenceNumber?: string): Observable<void> {
    const params = new URLSearchParams();
    if (reimbursementMethod) params.set('reimbursementMethod', reimbursementMethod);
    if (referenceNumber) params.set('referenceNumber', referenceNumber);
    const qs = params.toString();
    return this.api.post<void>(`${this.endpoint}/${id}/mark-as-paid${qs ? '?' + qs : ''}`, {});
  }
  delete(id: number): Observable<void> {
    return this.api.delete<void>(`${this.endpoint}/${id}`);
  }
}
