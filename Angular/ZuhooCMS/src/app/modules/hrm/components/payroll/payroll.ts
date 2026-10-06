import { Component, OnInit, ChangeDetectionStrategy, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Payroll, CreatePayrollRequest, Employee, BulkPayrollResult } from '../../models/hrm.model';
import { PaymentMethod, PAYROLL_PAYMENT_METHODS } from '../../../finance/models/finance.model';
import { readBlobErrorMessage } from '../../../../core/utils/http-error.util';
import { PayrollService } from '../../services/payroll.service';
import { EmployeeService } from '../../services/employee.service';
import { SalaryStructureService } from '../../services/salary-structure.service';
import { PayrollSettingsService, PayrollSettings } from '../../services/payroll-settings.service';
import { PayrollRunService, PayrollRun } from '../../services/payroll-run.service';
import { Pagination } from '../../../../shared/components/pagination/pagination';
import { Loader } from '../../../../shared/components/loader/loader';
import { EmptyState } from '../../../../shared/components/empty-state/empty-state';
import { ConfirmDialog } from '../../../../shared/components/confirm-dialog/confirm-dialog';
import { HasPermissionDirective } from '../../../../shared/directives/has-permission.directive';

@Component({
  selector: 'app-payroll',
  imports: [CommonModule, FormsModule, Pagination, Loader, EmptyState, ConfirmDialog, HasPermissionDirective],
  templateUrl: './payroll.html',
  changeDetection: ChangeDetectionStrategy.OnPush,
  styleUrl: './payroll.scss',
})
export class PayrollPage implements OnInit {
  payrolls: Payroll[] = [];
  employees: Employee[] = [];
  totalPages = 0;
  page = 0;
  loading = false;
  saving = false;
  error = '';
  success = '';

  months = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
  years: number[] = [];
  month: number;
  year: number;

  showForm = false;
  form: CreatePayrollRequest = this.emptyForm();

  /** Tells the user where the figures in the form came from, or that none were found. */
  structureNote = '';

  /**
   * The structure's own tax and provident fund. The server adds these itself, so they stay out of
   * the form and only join the preview totals - see onEmployeeSelected.
   */
  structureTax = 0;
  structurePf = 0;
  /** True once a structure has been read for the selected employee, even if its tax and PF are zero. */
  hasStructure = false;

  /** Company percentages: label what each component is a percentage of, and derive amounts when no approved structure exists. */
  settings?: PayrollSettings;

  /** Whether editing Basic re-derives the other components; off when an approved salary structure filled the form, so its figures are not overwritten by company defaults. */
  autoCalc = false;

  payTarget: Payroll | null = null;
  paymentReference = '';
  paymentMethod: PaymentMethod | '' = '';
  // Payout rails only - see PAYROLL_PAYMENT_METHODS for why SSLCommerz and the company wallet are not offered here.
  paymentMethods = PAYROLL_PAYMENT_METHODS;
  deleteTarget: Payroll | null = null;

  generating = false;
  generateResult: BulkPayrollResult | null = null;
  confirmGenerate = false;

  run: PayrollRun | null = null;
  runBusy = false;
  runError = '';
  showRejectBox = false;
  rejectReason = '';
  showRunPay = false;
  runPayMethod: PaymentMethod | '' = '';

  constructor(
    private payrollService: PayrollService,
    private employeeService: EmployeeService,
    private salaryStructureService: SalaryStructureService,
    private payrollSettingsService: PayrollSettingsService,
    private payrollRunService: PayrollRunService,
    private cdr: ChangeDetectorRef,
  ) {
    const now = new Date();
    this.month = now.getMonth() + 1;
    this.year = now.getFullYear();
    for (let y = this.year + 1; y >= 2020; y--) this.years.push(y);
  }

  ngOnInit(): void {
    this.load();
    this.employeeService.list(0, 100).subscribe({ next: (res) => { this.employees = res.content; this.cdr.markForCheck(); } });
    // Percentages are policy, not per-employee, so they are fetched once.
    this.payrollSettingsService.get().subscribe({
      next: (s) => { this.settings = s; this.cdr.markForCheck(); },
      error: () => { /* the form still works, it just cannot show or apply percentages */ },
    });
  }

