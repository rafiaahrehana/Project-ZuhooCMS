import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import 'crm_models.dart';
import 'crm_repository.dart';

/// What a timeline is attached to.
///
/// The endpoint takes either a client or an opportunity, never both, and
/// answers with everything logged against whichever was given. Modelled as a
/// pair so the providers key on it cleanly.
typedef ActivityScope = ({int? clientId, int? opportunityId});

final activitiesProvider =
    FutureProvider.autoDispose.family<List<CrmActivity>, ActivityScope>(
  (ref, scope) async {
    final page = await ref.read(crmRepositoryProvider).activities(
          clientId: scope.clientId,
          opportunityId: scope.opportunityId,
        );
    return page.content;
  },
);

/// Everything that has happened with a client or a deal.
///
/// The same shape as a lead's timeline, and deliberately so: a call is a call
/// whether it was about a lead, a client or a deal. What differs is only what
/// it is hung off.
class ActivityTimeline extends ConsumerStatefulWidget {
  const ActivityTimeline({
    super.key,
    this.clientId,
    this.opportunityId,
  });

  final int? clientId;
  final int? opportunityId;

  @override
  ConsumerState<ActivityTimeline> createState() => _ActivityTimelineState();
}

class _ActivityTimelineState extends ConsumerState<ActivityTimeline> {
  int? _busyId;

  ActivityScope get _scope =>
      (clientId: widget.clientId, opportunityId: widget.opportunityId);

  Future<void> _run(
    Future<void> Function(CrmRepository) action,
    String done,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action(ref.read(crmRepositoryProvider));
      ref.invalidate(activitiesProvider(_scope));
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('That did not go through.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _complete(CrmActivity activity) async {
    setState(() => _busyId = activity.id);
    await _run(
      (repo) => repo.completeActivity(activity.id),
      'Marked done.',
    );
  }

  Future<void> _delete(CrmActivity activity) async {
    final confirmed = await confirmAction(
      context,
      title: 'Remove this entry?',
      message: 'It goes from the timeline for good.',
      action: 'Remove',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyId = activity.id);
    await _run((repo) => repo.deleteActivity(activity.id), 'Removed.');
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(activitiesProvider(_scope));
    // Role-gated, not permission-gated: CrmActivityController is guarded by
    // @PreAuthorize on COMPANY_OWNER and EMPLOYEE with no permission code of
    // its own, so anybody who is not a portal client qualifies.
    final canWrite = !(ref.watch(currentUserProvider)?.isClient ?? true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Activity',
          icon: Icons.history_rounded,
          trailing: TextButton.icon(
            onPressed: () => showActivitySummarySheet(
              context,
              clientId: widget.clientId,
              opportunityId: widget.opportunityId,
            ),
            icon: const Icon(Icons.auto_awesome_outlined, size: 16),
            label: const Text('Summarise'),
          ),
        ),
        AppCard(
          child: async.when(
            loading: () => const Loader(padding: 12),
            error: (error, _) => Text(
              error is ApiException
                  ? error.message
                  : 'Could not load the activity.',
              style: TextStyle(color: bos.muted, fontSize: 13),
            ),
            data: (activities) => activities.isEmpty
                ? Text(
                    'Nothing logged yet.',
                    style: TextStyle(color: bos.muted, fontSize: 13),
                  )
                : Column(
                    children: [
                      for (final activity in activities)
                        _ActivityRow(
                          activity: activity,
                          busy: _busyId == activity.id,
                          // System entries are the audit trail — a stage
                          // change, a status change. Letting somebody tick one
                          // off or delete it would make the trail worth less
                          // than nothing.
                          onComplete: canWrite &&
                                  !activity.systemGenerated &&
                                  !activity.completed
                              ? () => _complete(activity)
                              : null,
                          onDelete: canWrite && !activity.systemGenerated
                              ? () => _delete(activity)
                              : null,
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.activity,
    required this.busy,
    this.onComplete,
    this.onDelete,
  });

  final CrmActivity activity;
  final bool busy;
  final VoidCallback? onComplete;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final hasMenu = onComplete != null || onDelete != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              activity.completed
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 16,
              color: activity.completed ? bos.success : bos.muted,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.subject,
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (activity.description != null &&
                    activity.description!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      activity.description!,
                      style: TextStyle(
                        color: bos.textSecondary,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  [
                    Fmt.label(activity.type),
                    Fmt.relative(activity.activityDate),
                    if (activity.systemGenerated) 'automatic',
                  ].join('  ·  '),
                  style: TextStyle(color: bos.muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          if (busy)
            const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (hasMenu)
            PopupMenuButton<String>(
              onSelected: (value) =>
                  value == 'done' ? onComplete?.call() : onDelete?.call(),
              itemBuilder: (context) => [
                if (onComplete != null)
                  const PopupMenuItem(value: 'done', child: Text('Mark done')),
                if (onDelete != null)
                  PopupMenuItem(
                    value: 'delete',
                    child:
                        Text('Remove', style: TextStyle(color: bos.danger)),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A drafted read on everything that has happened with a client or a deal.
///
/// Asking is what produces it — nothing is saved — and it is labelled as
/// machine-written wherever it appears, because a précis of a customer
/// relationship must not be mistaken for a colleague's note.
Future<void> showActivitySummarySheet(
  BuildContext context, {
  int? clientId,
  int? opportunityId,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ActivitySummarySheet(
        clientId: clientId,
        opportunityId: opportunityId,
      ),
    );

class _ActivitySummarySheet extends ConsumerStatefulWidget {
  const _ActivitySummarySheet({this.clientId, this.opportunityId});

  final int? clientId;
  final int? opportunityId;

  @override
  ConsumerState<_ActivitySummarySheet> createState() =>
      _ActivitySummarySheetState();
}

class _ActivitySummarySheetState
    extends ConsumerState<_ActivitySummarySheet> {
  late final Future<String> _summary =
      ref.read(crmRepositoryProvider).summariseActivity(
            clientId: widget.clientId,
            opportunityId: widget.opportunityId,
          );

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Where things stand',
            style: TextStyle(
              color: bos.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Written by the assistant, not by a person.',
            style: TextStyle(
              color: bos.muted,
              fontSize: 11.5,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 14),
          FutureBuilder<String>(
            future: _summary,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Loader(padding: 20, message: 'Reading it');
              }
              if (snapshot.hasError) {
                final error = snapshot.error;
                return MessageBanner.error(
                  error is ApiException
                      ? error.message
                      : 'Could not summarise this.',
                );
              }

              final summary = snapshot.data?.trim() ?? '';
              return summary.isEmpty
                  ? Text(
                      'Nothing came back. There may be too little logged to '
                      'say anything about.',
                      style: TextStyle(
                        color: bos.muted,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    )
                  : SelectableText(
                      summary,
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 13.5,
                        height: 1.6,
                      ),
                    );
            },
          ),
        ],
      ),
    );
  }
}
