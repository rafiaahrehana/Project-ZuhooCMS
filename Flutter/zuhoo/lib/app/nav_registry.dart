import 'package:flutter/material.dart';

import '../core/auth/auth_models.dart';
import '../core/auth/permission_controller.dart';
import '../features/approvals/approval_repository.dart' show canSeeApprovalInbox;
import '../features/accounting/accounting_models.dart' show AccountingPermissions;
import '../features/accounting/reconciliation_models.dart'
    show ReconciliationPermissions;
import '../features/admin/admin_models.dart';
import '../features/ai/ai_models.dart' show AiPermissions;
import '../features/assets_periods/assets_periods_models.dart'
    show ClosingPermissions;
import '../features/attendance/attendance_models.dart'
    show AttendanceAdminPermissions, AttendancePermissions;
import '../features/biometric/biometric_models.dart' show BiometricPermissions;
import '../features/budgets/budget_models.dart' show BudgetPermissions;
import '../features/catalogue/catalogue_models.dart' show CataloguePermissions;
import '../features/company/company_models.dart' show CompanyPermissions;
import '../features/crm/crm_models.dart' show CrmPermissions;
import '../features/directory/directory_models.dart' show DirectoryPermissions;
import '../features/finance/finance_models.dart' show FinancePermissions;
import '../features/hrpolicy/hrpolicy_models.dart' show HrPolicyPermissions;
import '../features/itam/itam_models.dart' show ItamPermissions;
import '../features/kb/kb_models.dart' show KbPermissions;
import '../features/leave/leave_models.dart' show LeavePermissions;
import '../features/payables/payables_models.dart' show PayablesPermissions;
import '../features/payslips/payslip_models.dart' show PayrollPermissions;
import '../features/performance/performance_models.dart'
    show PerformancePermissions;
import '../features/platform/platform_models.dart' show platformUserRoles;
import '../features/receivables/receivables_models.dart'
    show ReceivablesPermissions;
import '../features/recruitment/recruitment_models.dart'
    show RecruitmentPermissions;
import '../features/requests/request_models.dart' show RequestPermissions;
import '../features/salary/salary_models.dart' show SalaryPermissions;
import '../features/support/support_models.dart' show SupportPermissions;
import '../features/support_admin/support_admin_models.dart';
import '../features/workflow/workflow_models.dart' show WorkflowPermissions;
import 'router.dart';

/// Who is allowed to see a [NavDestination] or [NavGroup].
///
/// Mirrors Angular sidebar's own item-level `roles`/`requiredPermission`
/// checks, so a group built from this table behaves the same as the web
/// app's for the same account: a permission code, any-of a list of codes,
/// one of a list of roles, a hand-written rule for the handful of items
/// whose visibility depends on more than one thing at once (Angular's
/// `isOwner || !hasRole('EMPLOYEE')` for the dashboard split), or always.
enum _NavGateKind { always, anyPermission, role, custom }

class NavGate {
  const NavGate.always()
      : _kind = _NavGateKind.always,
        _codes = const [],
        _singleCode = null,
        _roles = const [],
        _test = null;

  const NavGate.permission(String code)
      : _kind = _NavGateKind.anyPermission,
        _codes = const [],
        _singleCode = code,
        _roles = const [],
        _test = null;

  const NavGate.anyPermission(List<String> codes)
      : _kind = _NavGateKind.anyPermission,
        _codes = codes,
        _singleCode = null,
        _roles = const [],
        _test = null;

  const NavGate.role(List<String> roles)
      : _kind = _NavGateKind.role,
        _codes = const [],
        _singleCode = null,
        _roles = roles,
        _test = null;

  /// Escape hatch for gates that are not a plain permission-or-role check —
  /// e.g. "owner, or anyone who is not a plain employee".
  const NavGate.custom(bool Function(AppUser? user, PermissionState perms) test)
      : _kind = _NavGateKind.custom,
        _codes = const [],
        _singleCode = null,
        _roles = const [],
        _test = test;

  final _NavGateKind _kind;
  final List<String> _codes;
  final String? _singleCode;
  final List<String> _roles;
  final bool Function(AppUser? user, PermissionState perms)? _test;

  bool allows(AppUser? user, PermissionState perms) {
    switch (_kind) {
      case _NavGateKind.always:
        return true;
      case _NavGateKind.anyPermission:
        return _singleCode != null ? perms.has(_singleCode) : perms.hasAny(_codes);
      case _NavGateKind.role:
        return user?.hasAnyRole(_roles) ?? false;
      case _NavGateKind.custom:
        return _test!(user, perms);
    }
  }
}

