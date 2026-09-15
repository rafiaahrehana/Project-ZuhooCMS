import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/config_list.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import '../support_admin/support_admin_models.dart'
    show SupportAgent, supportAgentAdminRoles;
import '../support_admin/support_admin_repository.dart'
    show supportAdminRepositoryProvider;
import 'internal_notes_screen.dart';
import 'my_agent_card.dart';
import 'support_models.dart';

/// The agent's side of the desk: the queues worth looking at, and everything
/// that happens to a ticket after it is raised.
///
/// The existing support repository is the *requester's* view — my tickets,
/// raise one, chat about it. This is the desk's view of everybody's.
class SupportQueueRepository {
  SupportQueueRepository(this._api);

  final ApiClient _api;

  static const _tickets = '/v1/support/tickets';
  static const _messages = '/v1/support/messages';

  // ── Queues ──────────────────────────────────────────────────

  /// Mine to deal with. `SUPPORT_AGENT` only — a manager sees the whole board
  /// instead.
  Future<PagedResponse<SupportTicket>> assignedToMe({
    int page = 0,
    int size = 30,
  }) =>
      _api.getPaged(
        '$_tickets/assigned-to-me',
        SupportTicket.fromJson,
        page: page,
        size: size,
      );

  /// One status across the desk.
  Future<PagedResponse<SupportTicket>> byStatus(
    String status, {
    int page = 0,
    int size = 30,
  }) =>
      _api.getPaged(
        '$_tickets/status/$status',
        SupportTicket.fromJson,
        page: page,
        size: size,
      );

  /// Past their promised response or resolution time. A bare list — the
  /// endpoint declares `ResponseEntity<?>`, and `getPaged` reads either shape.
  Future<PagedResponse<SupportTicket>> slaBreached() => _api.getPaged(
        '$_tickets/sla-breached',
        SupportTicket.fromJson,
        page: 0,
        size: 100,
      );

  /// Critical and still open.
  Future<PagedResponse<SupportTicket>> criticalOpen() => _api.getPaged(
        '$_tickets/critical-open',
        SupportTicket.fromJson,
        page: 0,
        size: 100,
      );

  /// Looking one up by its number, which is what somebody reads off an email.
  Future<SupportTicket> byNumber(String number) async {
    final json = await _api.get<Map<String, dynamic>>(
      '$_tickets/number/${Uri.encodeComponent(number)}',
    );
    return SupportTicket.fromJson(json);
  }

  // ── What happens to a ticket ────────────────────────────────

  /// Puts it on an agent. The agent is a **query parameter** and the response
  /// is empty, as every action on this controller is.
  Future<void> assign(int id, int agentId) =>
      _api.post<dynamic>('$_tickets/$id/assign?agentId=$agentId');

  /// Moves it to somebody else. Both the new agent and a reason are required —
  /// the reason has no `required = false`, so an empty one is a 400.
  Future<void> reassign(int id, int newAgentId, String reason) =>
      _api.post<dynamic>(
        '$_tickets/$id/reassign?newAgentId=$newAgentId'
        '&reason=${Uri.encodeQueryComponent(reason.trim())}',
      );

  /// Escalates it. The reason is required.
  Future<void> escalate(int id, String reason) => _api.post<dynamic>(
        '$_tickets/$id/escalate'
        '?reason=${Uri.encodeQueryComponent(reason.trim())}',
      );

  /// Stops the first-response clock. Idempotent in practice — the backend only
  /// records the first one.
  Future<void> recordFirstResponse(int id) =>
      _api.post<dynamic>('$_tickets/$id/first-response');

  /// The requester's verdict. Both the rating and the feedback are required
  /// query parameters.
  Future<void> recordSatisfaction(int id, int rating, String feedback) =>
      _api.post<dynamic>(
        '$_tickets/$id/satisfaction?rating=$rating'
        '&feedback=${Uri.encodeQueryComponent(feedback.trim())}',
      );

  // ── Messages ────────────────────────────────────────────────

  /// The notes agents leave each other, which the requester never sees.
  Future<List<SupportMessage>> internalNotes(int ticketId) async {
    final list =
        await _api.get<List<dynamic>>('$_messages/ticket/$ticketId/internal');
    return list
        .whereType<Map<String, dynamic>>()
        .map(SupportMessage.fromJson)
        .toList(growable: false);
  }

  /// Corrects a message's wording. Its own author or an agent.
  Future<SupportMessage> editMessage(int id, String message) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_messages/$id',
      {'message': message.trim()},
    );
    return SupportMessage.fromJson(json);
  }

  /// Removes one. Support manager or company owner only.
  Future<void> deleteMessage(int id) =>
      _api.delete<dynamic>('$_messages/$id');
}

final supportQueueRepositoryProvider = Provider<SupportQueueRepository>(
  (ref) => SupportQueueRepository(ref.watch(apiClientProvider)),
);

