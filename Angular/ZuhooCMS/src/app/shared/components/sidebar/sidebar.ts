import { ChangeDetectorRef, Component } from '@angular/core';
import { RouterLink, RouterLinkActive, Router, NavigationEnd } from '@angular/router';
import { filter } from 'rxjs';
import { AuthService } from '../../../core/services/auth.service';
import { PermissionService, PermissionCode } from '../../../core/services/permission.service';

import { PortalService } from '../../../modules/portal/portal.service';

interface NavGroup { label: string; icon: string; items: NavItem[]; roles?: string[]; }

interface NavItem {
  label: string; link: string; icon: string; roles?: string[]; requiredPermission?: PermissionCode;
    section?: string;
}

@Component({
  selector: 'app-sidebar',
  imports: [RouterLink, RouterLinkActive],
  templateUrl: './sidebar.html',
  styleUrl: './sidebar.scss',
})
export class Sidebar {
  isOwner = false;
  subscriptionPlan = 'FREE';

  expandedGroup: string | null = null;

  searchQuery = '';

  constructor(
    private auth: AuthService,
    private permissions: PermissionService,
    private cdr: ChangeDetectorRef,
    private portalService: PortalService,
    private router: Router,
  ) {

    this.permissions.permissions$.subscribe(() => { this.syncActiveGroup(this.router.url); this.cdr.markForCheck(); });
    this.permissions.catalog$.subscribe(() => this.cdr.markForCheck());
    this.auth.currentUser$.subscribe((user) => {
      this.isOwner = this.auth.hasRole('COMPANY_OWNER');
      if (this.isOwner) {
        this.loadCompanyPlan();
      }
      this.cdr.markForCheck();
    });

      this.syncActiveGroup(this.router.url);
    this.router.events
      .pipe(filter((e) => e instanceof NavigationEnd))
      .subscribe((e) => this.syncActiveGroup((e as NavigationEnd).urlAfterRedirects));
  }

  toggleGroup(label: string): void {

    if (document.body.classList.contains('sidebar-collapsed')) {
      document.body.classList.remove('sidebar-collapsed');
      try {
        localStorage.setItem('sidebar-collapsed', 'false');
      } catch {
      }
      this.expandedGroup = label;
      return;
    }
    this.expandedGroup = this.expandedGroup === label ? null : label;
  }

  isExpanded(label: string): boolean {
    return this.expandedGroup === label;
  }

  get searchResults(): NavItem[] {
    const q = this.searchQuery.trim().toLowerCase();
    if (!q) return [];
    return this.visibleGroups.flatMap((g) => g.items).filter((i) => i.label.toLowerCase().includes(q));
  }

  onSearchInput(value: string): void {
    this.searchQuery = value;
    this.cdr.markForCheck();
  }

  clearSearch(): void {
    this.searchQuery = '';
    this.cdr.markForCheck();
  }


  private syncActiveGroup(url: string): void {
    const active = this.visibleGroups.find((g) => g.items.some((i) => url.startsWith(i.link)));
    if (active && this.expandedGroup !== active.label) {
      this.expandedGroup = active.label;
      this.cdr.markForCheck();
    }
  }


  get showDashboardLink(): boolean {
    if (this.isOwner) return true;
    return !this.auth.hasRole('EMPLOYEE');
  }

  get showEmployeeDashboardLink(): boolean {
    return this.auth.hasRole('EMPLOYEE') && !this.isOwner;
  }


  get showGroupLabels(): boolean {
    return this.isOwner || this.auth.hasAnyRole(['SUPER_ADMIN', 'SYSTEM_ADMIN']);
  }

  /** Every permitted item, group structure discarded. Used when showGroupLabels is false. */
  get flatItems(): NavItem[] {
    return this.visibleGroups.flatMap((g) => g.items);
  }

  loadCompanyPlan(): void {
    this.portalService.getMyCompany().subscribe({
      next: (c: any) => {
        this.subscriptionPlan = c.subscriptionPlan || 'FREE';
        this.cdr.markForCheck();
      },
      error: () => {
        this.subscriptionPlan = 'FREE';
        this.cdr.markForCheck();
      }
    });
  }

