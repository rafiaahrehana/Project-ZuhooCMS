import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/config_list.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import '../support/support_models.dart' show ticketPriorities;
import 'support_admin_models.dart';
import 'support_admin_repository.dart';
import 'support_admin_sheets.dart';

/// Running the support desk.
///
/// Role-gated rather than permission-gated, and the roles differ per tab — see
/// [supportAgentAdminRoles] and the lists beside it. A support manager sees all
/// four; a company owner sees only the trail; a platform administrator sees the
/// policies but not the trail.
class SupportAdminScreen extends ConsumerWidget {
  const SupportAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final user = ref.watch(currentUserProvider);

    bool can(List<String> roles) => user?.hasAnyRole(roles) ?? false;

    final tabs = <({String label, Widget view, VoidCallback? create})>[
      if (can(supportAgentAdminRoles))
        (
          label: 'Agents',
          view: const _AgentsTab(),
          create: () => showSupportAgentSheet(context),
        ),
      if (can(supportCategoryViewRoles))
        (
          label: 'Categories',
          view: const _CategoriesTab(),
          create: can(supportCategoryAdminRoles)
              ? () => showSupportCategorySheet(context)
              : null,
        ),
      if (can(slaViewRoles))
        (
          label: 'SLA',
          view: const _SlaTab(),
          create: can(slaAdminRoles) ? () => showSlaPolicySheet(context) : null,
        ),
      if (can(supportAuditRoles))
        (label: 'Trail', view: const _AuditTab(), create: null),
    ];

    if (tabs.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Support desk')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Not available to you',
          message:
              'Running the support desk is for support managers and platform '
              'administrators.',
        ),
      );
    }

    return DefaultTabController(
      length: tabs.length,
      child: Builder(
        builder: (context) {
          final tabController = DefaultTabController.of(context);
          return AnimatedBuilder(
            animation: tabController,
            builder: (context, _) {
              final create = tabs[tabController.index].create;
              return Scaffold(
                backgroundColor: bos.bgPage,
                appBar: AppBar(
                  title: const Text('Support desk'),
                  bottom: TabBar(
                    isScrollable: tabs.length > 3,
                    tabAlignment: tabs.length > 3 ? TabAlignment.start : null,
                    tabs: [for (final tab in tabs) Tab(text: tab.label)],
                  ),
                ),
                floatingActionButton: create == null
                    ? null
                    : FloatingActionButton.extended(
                        onPressed: create,
                        backgroundColor: bos.brand,
                        foregroundColor: Colors.white,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('New'),
                      ),
                body: TabBarView(children: [for (final tab in tabs) tab.view]),
              );
            },
          );
        },
      ),
    );
  }
}

// ── Agents ────────────────────────────────────────────────────

class _AgentsTab extends ConsumerStatefulWidget {
  const _AgentsTab();

  @override
  ConsumerState<_AgentsTab> createState() => _AgentsTabState();
}

class _AgentsTabState extends ConsumerState<_AgentsTab> {
  int? _busyId;

  /// Status and availability have no response body, so the row is patched here
  /// from what was asked for rather than from what came back.
  Future<void> _run(
    SupportAgent agent,
    Future<void> Function() action,
    SupportAgent optimistic,
    String failure,
  ) async {
    setState(() => _busyId = agent.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      ref.read(supportAgentsProvider.notifier).apply(optimistic);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failure)));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _setStatus(SupportAgent agent) async {
    final status = await pickOne(
      context,
      current: agent.status,
      options: [
        for (final option in agentStatuses)
          (value: option, label: Fmt.label(option)),
      ],
    );
    if (status == null || status == agent.status || !mounted) return;

    final repo = ref.read(supportAdminRepositoryProvider);
    await _run(
      agent,
      () => repo.setAgentStatus(agent.id, status),
      _copyWithStatus(agent, status: status),
      'Could not change that status.',
    );
  }

  Future<void> _toggleAccepting(SupportAgent agent) async {
    final accepting = !agent.acceptingTickets;
    final repo = ref.read(supportAdminRepositoryProvider);
    await _run(
      agent,
      () => repo.setAcceptingTickets(agent.id, accepting),
      _copyWithStatus(agent, accepting: accepting),
      'Could not change that.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(agentStatusFilterProvider);
    final canAccept =
        ref.watch(currentUserProvider)?.hasAnyRole(acceptingTicketsRoles) ??
            false;

    return ConfigList<SupportAgent>(
      async: ref.watch(supportAgentsProvider),
      onRefresh: ref.read(supportAgentsProvider.notifier).refresh,
      emptyIcon: Icons.support_agent_rounded,
      emptyTitle:
          filter == null ? 'Nobody staffs the desk yet' : 'Nobody in that state',
      emptyMessage: filter == null
          ? 'Add a platform user as an agent and tickets can be assigned to '
              'them.'
          : 'Try another filter, or clear it to see everybody.',
      errorMessage: 'Could not load the agents.',
      header: FilterBar(
        selected: filter,
        onSelected: ref.read(agentStatusFilterProvider.notifier).set,
        options: [
          (value: null, label: 'Everyone'),
          (value: availableAgentsFilter, label: 'Free now'),
          for (final status in agentStatuses)
            (value: status, label: Fmt.label(status)),
        ],
      ),
      itemBuilder: (context, agent) => ConfigRow(
        title: agent.displayName,
        // Not "retired" here — an agent who is off duty is drawn the same
        // muted way, but the chip has to say the right thing.
        active: agent.isTakingWork,
        inactiveLabel: 'Off duty',
        subtitle: [
          Fmt.label(agent.status),
          if (agent.acceptingTickets)
            'up to ${agent.maxConcurrentTickets} at once'
          else
            'not taking new tickets',
          if (agent.department != null) agent.department!,
        ].join(' · '),
        trailingLabel: agent.totalTicketsHandled == 0
            ? null
            : '${agent.totalTicketsHandled} handled',
        busy: _busyId == agent.id,
        onEdit: () => showSupportAgentSheet(context, existing: agent),
        actions: [
          RowAction(label: 'Change status', onSelected: () => _setStatus(agent)),
          if (canAccept)
            RowAction(
              label: agent.acceptingTickets
                  ? 'Stop new tickets'
                  : 'Take new tickets',
              onSelected: () => _toggleAccepting(agent),
            ),
        ],
      ),
    );
  }
}

