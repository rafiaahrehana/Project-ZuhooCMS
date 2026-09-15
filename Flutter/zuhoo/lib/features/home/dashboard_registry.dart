import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/stat_card.dart';
import '../crm/crm_models.dart';
import '../finance/finance_models.dart';
import '../directory/directory_models.dart';
import '../leave/leave_models.dart';
import '../payslips/payslip_models.dart';
import '../requests/request_models.dart';
import '../support/support_models.dart';

/// GET /dashboard/summary, in full.
///
/// Port of Angular's `DashboardSummary` — the one response its own
/// `WIDGET_REGISTRY` (`widget-registry.ts`) reads every card from. Unlike
/// [HrSnapshot]/[CrmSnapshot], which are trimmed, purpose-built endpoints for
/// this app's own Team Today/Pipeline sections, this is the untrimmed
/// company-wide figure set, and it is what the registry below is built on.
class DashboardSummary {
  const DashboardSummary({
    required this.totalLeads,
    required this.qualifiedLeads,
    required this.totalClients,
    required this.openOpportunities,
    required this.pipelineValue,
    required this.weightedForecast,
    required this.pendingRequests,
    required this.inProgressRequests,
    required this.completedRequestsAllTime,
    required this.totalServiceRequests,
    required this.openTickets,
    required this.newTickets,
    required this.outstandingInvoiceAmount,
    required this.walletBalance,
    required this.walletCreditBalance,
    required this.totalEmployees,
    required this.pendingLeaveApprovals,
    required this.payrollProcessedThisMonth,
  });

  final int totalLeads;
  final int qualifiedLeads;
  final int totalClients;
  final int openOpportunities;
  final double pipelineValue;
  final double weightedForecast;
  final int pendingRequests;
  final int inProgressRequests;
  final int completedRequestsAllTime;
  final int totalServiceRequests;
  final int openTickets;
  final int newTickets;
  final double outstandingInvoiceAmount;
  final double walletBalance;
  final double walletCreditBalance;
  final int totalEmployees;
  final int pendingLeaveApprovals;
  final int payrollProcessedThisMonth;

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    int i(String key) => (json[key] as num?)?.toInt() ?? 0;
    double d(String key) => (json[key] as num?)?.toDouble() ?? 0;
    return DashboardSummary(
      totalLeads: i('totalLeads'),
      qualifiedLeads: i('qualifiedLeads'),
      totalClients: i('totalClients'),
      openOpportunities: i('openOpportunities'),
      pipelineValue: d('pipelineValue'),
      weightedForecast: d('weightedForecast'),
      pendingRequests: i('pendingRequests'),
      inProgressRequests: i('inProgressRequests'),
      completedRequestsAllTime: i('completedRequestsAllTime'),
      totalServiceRequests: i('totalServiceRequests'),
      openTickets: i('openTickets'),
      newTickets: i('newTickets'),
      outstandingInvoiceAmount: d('outstandingInvoiceAmount'),
      walletBalance: d('walletBalance'),
      walletCreditBalance: d('walletCreditBalance'),
      totalEmployees: i('totalEmployees'),
      pendingLeaveApprovals: i('pendingLeaveApprovals'),
      payrollProcessedThisMonth: i('payrollProcessedThisMonth'),
    );
  }
}

/// Company-wide, or null when the reader is not entitled to it — gated on
/// `hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')` at the controller, same shape as
/// [HrSnapshot]/[CrmSnapshot] above. The endpoint itself does not trim fields
/// per permission the way [dashboardRegistry] does client-side; that split
/// is Angular's own design, matched here rather than re-decided.
final dashboardSummaryProvider = FutureProvider<DashboardSummary?>((ref) async {
  ref.watch(currentUserProvider);
  try {
    final json = await ref
        .read(apiClientProvider)
        .get<Map<String, dynamic>>('/dashboard/summary');
    return DashboardSummary.fromJson(json);
  } on ApiException catch (e) {
    if (e.isForbidden || e.isNotFound) return null;
    rethrow;
  }
});

enum DashboardSection { crm, servicedesk, finance, hrm }