/// One destination inside a [NavGroup] — a screen, or a specific tab of one.
class NavDestination {
  const NavDestination({
    required this.label,
    required this.icon,
    required this.path,
    this.gate = const NavGate.always(),
    this.push = true,
    this.initialTabLabel,
  });

  final String label;
  final IconData icon;
  final String path;
  final NavGate gate;

  /// Whether opening this stacks on top of the current tab (`push`) or
  /// switches which bottom-nav branch is selected (`go`) — same convention
  /// `home_screen.dart`'s quick actions already use.
  final bool push;

  /// Lands the destination screen on a specific tab instead of its first —
  /// e.g. several rows all point at `Routes.crm` but each opens a different
  /// tab. Requires the target screen to accept an `initialTabLabel`
  /// constructor parameter; screens that don't yet (see the nav-parity plan's
  /// Phase 1 hub-screen changes) simply ignore it and open on their default
  /// tab until they're updated.
  final String? initialTabLabel;
}

/// A sidebar/drawer section — Angular's accordion groups, one-to-one.
class NavGroup {
  const NavGroup({
    required this.label,
    required this.icon,
    required this.items,
    this.gate = const NavGate.always(),
  });

  final String label;
  final IconData icon;
  final List<NavDestination> items;
  final NavGate gate;
}

/// Grouped-vs-flat rule from Angular's `showGroupLabels`: the accordion (with
/// per-group headers) is for company owners and the two platform admin roles
/// specifically — `isOwner || hasAnyRole(['SUPER_ADMIN', 'SYSTEM_ADMIN'])`.
/// Everyone else, a plain employee **and every other kind of platform staff**
/// (support, sales, marketing, platform accounting), gets every visible item
/// in one flat list, no grouping. [AppUser.isPlatformStaff] is deliberately
/// not used here — it is the broader set that also decides which *groups* to
/// drop entirely below, not this narrower one Angular checks for the
/// accordion.
bool showGroupedNav(AppUser? user) =>
    (user?.isCompanyOwner ?? false) ||
    (user?.hasAnyRole(['SUPER_ADMIN', 'SYSTEM_ADMIN']) ?? false);