  /** e.g. "40% of Basic" - shown beside the field so the number is explainable. */
  percentHint(component: 'houseRent' | 'medical' | 'transport' | 'food' | 'providentFund' | 'tax'): string {
    if (!this.settings) return '';
    const pct = {
      houseRent: this.settings.houseRentPercent,
      medical: this.settings.medicalPercent,
      transport: this.settings.transportPercent,
      food: this.settings.foodPercent,
      providentFund: this.settings.providentFundPercent,
      tax: this.settings.taxPercent,
    }[component];
    if (pct == null) return '';
    return `${this.trimPercent(pct)}% of Basic`;
  }

  private trimPercent(v: number): string {
    return String(Number(v));
  }

  /** Derives all six components from Basic; tax is a flat percentage here, not the progressive NBR slabs, so it is a working payslip figure. */
  applyPercentages(): void {
    const s = this.settings;
    const basic = Number(this.form.basicSalary) || 0;
    if (!s || basic <= 0) return;

    const pc = (percent: number) => Math.round(((basic * (percent || 0)) / 100) * 100) / 100;

    this.form.houseRent = pc(s.houseRentPercent);
    this.form.medicalAllowance = pc(s.medicalPercent);
    this.form.transportAllowance = pc(s.transportPercent);
    this.form.foodAllowance = pc(s.foodPercent);
    // Only when no structure applies - otherwise the server adds the structure's own tax and PF
    // on top of these, deducting both twice.
    if (!this.hasStructure) {
      this.form.providentFundDeduction = pc(s.providentFundPercent);
      this.form.taxDeduction = pc(s.taxPercent);
    }
    this.structureNote = 'Components derived from Basic using the company percentages.'
      + (this.hasStructure ? ' Tax and provident fund still come from the salary structure.' : '');
    this.cdr.markForCheck();
  }

  /** Only re-derives while auto-calculate is on - see the field's comment. */
  onBasicChanged(): void {
    if (this.autoCalc) this.applyPercentages();
  }

  /** Gross and net previewed live, so the form is not a black box until save. */
  get previewGross(): number {
    const f: any = this.form;
    return ['basicSalary', 'houseRent', 'medicalAllowance', 'transportAllowance',
            'foodAllowance', 'specialAllowance', 'bonus']
      .reduce((sum, k) => sum + (Number(f[k]) || 0), 0);
  }

  get previewDeductions(): number {
    const f: any = this.form;
    return ['deductions', 'taxDeduction', 'insuranceDeduction', 'providentFundDeduction']
      .reduce((sum, k) => sum + (Number(f[k]) || 0), 0)
      // The server applies these two from the structure, so the preview has to count them too.
      + this.structureTax + this.structurePf;
  }

  get previewNet(): number {
    return this.previewGross - this.previewDeductions;
  }

  downloadingCsv = false;

  /** Bank disbursement sheet for the period: APPROVED payrolls only, and downloading changes no status. */
  downloadDisbursement(): void {
    if (this.downloadingCsv) return;
    this.downloadingCsv = true;
    this.error = '';
    this.cdr.markForCheck();

    this.payrollService.disbursementCsv(this.month, this.year).subscribe({
      next: (blob) => {
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `salary-disbursement-${this.year}-${String(this.month).padStart(2, '0')}.csv`;
        a.click();
        // Without this the blob stays held for the life of the document.
        URL.revokeObjectURL(url);
        this.downloadingCsv = false;
        this.cdr.markForCheck();
      },
      // responseType: 'blob' means err.error is a Blob, so err.error.message was always undefined and this
      // always showed the generic line. readBlobErrorMessage reads the body and gets the server's reason.
      error: (err) => {
        this.downloadingCsv = false;
        this.cdr.markForCheck();
        readBlobErrorMessage(err, 'Failed to download the disbursement file').then((message) => {
          this.error = message;
          this.cdr.markForCheck();
        });
      },
    });
  }

  load(): void {
    this.loading = true;
    this.error = '';
    this.payrollService.listByPeriod(this.month, this.year, this.page, 50).subscribe({
      next: (res) => {
        this.payrolls = res.content;
        this.totalPages = res.totalPages;
        this.loading = false;
        this.cdr.markForCheck();
      },
      error: () => {
        this.error = 'Failed to load payroll';
        this.loading = false;
        this.cdr.markForCheck();
      },
    });
    this.loadRun();
  }

