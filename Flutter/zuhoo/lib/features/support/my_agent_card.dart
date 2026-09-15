import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import '../support_admin/support_admin_models.dart';
import '../support_admin/support_admin_repository.dart';

/// The signed-in user's own agent record, if they have one.
///
/// The lookup answers 404 for anybody who is not an agent, which is most
/// people. The card treats that as "not an agent" and shows nothing, rather
/// than as a failure — being absent is the ordinary case.
final myAgentProvider = FutureProvider.autoDispose<SupportAgent?>((ref) async {
  final userId = ref.watch(currentUserProvider)?.id;
  if (userId == null) return null;
  try {
    return await ref.read(supportAdminRepositoryProvider).agentForUser(userId);
  } on ApiException {
    return null;
  }
});

/// Where an agent stands: their status, whether they are taking anything new,
/// and how loaded they are.
///
/// Changing the status and the accepting flag is the same pair of endpoints
/// the agents admin screen uses. An agent may set their own — the backend
/// gates on the support roles, not on whose record it is — which is the point:
/// stepping away should not need a manager.
class MyAgentCard extends ConsumerStatefulWidget {
  const MyAgentCard({super.key});

  @override
  ConsumerState<MyAgentCard> createState() => _MyAgentCardState();
}

class _MyAgentCardState extends ConsumerState<MyAgentCard> {
  bool _busy = false;

  Future<void> _run(
    Future<void> Function(SupportAdminRepository) action,
    String done,
  ) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action(ref.read(supportAdminRepositoryProvider));
      ref.invalidate(myAgentProvider);
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('That did not go through.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(SupportAgent agent) async {
    final status = await pickOne(
      context,
      options: [
        for (final value in agentStatuses)
          (value: value, label: Fmt.label(value)),
      ],
      current: agent.status,
    );
    if (status == null || status == agent.status || !mounted) return;
    await _run(
      (repo) => repo.setAgentStatus(agent.id, status),
      'You are now ${Fmt.label(status).toLowerCase()}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final agent = ref.watch(myAgentProvider).value;

    if (agent == null) return const SizedBox.shrink();

    final facts = <String>[
      if (agent.maxConcurrentTickets > 0)
        'up to ${agent.maxConcurrentTickets} at once',
      '${agent.totalTicketsHandled} handled',
      if (agent.satisfactionScore != null)
        '${agent.satisfactionScore!.toStringAsFixed(1)} out of 5',
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    agent.displayName,
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_busy)
                  const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  GestureDetector(
                    onTap: () => _setStatus(agent),
                    child: StatusChip(agent.status, dense: true),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              facts.join('  ·  '),
              style: TextStyle(color: bos.muted, fontSize: 11.5),
            ),
            const SizedBox(height: 6),
            SwitchListTile.adaptive(
              value: agent.acceptingTickets,
              onChanged: _busy
                  ? null
                  : (value) => _run(
                        (repo) => repo.setAcceptingTickets(agent.id, value),
                        value
                            ? 'Taking new tickets again.'
                            : 'No new tickets will be routed to you.',
                      ),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                'Taking new tickets',
                style: TextStyle(color: bos.text, fontSize: 13.5),
              ),
              subtitle: Text(
                // The distinction matters: turning this off stops new work
                // arriving but leaves everything already assigned with you.
                'Off means nothing new is routed to you. What you already '
                'have stays yours.',
                style: TextStyle(color: bos.muted, fontSize: 11.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
