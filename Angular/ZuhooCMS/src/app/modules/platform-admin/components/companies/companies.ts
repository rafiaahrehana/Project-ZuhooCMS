import { EnumLabelPipe } from '../../../../shared/pipes/enum-label.pipe';
import { SecureFilePipe } from '../../../../shared/pipes/secure-file.pipe';
import { ActivatedRoute } from '@angular/router';
import { Component, OnInit, ChangeDetectionStrategy, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import {
  Company,
  COMPANY_STATUSES,
  CompanyStatus,
  RegisterCompanyRequest,
  SubscriptionPlan,
  SubscriptionPlanDefinition,
} from '../../models/platform-admin.model';
import { CompanyService } from '../../services/company.service';
import { SubscriptionPlanDefinitionService } from '../../services/subscription-plan-definition.service';
import { AuthService } from '../../../../core/services/auth.service';
import { HasRoleDirective } from '../../../../shared/directives/has-role.directive';
import { extractErrorMessage } from '../../../../core/utils/http-error.util';
import { Pagination } from '../../../../shared/components/pagination/pagination';
import { Loader } from '../../../../shared/components/loader/loader';
import { EmptyState } from '../../../../shared/components/empty-state/empty-state';
import { ConfirmDialog } from '../../../../shared/components/confirm-dialog/confirm-dialog';

@Component({
  selector: 'app-companies',
  imports: [EnumLabelPipe, SecureFilePipe, CommonModule, FormsModule, Pagination, Loader, EmptyState, ConfirmDialog, HasRoleDirective],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './companies.html',
})
export class Companies implements OnInit {
  companies: Company[] = [];
  totalPages = 0;
  totalCompanies = 0;
  page = 0;
  loading = false;
  error = '';
  success = '';

  statusFilter: CompanyStatus | '' = '';
  planFilter: SubscriptionPlan | '' = '';
  keyword = '';

  kpi = { total: 0, active: 0, trial: 0, suspended: 0 };
  loadingKpi = false;

  showRegister = false;
  form: RegisterCompanyRequest = {
    companyName: '', subdomain: '', ownerFirstName: '', ownerLastName: '', ownerEmail: '', ownerPassword: ''
  };

  planTarget: Company | null = null;
  planAmountPaid: number | null = null;
  planTransactionRef = '';
  newPlan: SubscriptionPlan = 'STARTER';

  statusTarget: Company | null = null;
  newStatus: CompanyStatus = 'ACTIVE';

  deactivateTarget: Company | null = null;

  impersonateTarget: Company | null = null;
  impersonateReason = '';
  impersonating = false;

  statuses = COMPANY_STATUSES;
  plans: SubscriptionPlanDefinition[] = [];

  constructor(
    private companyService: CompanyService,
    private planDefinitionService: SubscriptionPlanDefinitionService,
    private auth: AuthService,
    private route: ActivatedRoute,
    private cdr: ChangeDetectorRef,
  ) {}

  ngOnInit(): void {
    // Dashboard stat cards deep-link here pre-filtered (?status=TRIAL, ?plan=PRO ...)
    const qp = this.route.snapshot.queryParamMap;
    this.statusFilter = (qp.get('status') as CompanyStatus) || '';
    this.planFilter = (qp.get('plan') as SubscriptionPlan) || '';
    this.keyword = qp.get('keyword') || '';
    this.load();
    this.loadKpi();
    // Includes inactive plans: a company may already be on a since-disabled plan and still needs correct filter/badge display.
    this.planDefinitionService.list(false).subscribe({
      next: (plans) => { this.plans = plans; this.cdr.markForCheck(); },
      error: () => {},
    });
  }

  load(): void {
    this.loading = true;
    this.error = '';
    this.cdr.markForCheck();
    this.companyService.list(this.page, 20, this.statusFilter || undefined, this.planFilter || undefined, this.keyword || undefined).subscribe({
      next: (res) => {
        this.companies = res.content;
        this.totalPages = res.totalPages;
        this.totalCompanies = res.totalElements;
        this.loading = false;
        this.cdr.markForCheck();
      },
      error: () => { this.error = 'Failed to load companies'; this.loading = false; this.cdr.markForCheck(); }
    });
  }

  // One unfiltered page-1 call for the total, plus per-status calls for the breakdown, kept separate from the main list.
  loadKpi(): void {
    this.loadingKpi = true;
    // Reset the counter: without it a reload starts at 4 and finishes on the first response, with the
    // other three tiles still showing the previous load's numbers.
    this.kpiReady = 0;
    this.cdr.markForCheck();
    // A failed call still has to count, or the tiles spin forever waiting for a fourth answer that
    // will never come. Each tile keeps whatever it already had; only the spinner is resolved.
    this.companyService.list(0, 1).subscribe({
      next: (res) => { this.kpi.total = res.totalElements; this.tryFinishKpi(); },
      error: () => this.tryFinishKpi()
    });
    this.companyService.list(0, 1, 'ACTIVE').subscribe({
      next: (res) => { this.kpi.active = res.totalElements; this.tryFinishKpi(); },
      error: () => this.tryFinishKpi()
    });
    this.companyService.list(0, 1, 'TRIAL').subscribe({
      next: (res) => { this.kpi.trial = res.totalElements; this.tryFinishKpi(); },
      error: () => this.tryFinishKpi()
    });
    this.companyService.list(0, 1, 'SUSPENDED').subscribe({
      next: (res) => { this.kpi.suspended = res.totalElements; this.tryFinishKpi(); },
      error: () => this.tryFinishKpi()
    });
  }

  private kpiReady = 0;
  private tryFinishKpi(): void {
    this.kpiReady++;
    if (this.kpiReady >= 4) { this.loadingKpi = false; this.cdr.markForCheck(); }
  }

  openRegister(): void {
    this.form = { companyName: '', subdomain: '', ownerFirstName: '', ownerLastName: '', ownerEmail: '', ownerPassword: '' };
    this.showRegister = true;
  }

  register(): void {
    this.companyService.register(this.form).subscribe({
      next: () => { this.showRegister = false; this.success = 'Company registered'; this.cdr.markForCheck(); this.load(); this.kpiReady = 0; this.loadKpi(); },
      error: (err) => { this.error = err?.error?.message || 'Failed to register company'; this.cdr.markForCheck(); }
    });
  }

  openPlanChange(c: Company): void {
    this.planTarget = c;
    this.newPlan = c.subscriptionPlan;
    this.onPlanChange(this.newPlan);
    this.planTransactionRef = '';
  }

  // Defaults amount-paid to the plan's catalog price; it stays editable, e.g. for a negotiated discount.
  onPlanChange(planCode: SubscriptionPlan): void {
    this.planAmountPaid = this.plans.find(p => p.code === planCode)?.price ?? 0;
  }

  doChangePlan(): void {
    if (!this.planTarget) return;
    this.companyService.changePlan(
      this.planTarget.id, this.newPlan,
      this.planAmountPaid ?? undefined,
      this.planTransactionRef || undefined
    ).subscribe({
      next: () => { this.planTarget = null; this.success = 'Plan updated'; this.cdr.markForCheck(); this.load(); },
      error: (err) => { this.error = err?.error?.message || 'Failed to change plan'; this.planTarget = null; this.cdr.markForCheck(); }
    });
  }

  openStatusChange(c: Company): void {
    this.statusTarget = c;
    this.newStatus = c.status;
  }

  doChangeStatus(): void {
    if (!this.statusTarget) return;
    this.companyService.changeStatus(this.statusTarget.id, this.newStatus).subscribe({
      next: () => { this.statusTarget = null; this.success = 'Status updated'; this.cdr.markForCheck(); this.load(); this.kpiReady = 0; this.loadKpi(); },
      error: (err) => { this.error = err?.error?.message || 'Failed to change status'; this.statusTarget = null; this.cdr.markForCheck(); }
    });
  }

  doDeactivate(): void {
    if (!this.deactivateTarget) return;
    this.companyService.deactivate(this.deactivateTarget.id).subscribe({
      next: () => { this.deactivateTarget = null; this.success = 'Company deactivated'; this.cdr.markForCheck(); this.load(); this.kpiReady = 0; this.loadKpi(); },
      error: (err) => { this.deactivateTarget = null; this.error = extractErrorMessage(err, 'Cannot deactivate company'); this.cdr.markForCheck(); }
    });
  }

  openImpersonate(c: Company): void {
    this.impersonateTarget = c;
    this.impersonateReason = '';
  }

  doImpersonate(): void {
    if (!this.impersonateTarget || !this.impersonateReason.trim()) return;
    this.impersonating = true;
    this.cdr.markForCheck();
    this.companyService.impersonate(this.impersonateTarget.id, this.impersonateReason.trim()).subscribe({
      next: (res) => {
        this.impersonating = false;
        this.impersonateTarget = null;
        this.auth.startImpersonation(res);
        this.cdr.markForCheck();
      },
      error: (err) => {
        this.impersonating = false;
        this.error = err?.error?.message || 'Failed to access company';
        this.impersonateTarget = null;
        this.cdr.markForCheck();
      }
    });
  }

  goToPage(p: number): void { this.page = p; this.load(); }

  statusClass(status: CompanyStatus): string {
    return {
      PENDING_VERIFICATION: 'text-bg-secondary',
      TRIAL: 'text-bg-warning',
      ACTIVE: 'text-bg-success',
      SUSPENDED: 'text-bg-danger',
      DEACTIVATED: 'text-bg-secondary',
    }[status];
  }

  // Fixed styling for the four legacy codes; any code this map does not know falls back to a neutral badge.
  planClass(plan: SubscriptionPlan): string {
    const classes: Record<string, string> = {
      FREE: 'text-bg-light border',
      STARTER: 'text-bg-info',
      PRO: 'text-bg-primary',
      ENTERPRISE: 'text-bg-dark',
    };
    return classes[plan] || 'text-bg-secondary';
  }
}