  loadRun(): void {
    this.payrollRunService.forPeriod(this.month, this.year).subscribe({
      next: (r) => { this.run = r || null; this.cdr.markForCheck(); },
      error: () => { this.run = null; this.cdr.markForCheck(); },
    });
  }

  createRun(): void {
    this.runAction(this.payrollRunService.create(this.month, this.year));
  }

  submitRun(): void { if (this.run) this.runAction(this.payrollRunService.submit(this.run.id)); }
  approveRun(): void { if (this.run) this.runAction(this.payrollRunService.approve(this.run.id)); }
  recalcRun(): void { if (this.run) this.runAction(this.payrollRunService.recalculate(this.run.id)); }
  cancelRun(): void { if (this.run) this.runAction(this.payrollRunService.cancel(this.run.id)); }

  rejectRun(): void {
    if (!this.run || !this.rejectReason.trim()) return;
    this.showRejectBox = false;
    this.runAction(this.payrollRunService.reject(this.run.id, this.rejectReason.trim()));
    this.rejectReason = '';
  }

  payRun(): void {
    if (!this.run || !this.runPayMethod) return;
    this.showRunPay = false;
    this.runAction(this.payrollRunService.pay(this.run.id, this.runPayMethod));
  }

  runStatusBadge(status: string): string {
    return {
      DRAFT: 'text-bg-secondary', CALCULATED: 'text-bg-info', PENDING_APPROVAL: 'text-bg-warning',
      APPROVED: 'text-bg-primary', PAID: 'text-bg-success', REJECTED: 'text-bg-danger',
      CANCELLED: 'text-bg-secondary',
    }[status] || 'text-bg-secondary';
  }

  private runAction(op: { subscribe: Function }): void {
    this.runBusy = true;
    this.runError = '';
    op.subscribe({
      next: (r: PayrollRun) => {
        this.run = r;
        this.runBusy = false;
        this.cdr.markForCheck();
        // Line statuses / rows may have changed (generation, approval, payment).
        this.page = 0;
        this.payrollService.listByPeriod(this.month, this.year, 0, 50).subscribe({
          next: (res) => { this.payrolls = res.content; this.totalPages = res.totalPages; this.cdr.markForCheck(); },
        });
      },
      error: (err: any) => {
        this.runBusy = false;
        this.runError = err?.error?.message || 'Payroll run action failed';
        this.cdr.markForCheck();
      },
    });
  }

  /** Fills from the approved salary structure, not the Employee record (a partial undated copy that left food, special, provident fund and tax missing); matches PayrollServiceImpl.activeStructure so manual and batch agree. */
  onEmployeeSelected(): void {
    const id = this.form.employeeId;
    if (!id) return;

    this.structureNote = '';
    this.hasStructure = false;
    this.structureTax = 0;
    this.structurePf = 0;
    this.salaryStructureService.getActive(id).subscribe({
      next: (s) => {
        if (!s) { this.applyEmployeeFallback(); return; }
        this.hasStructure = true;
        this.form.basicSalary = s.basicSalary ?? 0;
        this.form.houseRent = s.houseRent ?? 0;
        this.form.medicalAllowance = s.medicalAllowance ?? 0;
        this.form.transportAllowance = s.transportAllowance ?? 0;
        this.form.foodAllowance = s.foodAllowance ?? 0;
        this.form.specialAllowance = s.specialAllowance ?? 0;
        // Tax and provident fund are deliberately left out of the form: PayrollCalculator adds the
        // structure's own figures on top of whatever the request carries, so copying them here
        // deducted both of them twice. They go into the preview and the note instead.
        this.form.taxDeduction = undefined as any;
        this.form.providentFundDeduction = undefined as any;
        this.structureTax = s.taxDeduction ?? 0;
        this.structurePf = s.providentFund ?? 0;
        // Auto-calculate stays off so editing Basic cannot replace approved figures with company defaults.
        this.autoCalc = false;
        const applied = this.structureTax + this.structurePf;
        this.structureNote = `Filled from the salary structure effective ${s.effectiveFrom}.`
          + (applied > 0
            ? ` Tax and provident fund from the structure are applied by the server - leave those two fields blank unless you are adding extra on top.`
            : '');
        this.cdr.markForCheck();
      },
      // No structure on file is a normal state for a new hire, not an error.
      error: () => { this.applyEmployeeFallback(); },
    });
  }