  private get dashboardGroup(): NavGroup {
    const items: NavItem[] = [];
    if (this.showDashboardLink) {
      items.push({ label: 'Overview', link: '/dashboard', icon: 'bi-grid-1x2' });
    }
    if (this.showEmployeeDashboardLink) {
      items.push({ label: 'My Dashboard', link: '/employee-dashboard', icon: 'bi-person-workspace' });
    }
    items.push({ label: 'CRM', link: '/crm/dashboard', icon: 'bi-graph-up-arrow', requiredPermission: 'OPPORTUNITY_VIEW' });
    items.push({ label: 'Human Resources', link: '/hrm/dashboard', icon: 'bi-people', requiredPermission: 'EMPLOYEE_VIEW' });
    items.push({ label: 'Payroll', link: '/hrm/payroll-dashboard', icon: 'bi-cash-stack', requiredPermission: 'PAYROLL_VIEW' });
    items.push({ label: 'Finance', link: '/finance/dashboard', icon: 'bi-cash-coin', requiredPermission: 'FINANCIAL_REPORT_VIEW' });
    return { label: 'Dashboards', icon: 'bi-speedometer2', items };
  }

  get visibleGroups(): NavGroup[] {
    return [this.dashboardGroup, ...this.groups]
      .filter(g => !g.roles || this.auth.hasAnyRole(g.roles))
      .map(g => ({
        ...g,
        items: g.items.filter(i =>
          (!i.roles || this.auth.hasAnyRole(i.roles)) &&
          this.permissions.hasPermission(i.requiredPermission),
        ),
      }))
      .filter(g => g.items.length > 0);
  }