/// The full table, gated for [user]/[perms] and with empty groups dropped.
///
/// This is the single source [AppDrawer] and Home's Quick Actions both read
/// from — neither may keep its own copy of this list, or the two will drift
/// again the way they did before this file existed.
List<NavGroup> buildNavGroups(
  AppUser? user,
  PermissionState perms, {
  bool includeAllForRouteCheck = false,
}) {
  final isPlatformOnly =
      includeAllForRouteCheck ? false : (user?.isPlatformStaff ?? false);

  bool itemVisible(NavDestination item) =>
      includeAllForRouteCheck || item.gate.allows(user, perms);

  List<NavDestination> filterItems(List<NavDestination> items) =>
      includeAllForRouteCheck ? items : items.where(itemVisible).toList();

  final groups = <NavGroup>[
    NavGroup(
      label: 'Dashboards',
      icon: Icons.dashboard_outlined,
      items: filterItems([
        NavDestination(
          label: 'Approvals',
          icon: Icons.fact_check_outlined,
          path: Routes.approvals,
          gate: NavGate.custom((u, p) => canSeeApprovalInbox(p)),
        ),
        NavDestination(
          label: 'Overview',
          icon: Icons.insights_outlined,
          path: Routes.dashboard,
          gate: NavGate.custom(
            (u, p) =>
                (u?.isCompanyOwner ?? false) || !(u?.hasRole('EMPLOYEE') ?? false),
          ),
        ),
        NavDestination(
          label: 'My Dashboard',
          icon: Icons.person_outline_rounded,
          path: Routes.dashboard,
          gate: NavGate.custom(
            (u, p) =>
                (u?.hasRole('EMPLOYEE') ?? false) && !(u?.isCompanyOwner ?? false),
          ),
        ),
        const NavDestination(
          label: 'CRM',
          icon: Icons.trending_up_rounded,
          path: Routes.crm,
          gate: NavGate.permission(CrmPermissions.opportunityView),
        ),
        const NavDestination(
          label: 'Human Resources',
          icon: Icons.groups_2_outlined,
          path: Routes.directory,
          gate: NavGate.permission(DirectoryPermissions.employeeView),
        ),
        const NavDestination(
          label: 'Payroll',
          icon: Icons.request_quote_outlined,
          path: Routes.payroll,
          gate: NavGate.permission(PayrollPermissions.view),
        ),
        const NavDestination(
          label: 'Finance',
          icon: Icons.account_balance_wallet_outlined,
          path: Routes.finance,
          gate: NavGate.permission(FinancePermissions.reportView),
        ),
        const NavDestination(
          label: 'The platform',
          icon: Icons.public_outlined,
          path: Routes.platformDashboard,
          gate: NavGate.role([
            'SUPER_ADMIN',
            'SYSTEM_ADMIN',
            'SUPPORT_AGENT',
            'SUPPORT_MANAGER',
            'MARKETING_MANAGER',
            'PLATFORM_ACCOUNTANT',
            'SALES_MANAGER',
          ]),
        ),
        // Angular's Platform Admin area is a wholly separate nav with seven
        // flat items (Companies, Platform Users, Custom Roles, Feature
        // Flags, Locations, Platform Expenses, Subscription Management) —
        // this mirrors most of that list, landing each on the matching tab
        // of the one PlatformScreen hub rather than a screen per item.
        // Two are deliberately absent: Custom Roles, because it and the
        // tenant "Roles & Permissions" hit the identical `/custom-roles`
        // endpoint, so AdminScreen's Roles tab already covers it in full
        // once impersonating the company in question; and Platform
        // Expenses, kept off this nav on purpose — the Expenses tab itself
        // is still on PlatformScreen for whoever lands there some other way.
        NavDestination(
          label: 'Companies',
          icon: Icons.business_outlined,
          path: Routes.platform,
          initialTabLabel: 'Companies',
          gate: NavGate.custom((u, p) => u?.isPlatformStaff ?? false),
        ),
        NavDestination(
          label: 'Platform Users',
          icon: Icons.admin_panel_settings_outlined,
          path: Routes.platform,
          initialTabLabel: 'Staff',
          gate: NavGate.role(platformUserRoles),
        ),
        NavDestination(
          label: 'Feature Flags',
          icon: Icons.toggle_on_outlined,
          path: Routes.platform,
          initialTabLabel: 'Flags',
          gate: NavGate.custom((u, p) => u?.isPlatformStaff ?? false),
        ),
        NavDestination(
          label: 'Locations',
          icon: Icons.map_outlined,
          path: Routes.platformLocations,
          gate: NavGate.role(platformUserRoles),
        ),
        NavDestination(
          label: 'Subscription Management',
          icon: Icons.workspace_premium_outlined,
          path: Routes.plans,
          gate: NavGate.role(platformUserRoles),
        ),
      ]),
    ),
    if (!isPlatformOnly)
      NavGroup(
        label: 'CRM',
        icon: Icons.trending_up_rounded,
        items: filterItems(const [
          NavDestination(
            label: 'Leads',
            icon: Icons.person_search_outlined,
            path: Routes.crm,
            initialTabLabel: 'Leads',
            gate: NavGate.permission(CrmPermissions.leadView),
          ),
          NavDestination(
            label: 'Opportunities',
            icon: Icons.trending_up_rounded,
            path: Routes.crm,
            initialTabLabel: 'Pipeline',
            gate: NavGate.permission(CrmPermissions.opportunityView),
          ),
          NavDestination(
            label: 'Clients',
            icon: Icons.handshake_outlined,
            path: Routes.crm,
            initialTabLabel: 'Clients',
            gate: NavGate.permission(CrmPermissions.clientView),
          ),
          NavDestination(
            label: 'Contacts',
            icon: Icons.contacts_outlined,
            path: Routes.contacts,
            gate: NavGate.anyPermission([
              CrmPermissions.contactView,
              CrmPermissions.tagView,
            ]),
          ),
          NavDestination(
            label: 'Reports',
            icon: Icons.query_stats_outlined,
            path: Routes.crmReports,
            gate: NavGate.permission(CrmPermissions.opportunityView),
          ),
          NavDestination(
            label: 'Client Chat',
            icon: Icons.forum_outlined,
            path: Routes.support,
            initialTabLabel: 'Client chat',
            gate: NavGate.permission(SupportPermissions.ticketView),
          ),
        ]),
      ),
    if (!isPlatformOnly)
      NavGroup(
        label: 'Company Services',
        icon: Icons.support_agent_rounded,
        items: filterItems([
          NavDestination(
            label: 'Categories',
            icon: Icons.category_outlined,
            path: Routes.admin,
            initialTabLabel: 'Categories',
            gate: NavGate.permission(AdminPermissions.serviceCategoryView),
          ),
          NavDestination(
            label: 'Services',
            icon: Icons.local_offer_outlined,
            path: Routes.catalogue,
            initialTabLabel: 'Services',
            gate: NavGate.permission(CataloguePermissions.serviceView),
          ),
          NavDestination(
            label: 'Packages',
            icon: Icons.inventory_2_outlined,
            path: Routes.catalogue,
            initialTabLabel: 'Packages',
            gate: NavGate.permission(CataloguePermissions.packageView),
          ),
          NavDestination(
            label: 'Templates',
            icon: Icons.description_outlined,
            path: Routes.catalogue,
            initialTabLabel: 'Templates',
            gate: NavGate.permission(CataloguePermissions.templateView),
          ),
          NavDestination(
            label: 'Requests',
            icon: Icons.assignment_outlined,
            path: Routes.requests,
            gate: NavGate.permission(RequestPermissions.view),
          ),
          NavDestination(
            label: 'Approvals',
            icon: Icons.fact_check_outlined,
            path: Routes.requests,
            initialTabLabel: 'Approvals',
            gate: NavGate.permission(RequestPermissions.approve),
          ),
          NavDestination(
            label: 'Workflows',
            icon: Icons.account_tree_outlined,
            path: Routes.workflows,
            gate: NavGate.permission(WorkflowPermissions.view),
          ),
          NavDestination(
            label: 'Knowledge Base',
            icon: Icons.menu_book_outlined,
            path: Routes.kb,
            gate: NavGate.permission(KbPermissions.view),
          ),
          NavDestination(
            label: 'Articles',
            icon: Icons.article_outlined,
            path: Routes.kbAuthoring,
            gate: NavGate.anyPermission([KbPermissions.create, KbPermissions.update]),
          ),
          NavDestination(
            label: 'Reviews',
            icon: Icons.star_border_rounded,
            path: Routes.reviews,
            gate: NavGate.permission(RequestPermissions.reviewView),
          ),
          NavDestination(
            label: 'Support',
            icon: Icons.support_agent_rounded,
            path: Routes.support,
          ),
          NavDestination(
            label: 'Support desk',
            icon: Icons.headset_mic_outlined,
            path: Routes.supportAdmin,
            gate: NavGate.role([
              ...supportAgentAdminRoles,
              ...supportCategoryAdminRoles,
              ...slaAdminRoles,
              ...supportAuditRoles,
            ]),
          ),
          NavDestination(
            label: 'The queue',
            icon: Icons.support_agent_outlined,
            path: Routes.supportQueue,
            gate: NavGate.role(['SUPPORT_AGENT', ...supportAgentAdminRoles]),
          ),
          NavDestination(
            label: 'Ask AI',
            icon: Icons.auto_awesome_outlined,
            path: Routes.ai,
            gate: NavGate.permission(AiPermissions.chat),
          ),
        ]),
      ),
    if (!isPlatformOnly)
      NavGroup(
        label: 'Human Resources',
        icon: Icons.people_outline_rounded,
        items: filterItems(const [
          NavDestination(
            label: 'Employees',
            icon: Icons.groups_2_outlined,
            path: Routes.directory,
            gate: NavGate.permission(DirectoryPermissions.employeeView),
          ),
          NavDestination(
            label: 'Departments',
            icon: Icons.apartment_outlined,
            path: Routes.admin,
            initialTabLabel: 'Departments',
            gate: NavGate.permission(AdminPermissions.departmentView),
          ),
          NavDestination(
            label: 'Designations',
            icon: Icons.badge_outlined,
            path: Routes.admin,
            initialTabLabel: 'Grades',
            gate: NavGate.permission(AdminPermissions.designationView),
          ),
          NavDestination(
            label: 'Shifts',
            icon: Icons.schedule_outlined,
            path: Routes.hrPolicy,
            initialTabLabel: 'Shifts',
            gate: NavGate.permission(HrPolicyPermissions.shiftView),
          ),
          // Same tab as Banking's "Expenses" — Angular links it a second
          // time from here under its own EXPENSE_VIEW gate too, one page
          // that filters to "mine"/"pending"/"all" rather than Angular's two
          // separate ones for the employee-reimbursement and company-wide
          // views.
          NavDestination(
            label: 'HR Expenses',
            icon: Icons.payments_outlined,
            path: Routes.finance,
            initialTabLabel: 'Expenses',
            gate: NavGate.permission(FinancePermissions.expenseView),
          ),
          NavDestination(
            label: 'Performance',
            icon: Icons.insights_outlined,
            path: Routes.performance,
            gate: NavGate.permission(PerformancePermissions.view),
          ),
          NavDestination(
            label: 'Letters',
            icon: Icons.description_outlined,
            path: Routes.hrPolicy,
            initialTabLabel: 'Letters',
            gate: NavGate.permission(HrPolicyPermissions.letterView),
          ),
          NavDestination(
            label: 'Who is in',
            icon: Icons.groups_outlined,
            path: Routes.teamAttendance,
            gate: NavGate.permission(AttendanceAdminPermissions.view),
          ),
          NavDestination(
            label: 'Company setup',
            icon: Icons.tune_rounded,
            path: Routes.admin,
            gate: NavGate.anyPermission([
              AdminPermissions.departmentView,
              AdminPermissions.designationView,
              AdminPermissions.announcementView,
              AdminPermissions.serviceCategoryView,
            ]),
          ),
          NavDestination(
            label: 'HR rules',
            icon: Icons.rule_folder_outlined,
            path: Routes.hrPolicy,
            gate: NavGate.anyPermission([
              HrPolicyPermissions.holidayView,
              HrPolicyPermissions.policyView,
              HrPolicyPermissions.shiftView,
              HrPolicyPermissions.letterView,
            ]),
          ),
          NavDestination(
            label: 'Entitlements',
            icon: Icons.event_available_outlined,
            path: Routes.entitlements,
            gate: NavGate.permission(LeavePermissions.balanceView),
          ),
        ]),
      ),
    if (!isPlatformOnly)
      NavGroup(
        label: 'Recruitment',
        icon: Icons.work_outline_rounded,
        items: filterItems(const [
          NavDestination(
            label: 'Reports & KPIs',
            icon: Icons.query_stats_outlined,
            path: Routes.recruitmentReports,
            gate: NavGate.permission(RecruitmentPermissions.reportView),
          ),
          NavDestination(
            label: 'Job Postings',
            icon: Icons.work_outline_rounded,
            path: Routes.recruitment,
            initialTabLabel: 'Jobs',
            gate: NavGate.permission(RecruitmentPermissions.jobView),
          ),
          NavDestination(
            label: 'Candidates',
            icon: Icons.person_search_outlined,
            path: Routes.recruitment,
            initialTabLabel: 'Candidates',
            gate: NavGate.permission(RecruitmentPermissions.applicationView),
          ),
          NavDestination(
            label: 'Applications',
            icon: Icons.assignment_ind_outlined,
            path: Routes.recruitment,
            initialTabLabel: 'Applicants',
            gate: NavGate.permission(RecruitmentPermissions.applicationView),
          ),
          // Angular's kanban board over the same applications the
          // "Applicants" tab already lists flat — no separate board widget
          // exists here, so this deep-links to the same tab rather than a
          // screen that would just be "Applications" a second time.
          NavDestination(
            label: 'Pipeline',
            icon: Icons.view_kanban_outlined,
            path: Routes.recruitment,
            initialTabLabel: 'Applicants',
            gate: NavGate.permission(RecruitmentPermissions.applicationView),
          ),
          NavDestination(
            label: 'Interviews',
            icon: Icons.event_available_outlined,
            path: Routes.recruitment,
            initialTabLabel: 'Interviews',
            gate: NavGate.permission(RecruitmentPermissions.applicationView),
          ),
          NavDestination(
            label: 'Offers',
            icon: Icons.local_offer_outlined,
            path: Routes.recruitment,
            initialTabLabel: 'Offers',
            gate: NavGate.permission(RecruitmentPermissions.applicationView),
          ),
          NavDestination(
            label: 'Talent Pool',
            icon: Icons.groups_2_outlined,
            path: Routes.recruitment,
            initialTabLabel: 'Talent pool',
            gate: NavGate.permission(RecruitmentPermissions.applicationView),
          ),
          NavDestination(
            label: 'Career Page',
            icon: Icons.public_outlined,
            path: Routes.careerPage,
            gate: NavGate.permission(RecruitmentPermissions.jobView),
          ),
        ]),
      ),
    if (!isPlatformOnly)
      NavGroup(
        label: 'Time & Leave',
        icon: Icons.event_available_outlined,
        items: filterItems(const [
          NavDestination(
            label: 'My attendance',
            icon: Icons.history_rounded,
            path: Routes.attendance,
            push: false,
          ),
          NavDestination(
            label: 'Timesheets',
            icon: Icons.receipt_long_outlined,
            path: Routes.attendance,
            initialTabLabel: 'Timesheets',
            push: false,
            gate: NavGate.permission(AttendanceAdminPermissions.timesheetView),
          ),
          NavDestination(
            label: 'Shift Assignments',
            icon: Icons.event_repeat_outlined,
            path: Routes.shiftRoster,
            gate: NavGate.permission(AttendancePermissions.shiftAssignmentView),
          ),
          NavDestination(
            label: 'Biometric Data',
            icon: Icons.fingerprint_rounded,
            path: Routes.biometric,
            gate: NavGate.permission(BiometricPermissions.view),
          ),
          NavDestination(
            label: 'Leave Requests',
            icon: Icons.event_note_rounded,
            path: Routes.leave,
            push: false,
            gate: NavGate.permission(LeavePermissions.view),
          ),
          NavDestination(
            label: 'Leave Balances',
            icon: Icons.event_available_outlined,
            path: Routes.leave,
            initialTabLabel: 'Balances',
            push: false,
            gate: NavGate.permission(LeavePermissions.balanceView),
          ),
          NavDestination(
            label: 'Leave Policies',
            icon: Icons.rule_folder_outlined,
            path: Routes.hrPolicy,
            initialTabLabel: 'Leave',
            gate: NavGate.permission(HrPolicyPermissions.policyView),
          ),
          NavDestination(
            label: 'Holidays',
            icon: Icons.beach_access_outlined,
            path: Routes.hrPolicy,
            initialTabLabel: 'Holidays',
            gate: NavGate.permission(HrPolicyPermissions.holidayView),
          ),
        ]),
      ),
    if (!isPlatformOnly)
      NavGroup(
        label: 'Payroll',
        icon: Icons.request_quote_outlined,
        items: filterItems(const [
          NavDestination(
            label: 'Salary Structures',
            icon: Icons.badge_outlined,
            path: Routes.salary,
            initialTabLabel: 'Structures',
            gate: NavGate.permission(SalaryPermissions.view),
          ),
          // Same tab as Salary Structures — Angular's "Employee Salaries"
          // is a second link to the same SALARY_STRUCTURE_VIEW-gated data
          // (a structure assignment is a specific employee's pay), not a
          // separate screen.
          NavDestination(
            label: 'Employee Salaries',
            icon: Icons.person_pin_outlined,
            path: Routes.salary,
            initialTabLabel: 'Structures',
            gate: NavGate.permission(SalaryPermissions.view),
          ),
          NavDestination(
            label: 'Payroll Runs',
            icon: Icons.request_quote_outlined,
            path: Routes.payroll,
            gate: NavGate.anyPermission([
              PayrollPermissions.view,
              PayrollPermissions.process,
              PayrollPermissions.approve,
            ]),
          ),
          NavDestination(
            label: 'Loans & Advances',
            icon: Icons.account_balance_outlined,
            path: Routes.salary,
            initialTabLabel: 'Loans',
            gate: NavGate.permission(SalaryPermissions.view),
          ),
          NavDestination(
            label: 'Salary Sheet',
            icon: Icons.table_chart_outlined,
            path: Routes.salarySheet,
            gate: NavGate.anyPermission([
              PayrollPermissions.view,
              PayrollPermissions.process,
              PayrollPermissions.approve,
            ]),
          ),
          NavDestination(
            label: 'My Payslips',
            icon: Icons.receipt_long_rounded,
            path: Routes.payslips,
          ),
        ]),
      ),
    if (!isPlatformOnly)
      NavGroup(
        label: 'Billing',
        icon: Icons.receipt_long_outlined,
        items: filterItems(const [
          // The invoice list itself is a tab on FinanceScreen, not
          // ReceivablesScreen — that one only has Receipts/Refunds/Credit
          // notes, no invoice list of its own.
          NavDestination(
            label: 'Invoices',
            icon: Icons.receipt_outlined,
            path: Routes.finance,
            initialTabLabel: 'Invoices',
            gate: NavGate.permission(FinancePermissions.invoiceView),
          ),
          NavDestination(
            label: 'Refunds',
            icon: Icons.undo_rounded,
            path: Routes.receivables,
            initialTabLabel: 'Refunds',
            gate: NavGate.permission(ReceivablesPermissions.invoiceView),
          ),
          NavDestination(
            label: 'Payment Receipts',
            icon: Icons.inbox_outlined,
            path: Routes.receivables,
            initialTabLabel: 'Receipts',
            gate: NavGate.permission(ReceivablesPermissions.receiptView),
          ),
          NavDestination(
            label: 'Vendors',
            icon: Icons.storefront_outlined,
            path: Routes.payables,
            initialTabLabel: 'Vendors',
            gate: NavGate.permission(PayablesPermissions.vendorView),
          ),
          NavDestination(
            label: 'Vendor Bills',
            icon: Icons.outbox_outlined,
            path: Routes.payables,
            initialTabLabel: 'Bills',
            gate: NavGate.permission(PayablesPermissions.billView),
          ),
        ]),
      ),
    if (!isPlatformOnly)
      NavGroup(
        label: 'Accounting',
        icon: Icons.menu_book_outlined,
        items: filterItems(const [
          NavDestination(
            label: 'Chart of Accounts',
            icon: Icons.account_tree_outlined,
            path: Routes.accounting,
            initialTabLabel: 'Accounts',
            gate: NavGate.permission(AccountingPermissions.accountView),
          ),
          NavDestination(
            label: 'Journal Entries',
            icon: Icons.edit_note_outlined,
            path: Routes.accounting,
            initialTabLabel: 'Entries',
            gate: NavGate.permission(AccountingPermissions.entryView),
          ),
          NavDestination(
            label: 'General Ledger',
            icon: Icons.menu_book_outlined,
            path: Routes.accounting,
            initialTabLabel: 'Ledger',
            gate: NavGate.permission(AccountingPermissions.ledgerView),
          ),
          NavDestination(
            label: 'Fiscal Years',
            icon: Icons.calendar_month_outlined,
            path: Routes.closing,
            initialTabLabel: 'Periods',
            gate: NavGate.permission(ClosingPermissions.periodView),
          ),
          NavDestination(
            label: 'Accounting Periods',
            icon: Icons.event_repeat_outlined,
            path: Routes.closing,
            initialTabLabel: 'Periods',
            gate: NavGate.permission(ClosingPermissions.periodView),
          ),
          NavDestination(
            label: 'Reports',
            icon: Icons.insights_outlined,
            path: Routes.reports,
            gate: NavGate.permission(AccountingPermissions.ledgerView),
          ),
        ]),
      ),
    if (!isPlatformOnly)
      NavGroup(
        label: 'Banking',
        icon: Icons.account_balance_wallet_outlined,
        items: filterItems(const [
          NavDestination(
            label: 'Expenses',
            icon: Icons.payments_outlined,
            path: Routes.finance,
            initialTabLabel: 'Expenses',
            gate: NavGate.permission(FinancePermissions.expenseView),
          ),
          NavDestination(
            label: 'Budgets',
            icon: Icons.savings_outlined,
            path: Routes.budgets,
            gate: NavGate.permission(BudgetPermissions.view),
          ),
          NavDestination(
            label: 'Wallet',
            icon: Icons.account_balance_wallet_outlined,
            path: Routes.finance,
            initialTabLabel: 'Wallet',
            gate: NavGate.permission(FinancePermissions.walletView),
          ),
          NavDestination(
            label: 'Bank Reconciliation',
            icon: Icons.account_balance_outlined,
            path: Routes.reconciliation,
            gate: NavGate.permission(ReconciliationPermissions.view),
          ),
          NavDestination(
            label: 'Fixed Assets',
            icon: Icons.precision_manufacturing_outlined,
            path: Routes.closing,
            initialTabLabel: 'Fixed assets',
            gate: NavGate.permission(ClosingPermissions.assetView),
          ),
        ]),
      ),
    if (!isPlatformOnly)
      NavGroup(
        label: 'IT Assets',
        icon: Icons.devices_outlined,
        items: filterItems(const [
          NavDestination(
            label: 'Hardware',
            icon: Icons.computer_outlined,
            path: Routes.itam,
            initialTabLabel: 'Hardware',
            gate: NavGate.permission(ItamPermissions.hardwareView),
          ),
          NavDestination(
            label: 'Software',
            icon: Icons.apps_outlined,
            path: Routes.itam,
            initialTabLabel: 'Software',
            gate: NavGate.permission(ItamPermissions.softwareView),
          ),
          NavDestination(
            label: 'Offboarding',
            icon: Icons.logout_rounded,
            path: Routes.itam,
            initialTabLabel: 'Offboarding',
            gate: NavGate.permission(ItamPermissions.offboardingView),
          ),
        ]),
      ),
    NavGroup(
      label: 'Administration',
      icon: Icons.settings_outlined,
      items: filterItems([
        const NavDestination(
          label: 'Users',
          icon: Icons.manage_accounts_outlined,
          path: Routes.users,
          gate: NavGate.permission(AdminPermissions.userView),
        ),
        NavDestination(
          label: 'Roles & Permissions',
          icon: Icons.admin_panel_settings_outlined,
          path: Routes.admin,
          initialTabLabel: 'Roles',
          gate: NavGate.custom((u, p) => u?.isCompanyOwner ?? false),
        ),
        const NavDestination(
          label: 'Company Profile',
          icon: Icons.domain_outlined,
          path: Routes.company,
          gate: NavGate.permission(CompanyPermissions.settings),
        ),
        const NavDestination(
          label: 'Announcements',
          icon: Icons.campaign_outlined,
          path: Routes.admin,
          initialTabLabel: 'Notices',
          gate: NavGate.permission(AdminPermissions.announcementView),
        ),
        NavDestination(
          label: 'Plans & Upgrade',
          icon: Icons.workspace_premium_outlined,
          path: Routes.subscriptionPlan,
          gate: NavGate.custom((u, p) => u?.isCompanyOwner ?? false),
        ),
        const NavDestination(
          label: 'AI Settings',
          icon: Icons.smart_toy_outlined,
          path: Routes.aiSettings,
          gate: NavGate.permission(AiPermissions.admin),
        ),
        const NavDestination(
          label: 'Notifications',
          icon: Icons.notifications_outlined,
          path: Routes.notificationPreferences,
        ),
        const NavDestination(
          label: 'Appearance',
          icon: Icons.palette_outlined,
          path: Routes.appearance,
        ),
        const NavDestination(
          label: 'Change Password',
          icon: Icons.key_outlined,
          path: Routes.changePassword,
        ),
        const NavDestination(
          label: 'Change Email',
          icon: Icons.alternate_email_rounded,
          path: Routes.changeEmail,
        ),
        // Angular links the same page from two places (`/audit-logs` under
        // its own Administration nav row, and the support module's own
        // route) — this is that same duplication, not a second screen:
        // `AUDIT_LOG_VIEW` gates `SupportAuditServiceImpl` on the backend,
        // which is exactly what SupportAdminScreen's "Trail" tab already
        // calls.
        NavDestination(
          label: 'Audit Logs',
          icon: Icons.history_rounded,
          path: Routes.supportAdmin,
          initialTabLabel: 'Trail',
          gate: NavGate.role(supportAuditRoles),
        ),
        const NavDestination(
          label: 'Platform Support',
          icon: Icons.support_agent_outlined,
          path: Routes.support,
          gate: NavGate.permission(SupportPermissions.messageView),
        ),
      ]),
    ),
  ];

  return groups.where((g) => g.items.isNotEmpty).toList();
}

