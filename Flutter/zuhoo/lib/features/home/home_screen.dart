import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/auth/permission_controller.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/stat_card.dart';
import '../accounting/accounting_models.dart' show AccountingPermissions;
import '../admin/admin_models.dart';
import '../ai/ai_models.dart';
import '../assets_periods/assets_periods_models.dart' show ClosingPermissions;
import '../attendance/attendance_controller.dart';
import '../attendance/attendance_models.dart'
    show AttendanceAdminPermissions;
import '../attendance/punch_card.dart';
import '../biometric/biometric_models.dart' show BiometricPermissions;
import '../catalogue/catalogue_models.dart' show CataloguePermissions;
import '../crm/crm_models.dart' show CrmPermissions;
import '../hrpolicy/hrpolicy_models.dart' show HrPolicyPermissions;
import '../kb/kb_models.dart';
import '../leave/leave_models.dart';
import '../leave/leave_repository.dart';
import '../payables/payables_models.dart' show PayablesPermissions;
import '../payslips/payslip_models.dart' show PayrollPermissions;
import '../profile/employee_repository.dart';
import '../receivables/receivables_models.dart' show ReceivablesPermissions;
import '../salary/salary_models.dart' show SalaryPermissions;
import '../support_admin/support_admin_models.dart';
import '../workflow/workflow_models.dart';
import 'home_repository.dart';

/// The employee's dashboard.
///
/// Every figure here comes from an endpoint that can legitimately be empty or
/// forbidden, so nothing is required for the screen to render: a missing panel
/// is simply absent, and a missing number is a dash. That is what lets one
/// screen work for an employee whose HR has configured everything and for one
/// on their first day.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(myEmployeeProvider);
    ref.invalidate(noticeBoardProvider);
    ref.invalidate(latestReviewScoreProvider);
    await Future.wait([
      ref.read(attendanceControllerProvider.notifier).refresh(),
      ref.read(leaveControllerProvider.notifier).refresh(),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final user = ref.watch(currentUserProvider);
    final employee = ref.watch(myEmployeeProvider);

    return Scaffold(
      backgroundColor: bos.bgPage,
      body: RefreshIndicator(
        color: bos.brand,
        backgroundColor: bos.bgCard,
        onRefresh: () => _refresh(ref),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _Greeting(
              name: employee.value?.firstName ??
                  user?.displayFirstName ??
                  '',
              role: employee.value?.roleLabel,
              imageUrl: employee.value?.imageUrl ?? user?.profileImageUrl,
              initials: employee.value?.initials ?? user?.initials ?? '?',
            ),
            const SizedBox(height: 18),
            const PunchCard(compact: true),
            const SizedBox(height: 18),
            const _Stats(),
            const SizedBox(height: 22),
            const _TeamToday(),
            const _Pipeline(),
            const _QuickActions(),
            const SizedBox(height: 22),
            const _LeaveBalances(),
            const _NoticeBoard(),
          ],
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({
    required this.name,
    required this.role,
    required this.imageUrl,
    required this.initials,
  });

  final String name;
  final String? role;
  final String? imageUrl;
  final String initials;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: TextStyle(color: bos.muted, fontSize: 13.5),
              ),
              const SizedBox(height: 2),
              Text(
                name.isEmpty ? 'Welcome back' : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: bos.text,
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              if (role != null) ...[
                const SizedBox(height: 4),
                Text(
                  role!,
                  style: TextStyle(
                    color: bos.brandInk,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Avatar(initials: initials, imageUrl: imageUrl, size: 46),
      ],
    );
  }
}

class _Stats extends ConsumerWidget {
  const _Stats();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final summary = ref.watch(attendanceControllerProvider).value?.summary;
    final leave = ref.watch(leaveControllerProvider).value;
    final notices = ref.watch(noticeBoardProvider).value;
    final review = ref.watch(latestReviewScoreProvider).value;

    final percent = summary?.attendancePercent;
    final available = leave?.totalAvailable;

    final cards = [
      StatCard(
        label: 'Attendance this month',
        value: percent?.toStringAsFixed(percent % 1 == 0 ? 0 : 1),
        suffix: '%',
        icon: Icons.event_available_rounded,
        tone: bos.success,
      ),
      StatCard(
        label: 'Leave days available',
        value: available == null
            ? null
            : available == available.roundToDouble()
                ? available.round().toString()
                : available.toStringAsFixed(1),
        icon: Icons.beach_access_rounded,
        tone: bos.info,
        onTap: () => context.go(Routes.leave),
      ),
      StatCard(
        label: 'Open requests',
        value: notices?.openRequests?.toString(),
        icon: Icons.assignment_outlined,
        tone: bos.warning,
        onTap: () => context.push(Routes.requests),
      ),
      StatCard(
        label: 'Latest review score',
        value: review?.toStringAsFixed(1),
        icon: Icons.star_outline_rounded,
        tone: bos.brandInk,
      ),
    ];

    // A fixed height, not an aspect ratio. An aspect ratio ties the tile's
    // height to the screen's width, so the same layout that fits a 411dp phone
    // clips its label on a 320dp one — and clips it on every phone once the
    // reader turns their font size up. The extent below is what the tallest
    // content actually needs (icon + figure + a two-line label), and it grows
    // with the text scale rather than pretending the scale is always 1.
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final extent = 134 + (scale - 1).clamp(0.0, 1.5) * 48;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: cards.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: extent,
      ),
      itemBuilder: (context, index) => cards[index],
    );
  }
}