/// Which queue is showing.
enum SupportQueue {
  mine('Mine', 'Tickets assigned to you.'),
  breached('SLA breached', 'Past the time the desk promised.'),
  critical('Critical', 'Critical priority and still open.'),
  unassigned('Unassigned', 'Raised, and nobody has picked them up.');

  const SupportQueue(this.label, this.blurb);

  final String label;
  final String blurb;
}

class SupportQueueController extends Notifier<SupportQueue> {
  @override
  SupportQueue build() => SupportQueue.mine;

  void set(SupportQueue queue) {
    if (state == queue) return;
    state = queue;
  }
}

final supportQueueProvider =
    NotifierProvider<SupportQueueController, SupportQueue>(
  SupportQueueController.new,
);

class SupportQueueListController extends AsyncNotifier<List<SupportTicket>> {
  @override
  Future<List<SupportTicket>> build() {
    ref.watch(currentUserProvider);
    ref.watch(supportQueueProvider);
    return _load();
  }

  Future<List<SupportTicket>> _load() async {
    final repo = ref.read(supportQueueRepositoryProvider);
    final page = switch (ref.read(supportQueueProvider)) {
      SupportQueue.mine => await repo.assignedToMe(),
      SupportQueue.breached => await repo.slaBreached(),
      SupportQueue.critical => await repo.criticalOpen(),
      // "Unassigned" is not its own endpoint — it is the NEW status, which is
      // where a ticket sits until somebody takes it.
      SupportQueue.unassigned => await repo.byStatus(TicketStatus.isNew),
    };
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }
}

final supportQueueListProvider =
    AsyncNotifierProvider<SupportQueueListController, List<SupportTicket>>(
  SupportQueueListController.new,
);

/// The agents a ticket can be handed to.
final assignableAgentsProvider = FutureProvider<List<SupportAgent>>((ref) async {
  final page = await ref.read(supportAdminRepositoryProvider).agents();
  return [
    for (final agent in page.content)
      if (agent.isTakingWork) agent,
  ];
});

/// The support desk's own queues.
class SupportQueueScreen extends ConsumerWidget {
  const SupportQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final user = ref.watch(currentUserProvider);

    // The queues are for whoever staffs the desk, not whoever raises tickets.
    if (user != null && !user.hasAnyRole(const ['SUPPORT_AGENT', ...supportAgentAdminRoles])) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('The queue')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Not available to you',
          message:
              'The queue is for support agents and their managers. Your own '
              'tickets are on the Support screen.',
        ),
      );
    }

    final queue = ref.watch(supportQueueProvider);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(
        title: const Text('The queue'),
        actions: [
          IconButton(
            onPressed: () => showFindTicketDialog(context, ref),
            tooltip: 'Find by number',
            icon: const Icon(Icons.search_rounded),
          ),
        ],
      ),
      body: ConfigList<SupportTicket>(
        async: ref.watch(supportQueueListProvider),
        onRefresh: ref.read(supportQueueListProvider.notifier).refresh,
        emptyIcon: Icons.inbox_outlined,
        emptyTitle: switch (queue) {
          SupportQueue.mine => 'Nothing assigned to you',
          SupportQueue.breached => 'Nothing has breached',
          SupportQueue.critical => 'Nothing critical is open',
          SupportQueue.unassigned => 'Nothing waiting to be picked up',
        },
        emptyMessage: queue.blurb,
        errorMessage: 'Could not load the queue.',
        header: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const MyAgentCard(),
              FilterBar(
                selected: queue.name,
                onSelected: (value) {
                  for (final q in SupportQueue.values) {
                    if (q.name == value) {
                      ref.read(supportQueueProvider.notifier).set(q);
                      return;
                    }
                  }
                },
                options: [
                  for (final q in SupportQueue.values)
                    (value: q.name, label: q.label),
                ],
              ),
              Text(
                queue.blurb,
                style: TextStyle(color: bos.muted, fontSize: 12.5),
              ),
            ],
          ),
        ),
        itemBuilder: (context, ticket) => _QueueRow(ticket: ticket),
      ),
    );
  }
}

class _QueueRow extends ConsumerStatefulWidget {
  const _QueueRow({required this.ticket});

  final SupportTicket ticket;

  @override
  ConsumerState<_QueueRow> createState() => _QueueRowState();
}

class _QueueRowState extends ConsumerState<_QueueRow> {
  bool _busy = false;

