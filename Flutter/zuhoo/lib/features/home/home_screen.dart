import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/nav_registry.dart';
import '../../app/router.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/auth/permission_controller.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/stat_card.dart';
import '../alerts/notification_navigation.dart';
import '../alerts/notification_repository.dart';
import '../approvals/approval_repository.dart';
import '../attendance/attendance_controller.dart';
import '../attendance/punch_card.dart';
import '../leave/leave_models.dart';
import '../leave/leave_repository.dart';
import '../profile/employee_repository.dart';
import 'dashboard_registry.dart';
import 'home_repository.dart';
import '../../app/shell.dart';

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
      ref.read(approvalInboxProvider.notifier).refresh(),
      ref.read(notificationsControllerProvider.notifier).refresh(),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final user = ref.watch(currentUserProvider);
    final employee = ref.watch(myEmployeeProvider);

    return Scaffold(
      backgroundColor: bos.bgPage,
      // No AppBar on this one tab (the greeting doubles as its header), which
      // is exactly why the menu button used to misfire here: as the first
      // child of a RefreshIndicator's ListView, sitting flush against the top
      // of the screen with no SafeArea, it was competing with the pull-to-
      // refresh drag recognizer for the same touch — and losing more often
      // than not. Pulling it out to a fixed header above the scrollable body
      // removes it from that gesture arena entirely.
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _Greeting(
                name:
                    employee.value?.firstName ?? user?.displayFirstName ?? '',
                role: employee.value?.roleLabel,
                imageUrl: employee.value?.imageUrl ?? user?.profileImageUrl,
                initials: employee.value?.initials ?? user?.initials ?? '?',
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: bos.brand,
                backgroundColor: bos.bgCard,
                onRefresh: () => _refresh(ref),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                  children: [
                    // "What do I need to do right now" leads: anything
                    // waiting on a decision, my own status, then the fastest
                    // way to start something new. Company/team pulse (Team
                    // today, Pipeline) — informational rather than
                    // actionable for most viewers — follows rather than
                    // leads, and configured-but-passive content (leave
                    // balances, the notice board) comes last.
                    const _PendingApprovalsBanner(),
                    const PunchCard(compact: true),
                    const SizedBox(height: 18),
                    const _Stats(),
                    const SizedBox(height: 22),
<<<<<<< Updated upstream
=======
                    const _TeamToday(),
                    const _Pipeline(),
                    const _CompanySnapshot(),
>>>>>>> Stashed changes
                    const _QuickActions(),
                    const SizedBox(height: 22),
                    const _RecentNotifications(),
                    const _TeamToday(),
                    const _Pipeline(),
                    const _LeaveBalances(),
                    const _NoticeBoard(),
                  ],
                ),
              ),
            ),
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
        // Home is the one tab with no app bar — the greeting *is* its header —
        // so the way into the drawer has to live here or it does not exist on
        // this screen at all.
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: IconButton(
            icon: const Icon(Icons.menu_rounded),
            tooltip: 'All modules',
            onPressed: () => appShellScaffoldKey.currentState?.openDrawer(),
          ),
        ),
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

    // Rows of two, not a grid. A grid has to be told a tile height before it
    // can lay anything out, so the height was a formula — and a formula that
    // has to predict wrapped text and font metrics gets it wrong: this one
    // ran five pixels short and clipped "Attendance this month" the moment a
    // reader turned their font size up. Nothing here predicts anything now;
    // the cards report their own height, IntrinsicHeight makes the pair in
    // each row match, and there is no number left to be wrong. It is also
    // what every other StatCard row in the app already does.
    return Column(
      children: [
        for (var i = 0; i < cards.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: cards[i]),
                const SizedBox(width: 12),
                // An odd card keeps its half of the row rather than
                // stretching across it.
                Expanded(
                  child: i + 1 < cards.length
                      ? cards[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// "What do I need to do right now" starts here — a count of everything
/// waiting on this account's decision, from the same aggregator the
/// Approvals screen itself reads. Absent entirely for anyone who holds none
/// of the approve permissions it aggregates, and silent (not an error
/// banner) if the fetch fails — a dashboard widget failing quietly beats one
/// that blocks the rest of the home screen from rendering.
class _PendingApprovalsBanner extends ConsumerWidget {
  const _PendingApprovalsBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perms = ref.watch(permissionControllerProvider);
    if (!canSeeApprovalInbox(perms)) return const SizedBox.shrink();

    final async = ref.watch(approvalInboxProvider);
    final count = async.value?.length ?? 0;
    if (async.isLoading && async.value == null) {
      return const SizedBox.shrink();
    }
    if (count == 0) return const SizedBox.shrink();

    final bos = Theme.of(context).bos;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: bos.warningSoft,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push(Routes.approvals),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: bos.warning.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Icon(Icons.fact_check_outlined, size: 20, color: bos.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    count == 1
                        ? '1 approval needs your decision'
                        : '$count approvals need your decision',
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 20, color: bos.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final user = ref.watch(currentUserProvider);
    final perms = ref.watch(permissionControllerProvider);

    // Sourced from the same registry the drawer reads, so the two surfaces
    // can never independently drift the way two hand-maintained copies did.
    // "Search everything" and "My profile" sit outside it: neither is a
    // sidebar module in Angular either — its nearest equivalent for both is
    // the top bar, not the grouped nav.
    final actions = <NavDestination>[
      const NavDestination(
        label: 'Search everything',
        icon: Icons.search_rounded,
        path: Routes.search,
      ),
      ...flattenGroups(buildNavGroups(user, perms)),
      const NavDestination(
        label: 'My profile',
        icon: Icons.person_outline_rounded,
        path: Routes.profile,
        push: false,
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
                      ? context.push(
                          actions[i].path,
                          extra: actions[i].initialTabLabel,
                        )
                      : context.go(
                          actions[i].path,
                          extra: actions[i].initialTabLabel,
                        ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A glance at what just happened, not the whole inbox — the Alerts tab is
/// one tap away for the rest. Reads the same controller the bell badge and
/// the Alerts screen already keep warm, so this adds no extra request of its
/// own.
class _RecentNotifications extends ConsumerWidget {
  const _RecentNotifications();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final items = ref.watch(notificationsControllerProvider).value?.items;
    if (items == null || items.isEmpty) return const SizedBox.shrink();

    final recent = items.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Recent notifications',
          icon: Icons.notifications_outlined,
          trailing: TextButton(
            onPressed: () => context.go(Routes.alerts),
            child: const Text('See all'),
          ),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < recent.length; i++) ...[
                if (i > 0) Divider(height: 1, indent: 34, color: bos.borderLight),
                _RecentNotificationRow(notification: recent[i]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
      ],
    );
  }
}

class _RecentNotificationRow extends ConsumerWidget {
  const _RecentNotificationRow({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final unread = !notification.read;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Container(
          height: 8,
          width: 8,
          decoration: BoxDecoration(
            color: unread ? bos.brand : Colors.transparent,
            shape: BoxShape.circle,
          ),
        ),
      ),
      title: Text(
        notification.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: bos.text,
          fontSize: 13.5,
          fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
      subtitle: Text(
        Fmt.relative(notification.createdAt),
        style: TextStyle(color: bos.muted, fontSize: 11.5),
      ),
      onTap: () async {
        if (unread) {
          await ref
              .read(notificationsControllerProvider.notifier)
              .markRead(notification.id);
        }
        if (context.mounted) {
          await openNotification(context, ref, notification);
        }
      },
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
        if (board.offline) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.cloud_off_rounded, size: 14, color: bos.muted),
                const SizedBox(width: 6),
                Text(
                  'Offline — showing the last saved copy',
                  style: TextStyle(color: bos.muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
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
    final snapshot = ref.watch(hrSnapshotProvider).value;
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
    final snapshot = ref.watch(crmSnapshotProvider).value;
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

/// The company-wide, permission-gated card grid — port of Angular's own
/// `WIDGET_REGISTRY` dashboard. Distinct from [_TeamToday]/[_Pipeline] above,
/// which read two purpose-built, trimmed endpoints for a quick at-a-glance
/// row each; this reads the one untrimmed `/dashboard/summary` Angular's
/// registry is built on, and gates each card independently rather than
/// hiding a whole block behind one permission.
class _CompanySnapshot extends ConsumerWidget {
  const _CompanySnapshot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final summary = ref.watch(dashboardSummaryProvider).value;
    if (summary == null) return const SizedBox.shrink();

    final perms = ref.watch(permissionControllerProvider);
    final bySection = visibleDashboardWidgets(perms);
    if (bySection.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final section in DashboardSection.values)
          if (bySection[section] case final widgets? when widgets.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(section.label, icon: section.icon),
                  // Deliberately not the IntrinsicHeight+stretch pairing
                  // _Stats/_TeamToday/_Pipeline use above: those each show a
                  // small, known set of fields, but this grid renders
                  // whatever figure a tenant's live data happens to produce,
                  // and IntrinsicHeight's own intrinsic-vs-actual layout
                  // rounding can overflow by a pixel or two on exactly the
                  // kind of long, unpredictable value this pulls (a currency
                  // figure with more digits than the row's other card).
                  // Letting each card size to its own content is what stays
                  // correct no matter what a company's numbers look like.
                  for (var i = 0; i < widgets.length; i += 2) ...[
                    if (i > 0) const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: widgets[i].build(context, summary, bos),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: i + 1 < widgets.length
                              ? widgets[i + 1].build(context, summary, bos)
                              : const SizedBox.shrink(),
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