/// Every visible destination across all groups, with no section headers —
/// Angular's non-owner rendering for a plain company role. A group left with
/// exactly one visible item collapses to a direct link even for a grouped
/// user, so the two paths share this: flattening one group's single item is
/// indistinguishable from flattening all of them.
List<NavDestination> flattenGroups(List<NavGroup> groups) =>
    groups.expand((g) => g.items).toList();

/// Every gate registered against a given route path, built once from the
/// unfiltered table (`includeAllForRouteCheck: true` bypasses both the
/// platform-only group drop and the per-item visibility filter, so a route
/// gated only inside a group that a particular caller wouldn't see is still
/// found here). A path can carry more than one gate — several destinations
/// share `Routes.crm` under different tabs — so access is the *union* of
/// them: any gate that passes is enough to open the screen at all, even if
/// the specific tab that gate belongs to isn't the one that loads.
final Map<String, List<NavGate>> _routeGates = () {
  final map = <String, List<NavGate>>{};
  final groups = buildNavGroups(
    null,
    const PermissionState(),
    includeAllForRouteCheck: true,
  );
  for (final group in groups) {
    for (final item in group.items) {
      map.putIfAbsent(item.path, () => []).add(item.gate);
    }
  }
  return map;
}();

/// Whether [user]/[perms] may open [path] directly — via a deep link, a
/// restored back stack, or a typed URL — not just whether it shows up in the
/// drawer. Mirrors Angular's `RoleGuard`, which blocks direct navigation to a
/// route the account can't use rather than only hiding the sidebar link.
///
/// A path with no registered destination (the bottom-nav tabs, auth screens,
/// account-settings screens) is always allowed here: those are either gated
/// elsewhere (the router's own auth/portal split) or intentionally open to
/// every signed-in account.
bool isRouteAllowed(String path, AppUser? user, PermissionState perms) {
  final gates = _routeGates[path];
  if (gates == null || gates.isEmpty) return true;
  return gates.any((gate) => gate.allows(user, perms));
}