/// Rebuilds an agent with one field changed.
///
/// The status and accepting-tickets endpoints return no body, so there is
/// nothing to parse — the row is rebuilt from what was asked for. A failure
/// leaves the old row untouched, because this is only reached after the call
/// succeeds.
SupportAgent _copyWithStatus(
  SupportAgent agent, {
  String? status,
  bool? accepting,
}) =>
    SupportAgent(
      id: agent.id,
      status: status ?? agent.status,
      acceptingTickets: accepting ?? agent.acceptingTickets,
      maxConcurrentTickets: agent.maxConcurrentTickets,
      totalTicketsHandled: agent.totalTicketsHandled,
      userId: agent.userId,
      fullName: agent.fullName,
      email: agent.email,
      department: agent.department,
      specialization: agent.specialization,
      notes: agent.notes,
      avgResponseTimeMinutes: agent.avgResponseTimeMinutes,
      avgResolutionTimeMinutes: agent.avgResolutionTimeMinutes,
      satisfactionScore: agent.satisfactionScore,
      lastActiveTime: agent.lastActiveTime,
    );

// ── Categories ────────────────────────────────────────────────

class _CategoriesTab extends ConsumerStatefulWidget {
  const _CategoriesTab();

  @override
  ConsumerState<_CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends ConsumerState<_CategoriesTab> {
  int? _busyId;

  Future<void> _toggle(SupportCategory row) async {
    setState(() => _busyId = row.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(supportAdminRepositoryProvider)
          .setCategoryActive(row.id, !row.active);
      // No response body, so the row is rebuilt from what was asked for.
      ref.read(supportCategoriesProvider.notifier).apply(
            SupportCategory(
              id: row.id,
              name: row.name,
              active: !row.active,
              description: row.description,
              icon: row.icon,
            ),
          );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not change that category.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _delete(SupportCategory row) async {
    final confirmed = await confirmAction(
      context,
      title: 'Remove ${row.name}?',
      message: 'Tickets already filed under it keep it. Retiring it instead '
          'stops new ones without touching the old.',
      action: 'Remove',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyId = row.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(supportAdminRepositoryProvider).deleteCategory(row.id);
      ref.read(supportCategoriesProvider.notifier).remove(row.id);
      messenger.showSnackBar(SnackBar(content: Text('${row.name} removed.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not remove that category.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canWrite =
        ref.watch(currentUserProvider)?.hasAnyRole(supportCategoryAdminRoles) ??
            false;

    return ConfigList<SupportCategory>(
      async: ref.watch(supportCategoriesProvider),
      onRefresh: ref.read(supportCategoriesProvider.notifier).refresh,
      emptyIcon: Icons.label_outline_rounded,
      emptyTitle: 'No categories yet',
      emptyMessage:
          'Categories are what a ticket is filed under, and what routes it to '
          'the right agent.',
      errorMessage: 'Could not load the categories.',
      itemBuilder: (context, row) => ConfigRow(
        title: row.name,
        active: row.active,
        subtitle: row.description,
        busy: _busyId == row.id,
        onEdit:
            canWrite ? () => showSupportCategorySheet(context, existing: row) : null,
        onToggle: canWrite ? () => _toggle(row) : null,
        actions: [
          if (canWrite)
            RowAction(
              label: 'Remove',
              destructive: true,
              onSelected: () => _delete(row),
            ),
        ],
      ),
    );
  }
}

// ── SLA policies ──────────────────────────────────────────────

class _SlaTab extends ConsumerStatefulWidget {
  const _SlaTab();

  @override
  ConsumerState<_SlaTab> createState() => _SlaTabState();
}

class _SlaTabState extends ConsumerState<_SlaTab> {
  int? _busyId;

  Future<void> _toggle(SlaPolicy row) async {
    setState(() => _busyId = row.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(supportAdminRepositoryProvider)
          .setSlaActive(row.id, !row.active);
      ref.read(slaPoliciesProvider.notifier).apply(
            SlaPolicy(
              id: row.id,
              name: row.name,
              priority: row.priority,
              firstResponseTimeHours: row.firstResponseTimeHours,
              resolutionTimeHours: row.resolutionTimeHours,
              businessHoursOnly: row.businessHoursOnly,
              active: !row.active,
              description: row.description,
              notes: row.notes,
            ),
          );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not change that policy.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _delete(SlaPolicy row) async {
    final confirmed = await confirmAction(
      context,
      title: 'Remove ${row.name}?',
      message: 'Tickets at that priority would fall back to whatever other '
          'policy covers them, or to none at all.',
      action: 'Remove',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyId = row.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(supportAdminRepositoryProvider).deleteSlaPolicy(row.id);
      ref.read(slaPoliciesProvider.notifier).remove(row.id);
      messenger.showSnackBar(SnackBar(content: Text('${row.name} removed.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not remove that policy.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(slaPriorityFilterProvider);
    final canWrite =
        ref.watch(currentUserProvider)?.hasAnyRole(slaAdminRoles) ?? false;

    return ConfigList<SlaPolicy>(
      async: ref.watch(slaPoliciesProvider),
      onRefresh: ref.read(slaPoliciesProvider.notifier).refresh,
      emptyIcon: Icons.timer_outlined,
      emptyTitle: filter == null
          ? 'Nothing is promised yet'
          : 'No policy at that priority',
      emptyMessage:
          'An SLA policy sets how quickly a ticket at a given priority must be '
          'answered and resolved.',
      errorMessage: 'Could not load the policies.',
      header: FilterBar(
        selected: filter,
        onSelected: ref.read(slaPriorityFilterProvider.notifier).set,
        options: [
          (value: null, label: 'All priorities'),
          for (final priority in ticketPriorities)
            (value: priority, label: Fmt.label(priority)),
        ],
      ),
      itemBuilder: (context, row) => ConfigRow(
        title: row.name,
        active: row.active,
        subtitle: [
          '${Fmt.label(row.priority)} priority',
          'reply in ${row.firstResponseTimeHours}h',
          'resolve in ${row.resolutionTimeHours}h',
          if (row.businessHoursOnly) 'business hours',
        ].join(' · '),
        busy: _busyId == row.id,
        onEdit: canWrite ? () => showSlaPolicySheet(context, existing: row) : null,
        onToggle: canWrite ? () => _toggle(row) : null,
        actions: [
          if (canWrite)
            RowAction(
              label: 'Remove',
              destructive: true,
              onSelected: () => _delete(row),
            ),
        ],
      ),
    );
  }
}

// ── Audit trail ───────────────────────────────────────────────

class _AuditTab extends ConsumerWidget {
  const _AuditTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final filter = ref.watch(auditFilterProvider);

    return ConfigList<SupportAuditEntry>(
      async: ref.watch(supportAuditProvider),
      onRefresh: ref.read(supportAuditProvider.notifier).refresh,
      emptyIcon: Icons.history_rounded,
      emptyTitle: filter.isEmpty ? 'Nothing recorded yet' : 'Nothing matches',
      emptyMessage: filter.isEmpty
          ? 'Actions taken on the support desk are recorded here as they '
              'happen.'
          : 'Try a different action type or date range.',
      errorMessage: 'Could not load the trail.',
      header: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                filter.isEmpty
                    ? 'Everything, newest first'
                    : filter.actionType != null
                        ? 'Only ${filter.actionType}'
                        : '${Fmt.date(filter.start)} to ${Fmt.date(filter.end)}',
                style: TextStyle(color: bos.muted, fontSize: 12.5),
              ),
            ),
            TextButton.icon(
              onPressed: () => showAuditFilterSheet(context),
              icon: const Icon(Icons.filter_list_rounded, size: 18),
              label: const Text('Filter'),
            ),
          ],
        ),
      ),
      itemBuilder: (context, entry) => _AuditRow(entry: entry),
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.entry});

  final SupportAuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    Fmt.label(entry.actionType),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  Fmt.relative(entry.createdAt),
                  style: TextStyle(color: bos.muted, fontSize: 11.5),
                ),
              ],
            ),
            if (entry.description != null) ...[
              const SizedBox(height: 4),
              Text(
                entry.description!,
                style: TextStyle(color: bos.text, fontSize: 13, height: 1.4),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              [
                entry.actionByUserName ?? 'Someone',
                if (entry.resourceType != null)
                  '${Fmt.label(entry.resourceType)}'
                      '${entry.resourceId == null ? '' : ' #${entry.resourceId}'}',
              ].join(' · '),
              style: TextStyle(color: bos.muted, fontSize: 12),
            ),
            if (entry.contextSwitchToCompanyName != null) ...[
              const SizedBox(height: 8),
              // The single most important thing on the row: this action was
              // taken while switched into somebody else's company.
              Row(
                children: [
                  Icon(Icons.swap_horiz_rounded, size: 14, color: bos.warning),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'While in ${entry.contextSwitchToCompanyName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: bos.warning, fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