  Future<void> _act(
    Future<void> Function(SupportQueueRepository repo) action,
    String success,
    String failure,
  ) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action(ref.read(supportQueueRepositoryProvider));
      // Every action here answers with an empty body, and most move the
      // ticket between queues, so the list reloads rather than being patched.
      await ref.read(supportQueueListProvider.notifier).refresh();
      messenger.showSnackBar(SnackBar(content: Text(success)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failure)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<SupportAgent?> _pickAgent() async {
    final agents = ref.read(assignableAgentsProvider).value ?? const [];
    if (agents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No agent is currently taking new tickets.'),
        ),
      );
      return null;
    }
    final id = await pickOne(
      context,
      options: [
        for (final agent in agents)
          (value: '${agent.id}', label: agent.displayName),
      ],
    );
    if (id == null) return null;
    for (final agent in agents) {
      if ('${agent.id}' == id) return agent;
    }
    return null;
  }

  Future<void> _assign() async {
    final agent = await _pickAgent();
    if (agent == null || !mounted) return;
    await _act(
      (repo) => repo.assign(widget.ticket.id, agent.id),
      '${agent.displayName} has it.',
      'Could not assign that ticket.',
    );
  }

  Future<void> _reassign() async {
    final agent = await _pickAgent();
    if (agent == null || !mounted) return;
    final reason = await askForText(
      context,
      title: 'Why the change?',
      message:
          'The reason is kept on the ticket. The endpoint requires it, so it '
          'cannot be left blank.',
      label: 'Reason',
      action: 'Reassign',
      required: true,
    );
    if (reason == null || !mounted) return;
    await _act(
      (repo) => repo.reassign(widget.ticket.id, agent.id, reason),
      'Moved to ${agent.displayName}.',
      'Could not reassign that ticket.',
    );
  }

  /// Records what the requester made of it. Both figures are required query
  /// parameters, so neither can be skipped.
  Future<void> _satisfaction() async {
    final rating = await pickOne(
      context,
      options: const [
        (value: '5', label: 'Very happy'),
        (value: '4', label: 'Happy'),
        (value: '3', label: 'Neither'),
        (value: '2', label: 'Unhappy'),
        (value: '1', label: 'Very unhappy'),
      ],
    );
    if (rating == null || !mounted) return;
    final feedback = await askForText(
      context,
      title: 'What did they say?',
      message: 'Kept against the ticket. The endpoint requires it.',
      label: 'Their words',
      action: 'Record it',
      required: true,
    );
    if (feedback == null || !mounted) return;
    await _act(
      (repo) => repo.recordSatisfaction(
        widget.ticket.id,
        int.parse(rating),
        feedback,
      ),
      'Recorded.',
      'Could not record that.',
    );
  }

  Future<void> _escalate() async {
    final reason = await askForText(
      context,
      title: 'Escalate ${widget.ticket.ticketNumber}?',
      message: 'Raises it to whoever handles escalations. The reason is kept '
          'on the ticket and is required.',
      label: 'Reason',
      action: 'Escalate',
      required: true,
      destructive: true,
    );
    if (reason == null || !mounted) return;
    await _act(
      (repo) => repo.escalate(widget.ticket.id, reason),
      'Escalated.',
      'Could not escalate that ticket.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final ticket = widget.ticket;

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
                    ticket.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                StatusChip(ticket.status, dense: true),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  PopupMenuButton<String>(
                    onSelected: (value) => switch (value) {
                      'assign' => _assign(),
                      'reassign' => _reassign(),
                      'escalate' => _escalate(),
                      'satisfaction' => _satisfaction(),
                      'notes' => InternalNotesScreen.open(context, ticket: ticket),
                      _ => _act(
                          (repo) => repo.recordFirstResponse(ticket.id),
                          'First response recorded.',
                          'Could not record that.',
                        ),
                    },
                    itemBuilder: (context) => [
                      // A ticket nobody holds is assigned; one somebody holds
                      // is reassigned. Offering both would be a choice with a
                      // wrong answer.
                      if (ticket.assignedToAgentName == null)
                        const PopupMenuItem(
                          value: 'assign',
                          child: Text('Assign it'),
                        )
                      else
                        const PopupMenuItem(
                          value: 'reassign',
                          child: Text('Hand it to somebody else'),
                        ),
                      const PopupMenuItem(
                        value: 'first-response',
                        child: Text('Record first response'),
                      ),
                      const PopupMenuItem(
                        value: 'notes',
                        child: Text('Internal notes'),
                      ),
                      // Only worth asking once the work is done.
                      if (TicketStatus.settled.contains(ticket.status))
                        const PopupMenuItem(
                          value: 'satisfaction',
                          child: Text('Record their verdict'),
                        ),
                      PopupMenuItem(
                        value: 'escalate',
                        child: Text(
                          'Escalate',
                          style: TextStyle(color: bos.danger),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                ticket.ticketNumber,
                Fmt.label(ticket.priority),
                ticket.assignedToAgentName ?? 'unassigned',
                Fmt.relative(ticket.createdAt),
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: bos.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Looks a ticket up by the number somebody reads off an email.
Future<void> showFindTicketDialog(BuildContext context, WidgetRef ref) async {
  final number = await askForText(
    context,
    title: 'Find a ticket',
    message: 'The number as it appears on the ticket or in an email.',
    label: 'Ticket number',
    action: 'Find it',
    required: true,
  );
  if (number == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    final ticket =
        await ref.read(supportQueueRepositoryProvider).byNumber(number);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${ticket.ticketNumber}: ${ticket.title} — '
          '${Fmt.label(ticket.status)}',
        ),
      ),
    );
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not find that ticket.')),
    );
  }
}