  groups: NavGroup[] = [
    {
      label: 'CRM',
      icon: 'bi-graph-up-arrow',
      items: [
        { section: 'Sales', label: 'Leads', link: '/crm/leads', icon: 'bi-person-plus', requiredPermission: 'LEAD_VIEW' },
        { section: 'Sales', label: 'Opportunities', link: '/crm/pipeline', icon: 'bi-kanban', requiredPermission: 'OPPORTUNITY_VIEW' },
        { section: 'Sales', label: 'Clients', link: '/crm/clients', icon: 'bi-building', requiredPermission: 'CLIENT_VIEW' },
        { section: 'Sales', label: 'Contacts', link: '/crm/contacts', icon: 'bi-person-lines-fill', requiredPermission: 'CONTACT_VIEW' },
        { section: 'Analytics', label: 'Reports', link: '/crm/pipeline/reports', icon: 'bi-bar-chart', requiredPermission: 'OPPORTUNITY_VIEW' },
        { section: 'Sales', label: 'Client Chat', link: '/support/client-chat', icon: 'bi-headset', requiredPermission: 'SUPPORT_MESSAGE_VIEW' },
      ]
    },
    {
      label: 'Company Services',
      icon: 'bi-briefcase',
      items: [
        { section: 'Catalog', label: 'Categories', link: '/servicedesk/categories', icon: 'bi-tags', requiredPermission: 'SERVICE_CATEGORY_VIEW' },
        { section: 'Catalog', label: 'Services', link: '/servicedesk/services', icon: 'bi-bell-fill', requiredPermission: 'SERVICE_CATALOG_VIEW' },
        { section: 'Catalog', label: 'Packages', link: '/servicedesk/packages', icon: 'bi-box-seam', requiredPermission: 'SERVICE_PACKAGE_VIEW' },
        { section: 'Catalog', label: 'Templates', link: '/servicedesk/templates', icon: 'bi-file-earmark-ruled', requiredPermission: 'SERVICE_TEMPLATE_VIEW' },
        { section: 'Operations', label: 'Requests', link: '/servicedesk/requests', icon: 'bi-ticket', requiredPermission: 'SERVICE_REQUEST_VIEW' },
        { section: 'Operations', label: 'Approvals', link: '/servicedesk/approvals', icon: 'bi-clipboard-check', requiredPermission: 'SERVICE_REQUEST_APPROVE' },
        { section: 'Automation', label: 'Workflows', link: '/servicedesk/workflows', icon: 'bi-diagram-2', requiredPermission: 'WORKFLOW_VIEW' },
        { section: 'Knowledge', label: 'Knowledge Base', link: '/servicedesk/kb', icon: 'bi-journal-text', requiredPermission: 'KNOWLEDGE_BASE_VIEW' },
        { section: 'Analytics', label: 'Reviews', link: '/servicedesk/reviews', icon: 'bi-star', requiredPermission: 'REVIEW_VIEW' },
      ]
    },
    {
      label: 'Human Resources',
      icon: 'bi-people',
      items: [
        { label: 'Employees', link: '/hrm/employees', icon: 'bi-person-vcard', requiredPermission: 'EMPLOYEE_VIEW' },
        { label: 'Departments', link: '/hrm/departments', icon: 'bi-diagram-3', requiredPermission: 'DEPARTMENT_VIEW' },
        { label: 'Designations', link: '/hrm/designations', icon: 'bi-award', requiredPermission: 'DESIGNATION_VIEW' },
        { label: 'Shifts', link: '/hrm/shifts', icon: 'bi-clock-history', requiredPermission: 'SHIFT_VIEW' },
        { label: 'HR Expenses', link: '/hrm/expenses', icon: 'bi-receipt-cutoff', requiredPermission: 'EXPENSE_VIEW' },
        { label: 'Performance', link: '/hrm/performance', icon: 'bi-graph-up', requiredPermission: 'PERFORMANCE_VIEW' },
        { label: 'Letters', link: '/hrm/letters', icon: 'bi-envelope-paper', requiredPermission: 'LETTER_VIEW' },
      ]
    },
    {
      label: 'Recruitment',
      icon: 'bi-person-plus',
      items: [
        { section: 'Recruiting', label: 'Reports & KPIs', link: '/hrm/recruitment-reports', icon: 'bi-bar-chart-line', requiredPermission: 'RECRUITMENT_REPORT_VIEW' },
        { section: 'Recruiting', label: 'Job Postings', link: '/hrm/job-postings', icon: 'bi-briefcase', requiredPermission: 'JOB_POSTING_VIEW' },
        { section: 'Recruiting', label: 'Candidates', link: '/hrm/candidates', icon: 'bi-people-fill', requiredPermission: 'APPLICATION_VIEW' },
        { section: 'Recruiting', label: 'Applications', link: '/hrm/applications', icon: 'bi-person-lines-fill', requiredPermission: 'APPLICATION_VIEW' },
        { section: 'Recruiting', label: 'Pipeline', link: '/hrm/pipeline', icon: 'bi-kanban', requiredPermission: 'APPLICATION_VIEW' },
        { section: 'Recruiting', label: 'Interviews', link: '/hrm/interviews', icon: 'bi-camera-video', requiredPermission: 'APPLICATION_VIEW' },
        { section: 'Recruiting', label: 'Offers', link: '/hrm/offers', icon: 'bi-envelope-check', requiredPermission: 'APPLICATION_VIEW' },
        { section: 'Recruiting', label: 'Talent Pool', link: '/hrm/talent-pool', icon: 'bi-people', requiredPermission: 'APPLICATION_VIEW' },
        { section: 'Public', label: 'Career Page', link: '/hrm/career-page', icon: 'bi-globe2', requiredPermission: 'JOB_POSTING_VIEW' },
      ]
    },
    {
      label: 'Time & Leave',
      icon: 'bi-calendar2-check',
      items: [
        { section: 'Attendance', label: 'Attendance', link: '/attendance/records', icon: 'bi-calendar-check', requiredPermission: 'ATTENDANCE_VIEW' },
        { section: 'Attendance', label: 'Timesheets', link: '/attendance/timesheets', icon: 'bi-clock', requiredPermission: 'TIMESHEET_VIEW' },
        { section: 'Attendance', label: 'Shift Assignments', link: '/attendance/shift-assignments', icon: 'bi-person-badge', requiredPermission: 'SHIFT_ASSIGNMENT_VIEW' },
        { section: 'Attendance', label: 'Biometric Data', link: '/attendance/biometric-data', icon: 'bi-fingerprint', requiredPermission: 'BIOMETRIC_VIEW' },
        { section: 'Leave', label: 'Leave Requests', link: '/hrm/leaves', icon: 'bi-calendar-minus', requiredPermission: 'LEAVE_VIEW' },
        { section: 'Leave', label: 'Leave Balances', link: '/hrm/leave-balances', icon: 'bi-hourglass-split', requiredPermission: 'LEAVE_BALANCE_VIEW' },
        { section: 'Leave', label: 'Leave Policies', link: '/hrm/leave-policies', icon: 'bi-shield-check', requiredPermission: 'LEAVE_POLICY_VIEW' },
        { section: 'Leave', label: 'Holidays', link: '/hrm/holidays', icon: 'bi-calendar-event', requiredPermission: 'HOLIDAY_VIEW' },
        { section: 'Analytics', label: 'Reports', link: '/attendance/reports', icon: 'bi-file-earmark-bar-graph', requiredPermission: 'ATTENDANCE_VIEW' },
      ]
    },
    {
      label: 'Payroll',
      icon: 'bi-cash-stack',
      items: [
        { label: 'Salary Structures', link: '/hrm/salary-structures', icon: 'bi-wallet2', requiredPermission: 'SALARY_STRUCTURE_VIEW' },
        { label: 'Employee Salaries', link: '/hrm/employee-salaries', icon: 'bi-person-badge', requiredPermission: 'SALARY_STRUCTURE_VIEW' },
        { label: 'Payroll Runs', link: '/hrm/payroll', icon: 'bi-cash-coin', requiredPermission: 'PAYROLL_VIEW' },
        { label: 'Loans & Advances', link: '/hrm/loans-advances', icon: 'bi-piggy-bank', requiredPermission: 'PAYROLL_VIEW' },
        { label: 'Salary Sheet', link: '/hrm/salary-sheet', icon: 'bi-table', requiredPermission: 'PAYROLL_VIEW' },
        { label: 'Payslips', link: '/hrm/my-payslips', icon: 'bi-receipt' },
      ]
    },
    {
      label: 'Billing',
      icon: 'bi-receipt',
      items: [
        { label: 'Invoices', link: '/finance/invoices', icon: 'bi-receipt', requiredPermission: 'INVOICE_VIEW' },
        { label: 'Payment Receipts', link: '/finance/payment-receipts', icon: 'bi-receipt-cutoff', requiredPermission: 'PAYMENT_RECEIPT_VIEW' },
        { label: 'Refunds', link: '/finance/refunds', icon: 'bi-arrow-counterclockwise', requiredPermission: 'INVOICE_VIEW' },
        { label: 'Vendors', link: '/finance/vendors', icon: 'bi-shop', requiredPermission: 'VENDOR_VIEW' },
        { label: 'Vendor Bills', link: '/finance/vendor-bills', icon: 'bi-file-earmark-text', requiredPermission: 'VENDOR_BILL_VIEW' },
      ]
    },
    {
      label: 'Accounting',
      icon: 'bi-journal-bookmark',
      items: [
        { label: 'Chart of Accounts', link: '/finance/coa', icon: 'bi-journal-bookmark', requiredPermission: 'CHART_OF_ACCOUNT_VIEW' },
        { label: 'Journal Entries', link: '/finance/journal-entries', icon: 'bi-journal-plus', requiredPermission: 'JOURNAL_ENTRY_VIEW' },
        { label: 'General Ledger', link: '/finance/general-ledger', icon: 'bi-journal-text', requiredPermission: 'GENERAL_LEDGER_VIEW' },
        { label: 'Fiscal Years', link: '/finance/fiscal-years', icon: 'bi-calendar3', requiredPermission: 'ACCOUNTING_PERIOD_VIEW' },
        { label: 'Accounting Periods', link: '/finance/accounting-periods', icon: 'bi-calendar-check', requiredPermission: 'ACCOUNTING_PERIOD_VIEW' },
        { label: 'Reports', link: '/finance/reports', icon: 'bi-bar-chart', requiredPermission: 'FINANCIAL_REPORT_VIEW' },
      ]
    },
    {
      label: 'Banking',
      icon: 'bi-piggy-bank',
      items: [
        { label: 'Expenses', link: '/finance/expenses', icon: 'bi-cash-stack', requiredPermission: 'EXPENSE_VIEW' },
        { label: 'Budgets', link: '/finance/budgets', icon: 'bi-piggy-bank', requiredPermission: 'BUDGET_VIEW' },
        { label: 'Wallet', link: '/finance/wallet', icon: 'bi-wallet2', requiredPermission: 'WALLET_VIEW' },
        { label: 'Bank Reconciliation', link: '/finance/bank-reconciliation', icon: 'bi-bank', requiredPermission: 'BANK_RECONCILIATION_VIEW' },
        { label: 'Fixed Assets', link: '/finance/fixed-assets', icon: 'bi-pc-display-horizontal', requiredPermission: 'FIXED_ASSET_VIEW' },
      ]
    },
    {
      label: 'IT Assets',
      icon: 'bi-pc-display',
      items: [
        { label: 'Hardware', link: '/itam/hardware', icon: 'bi-laptop', requiredPermission: 'HARDWARE_VIEW' },
        { label: 'Software', link: '/itam/software', icon: 'bi-file-earmark-code', requiredPermission: 'SOFTWARE_LICENSE_VIEW' },
        { label: 'Assignments', link: '/itam/assignments', icon: 'bi-clipboard-data', requiredPermission: 'ASSET_ASSIGNMENT_VIEW' },
        { label: 'Offboarding', link: '/itam/offboarding', icon: 'bi-person-x', requiredPermission: 'OFFBOARDING_VIEW' },
        { label: 'Bulk Import', link: '/itam/import', icon: 'bi-upload', requiredPermission: 'ASSET_IMPORT_VIEW' },
      ]
    },
    {
      label: 'Administration',
      icon: 'bi-gear',
      items: [
        { section: 'User Management', label: 'Users', link: '/users', icon: 'bi-people', requiredPermission: 'USER_VIEW' },
        { section: 'User Management', label: 'Roles & Permissions', link: '/roles-permissions', icon: 'bi-shield-lock', roles: ['COMPANY_OWNER'] },
        { section: 'Organization', label: 'Company Profile', link: '/finance/company-settings', icon: 'bi-building-gear', requiredPermission: 'COMPANY_SETTINGS' },
        { section: 'Organization', label: 'Announcements', link: '/hrm/announcements', icon: 'bi-megaphone', requiredPermission: 'ANNOUNCEMENT_VIEW' },
        { section: 'Subscription', label: 'Plans & Upgrade', link: '/subscriptionPlan', icon: 'bi-gem', roles: ['COMPANY_OWNER'] },
        { section: 'AI', label: 'AI Settings', link: '/ai/settings', icon: 'bi-stars', requiredPermission: 'AI_ADMIN' },
        { section: 'Security', label: 'Change Password', link: '/account/password', icon: 'bi-key' },
        { section: 'Security', label: 'Change Email', link: '/account/email', icon: 'bi-envelope-at' },
        { section: 'System', label: 'Audit Logs', link: '/support/audit-logs', icon: 'bi-shield-check', requiredPermission: 'AUDIT_LOG_VIEW' },
        { section: 'System', label: 'Platform Support', link: '/support/messages', icon: 'bi-life-preserver', requiredPermission: 'SUPPORT_MESSAGE_VIEW' },
      ]
    },
  ];
}