extension DashboardSectionLabel on DashboardSection {
  String get label => switch (this) {
        DashboardSection.crm => 'CRM',
        DashboardSection.servicedesk => 'Servicedesk & Support',
        DashboardSection.finance => 'Finance',
        DashboardSection.hrm => 'HRM',
      };

  IconData get icon => switch (this) {
        DashboardSection.crm => Icons.trending_up_rounded,
        DashboardSection.servicedesk => Icons.support_agent_rounded,
        DashboardSection.finance => Icons.account_balance_wallet_outlined,
        DashboardSection.hrm => Icons.groups_outlined,
      };
}

/// One permission-gated card. Port of Angular's `DashboardWidgetDef` — the
/// same idea, just without a component registry to point at, since Flutter
/// builds the card directly rather than instantiating one.
class DashboardWidgetDef {
  const DashboardWidgetDef({
    required this.id,
    required this.section,
    required this.requiredPermission,
    required this.build,
  });

  final String id;
  final DashboardSection section;
  final String requiredPermission;
  final StatCard Function(
    BuildContext context,
    DashboardSummary summary,
    BosPalette bos,
  ) build;
}

/// Every card the company dashboard can show, each gated by the one
/// permission its own destination screen already requires — a direct port of
/// Angular's `WIDGET_REGISTRY`. Adding a new card needs no new endpoint: it
/// reads a field already present on [DashboardSummary].
final List<DashboardWidgetDef> dashboardRegistry = [
  DashboardWidgetDef(
    id: 'total-leads',
    section: DashboardSection.crm,
    requiredPermission: CrmPermissions.leadView,
    build: (context, s, bos) => StatCard(
      label: 'Total leads',
      value: '${s.totalLeads}',
      suffix: '${s.qualifiedLeads} qualified',
      icon: Icons.person_add_alt_1_outlined,
      tone: bos.brandInk,
      onTap: () => context.push(Routes.crm, extra: 'Leads'),
    ),
  ),
  DashboardWidgetDef(
    id: 'accounts',
    section: DashboardSection.crm,
    requiredPermission: CrmPermissions.clientView,
    build: (context, s, bos) => StatCard(
      label: 'Total clients',
      value: '${s.totalClients}',
      icon: Icons.handshake_outlined,
      tone: bos.info,
      onTap: () => context.push(Routes.crm, extra: 'Clients'),
    ),
  ),
  DashboardWidgetDef(
    id: 'open-opportunities',
    section: DashboardSection.crm,
    requiredPermission: CrmPermissions.opportunityView,
    build: (context, s, bos) => StatCard(
      label: 'Open opportunities',
      value: '${s.openOpportunities}',
      suffix: Fmt.money(s.pipelineValue),
      icon: Icons.donut_large_outlined,
      onTap: () => context.push(Routes.crm, extra: 'Pipeline'),
    ),
  ),
  DashboardWidgetDef(
    id: 'weighted-forecast',
    section: DashboardSection.crm,
    requiredPermission: CrmPermissions.opportunityView,
    build: (context, s, bos) => StatCard(
      label: 'Weighted forecast',
      value: Fmt.money(s.weightedForecast),
      icon: Icons.trending_up_rounded,
      tone: bos.success,
      onTap: () => context.push(Routes.crm, extra: 'Pipeline'),
    ),
  ),
  DashboardWidgetDef(
    id: 'pending-requests',
    section: DashboardSection.servicedesk,
    requiredPermission: RequestPermissions.view,
    build: (context, s, bos) => StatCard(
      label: 'Pending requests',
      value: '${s.pendingRequests}',
      icon: Icons.hourglass_top_rounded,
      tone: bos.brandInk,
      onTap: () => context.push(Routes.requests),
    ),
  ),
  DashboardWidgetDef(
    id: 'in-progress-requests',
    section: DashboardSection.servicedesk,
    requiredPermission: RequestPermissions.view,
    build: (context, s, bos) => StatCard(
      label: 'In progress',
      value: '${s.inProgressRequests}',
      suffix: '${s.completedRequestsAllTime} completed all-time',
      icon: Icons.autorenew_rounded,
      tone: bos.info,
      onTap: () => context.push(Routes.requests),
    ),
  ),
  DashboardWidgetDef(
    id: 'total-service-requests',
    section: DashboardSection.servicedesk,
    requiredPermission: RequestPermissions.view,
    build: (context, s, bos) => StatCard(
      label: 'Service requests',
      value: '${s.totalServiceRequests}',
      icon: Icons.assignment_outlined,
      onTap: () => context.push(Routes.requests),
    ),
  ),
  DashboardWidgetDef(
    id: 'support-tickets',
    section: DashboardSection.servicedesk,
    requiredPermission: SupportPermissions.ticketView,
    build: (context, s, bos) => StatCard(
      label: 'Support tickets',
      value: '${s.openTickets}',
      suffix: '${s.newTickets} new',
      icon: Icons.chat_bubble_outline_rounded,
      onTap: () => context.push(Routes.support),
    ),
  ),
  DashboardWidgetDef(
    id: 'outstanding-invoices',
    section: DashboardSection.finance,
    requiredPermission: FinancePermissions.invoiceView,
    build: (context, s, bos) => StatCard(
      label: 'Outstanding invoices',
      value: Fmt.money(s.outstandingInvoiceAmount),
      icon: Icons.receipt_long_outlined,
      tone: s.outstandingInvoiceAmount > 0 ? bos.danger : bos.success,
      onTap: () => context.push(Routes.finance, extra: 'Invoices'),
    ),
  ),
  DashboardWidgetDef(
    id: 'wallet-balance',
    section: DashboardSection.finance,
    requiredPermission: FinancePermissions.walletView,
    build: (context, s, bos) => StatCard(
      label: 'Wallet balance',
      value: Fmt.money(s.walletBalance),
      icon: Icons.account_balance_wallet_outlined,
      onTap: () => context.push(Routes.finance, extra: 'Wallet'),
    ),
  ),
  DashboardWidgetDef(
    id: 'wallet-credits',
    section: DashboardSection.finance,
    requiredPermission: FinancePermissions.walletView,
    build: (context, s, bos) => StatCard(
      label: 'Wallet credits',
      value: Fmt.money(s.walletCreditBalance),
      icon: Icons.savings_outlined,
      tone: bos.success,
      onTap: () => context.push(Routes.finance, extra: 'Wallet'),
    ),
  ),
  DashboardWidgetDef(
    id: 'total-employees',
    section: DashboardSection.hrm,
    requiredPermission: DirectoryPermissions.employeeView,
    build: (context, s, bos) => StatCard(
      label: 'Total employees',
      value: '${s.totalEmployees}',
      icon: Icons.badge_outlined,
      tone: bos.brandInk,
      onTap: () => context.push(Routes.directory),
    ),
  ),
  DashboardWidgetDef(
    id: 'pending-leave-approvals',
    section: DashboardSection.hrm,
    requiredPermission: LeavePermissions.view,
    build: (context, s, bos) => StatCard(
      label: 'Pending leave approvals',
      value: '${s.pendingLeaveApprovals}',
      icon: Icons.event_busy_outlined,
      tone: s.pendingLeaveApprovals > 0 ? bos.danger : bos.success,
      onTap: () => context.push(Routes.leave),
    ),
  ),
  DashboardWidgetDef(
    id: 'payroll-status',
    section: DashboardSection.hrm,
    requiredPermission: PayrollPermissions.view,
    build: (context, s, bos) => StatCard(
      label: 'Payroll processed',
      value: '${s.payrollProcessedThisMonth}',
      suffix: 'of ${s.totalEmployees} employees this month',
      icon: Icons.paid_outlined,
      tone: bos.info,
      onTap: () => context.push(Routes.payroll),
    ),
  ),
];

/// The registry filtered to what [perms] actually allows, grouped by
/// section and dropping any section that ends up with nothing to show.
Map<DashboardSection, List<DashboardWidgetDef>> visibleDashboardWidgets(
  PermissionState perms,
) {
  final byId = <DashboardSection, List<DashboardWidgetDef>>{};
  for (final widget in dashboardRegistry) {
    if (!perms.has(widget.requiredPermission)) continue;
    (byId[widget.section] ??= []).add(widget);
  }
  return byId;
}