  /** Last resort when no structure exists: the partial figures on the employee record. */
  private applyEmployeeFallback(): void {
    // No structure, so the server adds nothing of its own and the form carries every deduction.
    this.hasStructure = false;
    this.structureTax = 0;
    this.structurePf = 0;
    const emp = this.employees.find((e) => e.id === this.form.employeeId);
    if (emp) {
      this.form.basicSalary = emp.basicSalary ?? this.form.basicSalary;
      this.form.houseRent = emp.houseRent ?? 0;
      this.form.medicalAllowance = emp.medicalAllowance ?? 0;
      this.form.transportAllowance = emp.transportAllowance ?? 0;
    }
    // No approved figures to protect, so the percentages become the default and Basic drives the rest.
    this.autoCalc = true;
    this.structureNote = 'No approved salary structure for this employee - components follow the company percentages.';
    this.applyPercentages();
    this.cdr.markForCheck();
  }

  save(): void {
    this.saving = true;
    this.error = '';
    const payload: any = { ...this.form };
    Object.keys(payload).forEach((k) => {
      if (payload[k] === '' || payload[k] === null || payload[k] === undefined) delete payload[k];
    });
    this.payrollService.create(payload).subscribe({
      next: () => {
        this.saving = false;
        this.showForm = false;
        this.form = this.emptyForm();
        this.structureNote = '';
        this.hasStructure = false;
        this.structureTax = 0;
        this.structurePf = 0;
        this.success = 'Payroll created';
        this.cdr.markForCheck();
        this.load();
      },
      error: (err) => {
        this.saving = false;
        this.error = err?.error?.message || 'Failed to create payroll';
        this.cdr.markForCheck();
      },
    });
  }

  openGenerate(): void {
    this.generateResult = null;
    this.confirmGenerate = true;
  }

  runGenerate(): void {
    this.confirmGenerate = false;
    this.generating = true;
    this.error = '';
    this.payrollService.generateForAll(this.month, this.year).subscribe({
      next: (result) => {
        this.generating = false;
        this.generateResult = result;
        this.success = `Generated ${result.created.length} payroll draft(s)`;
        this.cdr.markForCheck();
        this.load();
      },
      error: (err) => {
        this.generating = false;
        this.error = err?.error?.message || 'Failed to generate payroll';
        this.cdr.markForCheck();
      },
    });
  }

  approve(p: Payroll): void {
    this.payrollService.approve(p.id).subscribe({
      next: () => {
        this.success = 'Payroll approved';
        this.cdr.markForCheck();
        this.load();
      },
      error: (err) => { this.error = err?.error?.message || 'Failed to approve payroll'; this.cdr.markForCheck(); },
    });
  }

  openPay(p: Payroll): void {
    this.payTarget = p;
    this.paymentReference = '';
    this.paymentMethod = '';
  }

  confirmPay(): void {
    if (!this.payTarget) return;
    this.payrollService
      .markPaid(this.payTarget.id, this.paymentReference.trim() || undefined, this.paymentMethod || undefined)
      .subscribe({
        next: () => {
          this.payTarget = null;
          this.success = 'Payroll marked as paid';
          this.cdr.markForCheck();
          this.load();
        },
        error: (err) => {
          this.payTarget = null;
          this.error = err?.error?.message || 'Failed to mark as paid';
          this.cdr.markForCheck();
        },
      });
  }

  confirmDelete(): void {
    if (!this.deleteTarget) return;
    this.payrollService.delete(this.deleteTarget.id).subscribe({
      next: () => {
        this.deleteTarget = null;
        this.success = 'Payroll deleted';
        this.cdr.markForCheck();
        this.load();
      },
      error: (err) => {
        this.error = err?.error?.message || 'Failed to delete payroll';
        this.deleteTarget = null;
        this.cdr.markForCheck();
      },
    });
  }

  goToPage(p: number): void {
    this.page = p;
    this.load();
  }

  private emptyForm(): CreatePayrollRequest {
    return {
      employeeId: undefined as any,
      payMonth: this.month ?? new Date().getMonth() + 1,
      payYear: this.year ?? new Date().getFullYear(),
      basicSalary: undefined as any,
    };
  }
}