class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final canAskAi =
        ref.watch(permissionControllerProvider).has(AiPermissions.chat);
    final canReadKb =
        ref.watch(permissionControllerProvider).has(KbPermissions.view);
    // Any one of the setup tabs is enough to make the screen worth opening;
    // it decides for itself which of them to show.
    final canSetUp = ref.watch(permissionControllerProvider).hasAny(const [
      AdminPermissions.departmentView,
      AdminPermissions.designationView,
      AdminPermissions.announcementView,
      AdminPermissions.serviceCategoryView,
    ]);
    // Same idea for the catalogue: any one of its tabs is worth the trip.
    final canSeeCatalogue =
        ref.watch(permissionControllerProvider).hasAny(const [
      CataloguePermissions.serviceView,
      CataloguePermissions.templateView,
      CataloguePermissions.packageView,
    ]);
    final canDesignWorkflows =
        ref.watch(permissionControllerProvider).has(WorkflowPermissions.view);
    final canSeeTerminals =
        ref.watch(permissionControllerProvider).has(BiometricPermissions.view);
    final canRunPayroll = ref.watch(permissionControllerProvider).hasAny(const [
      PayrollPermissions.view,
      PayrollPermissions.process,
      PayrollPermissions.approve,
    ]);
    final canSetPay = ref.watch(permissionControllerProvider).hasAny(const [
      SalaryPermissions.view,
      SalaryPermissions.create,
    ]);
    final canSeeBooks = ref.watch(permissionControllerProvider).hasAny(const [
      AccountingPermissions.accountView,
      AccountingPermissions.entryView,
      AccountingPermissions.ledgerView,
    ]);
    final canSeeReports = ref
        .watch(permissionControllerProvider)
        .has(AccountingPermissions.ledgerView);
    final canSeePayables =
        ref.watch(permissionControllerProvider).hasAny(const [
      PayablesPermissions.billView,
      PayablesPermissions.vendorView,
    ]);
    final canSeeReceipts =
        ref.watch(permissionControllerProvider).hasAny(const [
      ReceivablesPermissions.receiptView,
      ReceivablesPermissions.invoiceView,
    ]);
    final canCloseBooks = ref.watch(permissionControllerProvider).hasAny(const [
      ClosingPermissions.periodView,
      ClosingPermissions.assetView,
    ]);
    final canSeeTeamAttendance = ref
        .watch(permissionControllerProvider)
        .has(AttendanceAdminPermissions.view);
    final canSeeContacts =
        ref.watch(permissionControllerProvider).hasAny(const [
      CrmPermissions.contactView,
      CrmPermissions.tagView,
    ]);
    final canSetHrRules =
        ref.watch(permissionControllerProvider).hasAny(const [
      HrPolicyPermissions.holidayView,
      HrPolicyPermissions.policyView,
      HrPolicyPermissions.shiftView,
      HrPolicyPermissions.letterView,
    ]);
    // The support desk is role-gated rather than permission-gated — see
    // support_admin_models.dart for why each surface has its own list.
    final canRunSupportDesk = ref.watch(currentUserProvider)?.hasAnyRole(const [
          ...supportAgentAdminRoles,
          ...supportCategoryAdminRoles,
          ...slaAdminRoles,
          ...supportAuditRoles,
        ]) ??
        false;

    // `push` marks a destination that lives outside the tab bar: it stacks on
    // top and backs out again, rather than switching which tab is selected.
    final actions = <({String label, IconData icon, String path, bool push})>[
      (
        label: 'Search everything',
        icon: Icons.search_rounded,
        path: Routes.search,
        push: true
      ),
      if (canAskAi)
        (
          label: 'Ask AI',
          icon: Icons.auto_awesome_rounded,
          path: Routes.ai,
          push: true
        ),
      (
        label: 'Raise a request',
        icon: Icons.add_task_rounded,
        path: Routes.requests,
        push: true
      ),
      (
        label: 'Apply for leave',
        icon: Icons.event_note_rounded,
        path: Routes.leave,
        push: false
      ),
      (
        label: 'My attendance',
        icon: Icons.history_rounded,
        path: Routes.attendance,
        push: false
      ),
      (
        label: 'My payslips',
        icon: Icons.receipt_long_rounded,
        path: Routes.payslips,
        push: true
      ),
      (
        label: 'CRM',
        icon: Icons.trending_up_rounded,
        path: Routes.crm,
        push: true
      ),
      (
        label: 'Finance',
        icon: Icons.account_balance_wallet_outlined,
        path: Routes.finance,
        push: true
      ),
      (
        label: 'Support',
        icon: Icons.support_agent_rounded,
        path: Routes.support,
        push: true
      ),
      if (canReadKb)
        (
          label: 'Knowledge base',
          icon: Icons.menu_book_outlined,
          path: Routes.kb,
          push: true
        ),
      if (canSetUp)
        (
          label: 'Company setup',
          icon: Icons.tune_rounded,
          path: Routes.admin,
          push: true
        ),
      if (canSeeCatalogue)
        (
          label: 'Catalogue',
          icon: Icons.local_offer_outlined,
          path: Routes.catalogue,
          push: true
        ),
      if (canRunSupportDesk)
        (
          label: 'Support desk',
          icon: Icons.headset_mic_outlined,
          path: Routes.supportAdmin,
          push: true
        ),
      if (canDesignWorkflows)
        (
          label: 'Workflows',
          icon: Icons.account_tree_outlined,
          path: Routes.workflows,
          push: true
        ),
      if (canSeeTerminals)
        (
          label: 'Terminals',
          icon: Icons.fingerprint_rounded,
          path: Routes.biometric,
          push: true
        ),
      if (canRunPayroll)
        (
          label: 'Payroll',
          icon: Icons.request_quote_outlined,
          path: Routes.payroll,
          push: true
        ),
      if (canSetPay)
        (
          label: 'Pay and loans',
          icon: Icons.badge_outlined,
          path: Routes.salary,
          push: true
        ),
      if (canSeeBooks)
        (
          label: 'Books',
          icon: Icons.menu_book_outlined,
          path: Routes.accounting,
          push: true
        ),
      // Every report reads the ledger, so that one permission gates them all.
      if (canSeeReports)
        (
          label: 'Reports',
          icon: Icons.insights_outlined,
          path: Routes.reports,
          push: true
        ),
      if (canSeePayables)
        (
          label: 'Payables',
          icon: Icons.outbox_outlined,
          path: Routes.payables,
          push: true
        ),
      if (canSeeReceipts)
        (
          label: 'Receipts',
          icon: Icons.inbox_outlined,
          path: Routes.receivables,
          push: true
        ),
      if (canCloseBooks)
        (
          label: 'Month end',
          icon: Icons.calendar_month_outlined,
          path: Routes.closing,
          push: true
        ),
      if (canSetHrRules)
        (
          label: 'HR rules',
          icon: Icons.rule_folder_outlined,
          path: Routes.hrPolicy,
          push: true
        ),
      if (canSeeContacts)
        (
          label: 'Contacts',
          icon: Icons.contacts_outlined,
          path: Routes.contacts,
          push: true
        ),
      if (canSeeTeamAttendance)
        (
          label: 'Who is in',
          icon: Icons.groups_outlined,
          path: Routes.teamAttendance,
          push: true
        ),
      (
        label: 'My profile',
        icon: Icons.person_outline_rounded,
        path: Routes.profile,
        push: false
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Quick actions', icon: Icons.bolt_rounded),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, indent: 54, color: bos.borderLight),
                ListTile(
                  leading: Container(
                    height: 34,
                    width: 34,
                    decoration: BoxDecoration(
                      color: bos.brandSoft,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(actions[i].icon, size: 18, color: bos.brandInk),
                  ),
                  title: Text(actions[i].label),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: bos.muted,
                  ),
                  onTap: () => actions[i].push
                      ? context.push(actions[i].path)
                      : context.go(actions[i].path),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _LeaveBalances extends ConsumerWidget {
  const _LeaveBalances();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balances = ref.watch(leaveControllerProvider).value?.balances;

    // No balances configured is a normal state, not an empty state worth
    // announcing — the panel just is not there.
    if (balances == null || balances.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Leave balance',
          icon: Icons.beach_access_rounded,
          trailing: TextButton(
            onPressed: () => context.go(Routes.leave),
            child: const Text('See all'),
          ),
        ),
        AppCard(
          child: Column(
            children: [
              for (var i = 0; i < balances.length && i < 4; i++) ...[
                if (i > 0) const SizedBox(height: 14),
                _BalanceRow(balance: balances[i]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
      ],
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({required this.balance});

  final LeaveBalance balance;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                Fmt.label(balance.leaveType),
                style: TextStyle(
                  color: bos.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${_n(balance.remainingDays)} of ${_n(balance.entitledDays)} left',
              style: TextStyle(color: bos.muted, fontSize: 12.5),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: balance.consumedFraction,
            minHeight: 6,
            backgroundColor: bos.neutralSoft,
            valueColor: AlwaysStoppedAnimation(bos.brand),
          ),
        ),
      ],
    );
  }

  static String _n(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);
}

class _NoticeBoard extends ConsumerWidget {
  const _NoticeBoard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final board = ref.watch(noticeBoardProvider).value;
    if (board == null) return const SizedBox.shrink();

    final announcements = board.announcements.take(3).toList();
    final holidays = board.holidays.take(3).toList();
    if (announcements.isEmpty && holidays.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Notice board', icon: Icons.campaign_outlined),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final a in announcements) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.campaign_rounded, size: 17, color: bos.brandInk),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.title,
                            style: TextStyle(
                              color: bos.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (a.body.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              a.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: bos.muted,
                                fontSize: 12.5,
                                height: 1.35,
                              ),
                            ),
                          ],
                          const SizedBox(height: 3),
                          Text(
                            Fmt.relative(a.shownAt),
                            style: TextStyle(color: bos.muted, fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              if (announcements.isNotEmpty && holidays.isNotEmpty) ...[
                Divider(color: bos.borderLight, height: 1),
                const SizedBox(height: 14),
              ],
              for (var i = 0; i < holidays.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.celebration_outlined, size: 17, color: bos.info),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        holidays[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: bos.text, fontSize: 13.5),
                      ),
                    ),
                    Text(
                      holidays[i].countdownLabel,
                      style: TextStyle(
                        color: bos.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// How today is going for the company, for whoever is entitled to see it.
///
/// Renders nothing at all when the summary is not available — the endpoint is
/// gated on EMPLOYEE_VIEW, and an employee without it should get a home screen
/// that simply has one fewer section rather than an error or an empty box.
class _TeamToday extends ConsumerWidget {
  const _TeamToday();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final snapshot = ref.watch(hrSnapshotProvider).valueOrNull;
    if (snapshot == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Team today', icon: Icons.groups_outlined),
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'In today',
                value: '${snapshot.presentToday}',
                suffix: 'of ${snapshot.totalEmployees}',
                icon: Icons.how_to_reg_outlined,
                tone: bos.success,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                label: 'On leave',
                value: '${snapshot.onLeaveToday}',
                icon: Icons.beach_access_outlined,
                tone: bos.info,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'Absent',
                value: '${snapshot.absentToday}',
                icon: Icons.person_off_outlined,
                // Only coloured when there is somebody to chase.
                tone: snapshot.absentToday > 0 ? bos.warning : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                label: 'Open roles',
                value: '${snapshot.openPositions}',
                icon: Icons.work_outline_rounded,
                onTap: () => context.push(Routes.recruitment),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
      ],
    );
  }
}

/// The same, for whoever works the pipeline.
class _Pipeline extends ConsumerWidget {
  const _Pipeline();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final snapshot = ref.watch(crmSnapshotProvider).valueOrNull;
    if (snapshot == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Pipeline', icon: Icons.trending_up_rounded),
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'Open pipeline',
                value: Fmt.money(snapshot.pipelineValue),
                suffix: '${snapshot.openOpportunities} deals',
                icon: Icons.donut_large_outlined,
                onTap: () => context.push(Routes.crm),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                label: 'Won this month',
                value: Fmt.money(snapshot.wonThisMonth),
                suffix: '${snapshot.qualifiedLeads} qualified leads',
                icon: Icons.emoji_events_outlined,
                tone: bos.success,
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
      ],
    );
  }
}
