import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import 'itam_models.dart';
import 'software_detail_screen.dart';
import 'itam_repository.dart';

/// One person's offboarding: five things that have to happen before they go.
///
/// The steps are one-way. The backend exposes an endpoint to mark each one
/// done and none to undo it, so these are buttons rather than switches — a
/// switch that cannot travel back is a lie about what the screen can do.
class OffboardingDetailScreen extends ConsumerStatefulWidget {
  const OffboardingDetailScreen({super.key, required this.checklist});

  final OffboardingChecklist checklist;

  static void open(
    BuildContext context, {
    required OffboardingChecklist checklist,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OffboardingDetailScreen(checklist: checklist),
      ),
    );
  }

  @override
  ConsumerState<OffboardingDetailScreen> createState() =>
      _OffboardingDetailScreenState();
}

class _OffboardingDetailScreenState
    extends ConsumerState<OffboardingDetailScreen> {
  late OffboardingChecklist _checklist = widget.checklist;
  String? _busyStep;

  /// Removes the whole checklist.
  ///
  /// Not a step back — there is no way to un-tick one. This throws away the
  /// record that the leaver was being processed at all, which is only ever
  /// right when the checklist was opened by mistake.
  Future<void> _delete() async {
    final confirmed = await confirmAction(
      context,
      title: 'Delete this checklist?',
      message: 'Everything ticked off so far goes with it. Do this only if '
          'the checklist should never have been opened.',
      action: 'Delete',
    );
    if (!confirmed || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(itamRepositoryProvider).deleteChecklist(_checklist.id);
      ref.invalidate(pendingOffboardingProvider);
      await ref.read(offboardingProvider.notifier).refresh();
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Deleted.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not delete that checklist.')),
      );
    }
  }

  Future<void> _complete(OffboardingStep step) async {
    final notes = await showDialog<String>(
      context: context,
      builder: (context) => _NotesDialog(step: step),
    );
    // Null means dismissed. An empty string is a deliberate "no notes".
    if (notes == null || !mounted) return;

    setState(() => _busyStep = step.key);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await ref.read(itamRepositoryProvider).completeStep(
            _checklist.id,
            step.path,
            notes: notes,
          );
      ref.read(offboardingProvider.notifier).apply(updated);
      if (!mounted) return;
      setState(() => _checklist = updated);
      messenger.showSnackBar(
        SnackBar(content: Text('${step.label} — recorded.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not record that step.')),
      );
    } finally {
      if (mounted) setState(() => _busyStep = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final canManage = ref
        .watch(permissionControllerProvider)
        .has(ItamPermissions.offboardingManage);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(
        title: Text(_checklist.personLabel),
        actions: [
          if (canManage)
            PopupMenuButton<String>(
              onSelected: (_) => _delete(),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'Delete the checklist',
                    style: TextStyle(color: bos.danger),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _Summary(checklist: _checklist),
          if (!canManage) ...[
            const SizedBox(height: 14),
            const MessageBanner.info(
              'You can see this checklist but not tick steps off. That needs '
              'the offboarding management permission.',
            ),
          ],
          const SizedBox(height: 20),
          const SectionHeader('Steps', icon: Icons.checklist_rounded),
          for (final step in _checklist.steps)
            _StepRow(
              step: step,
              canManage: canManage,
              busy: _busyStep == step.key,
              onComplete: () => _complete(step),
            ),
          const SizedBox(height: 18),
          // What they still hold, so "licences revoked" can be ticked off
          // knowing what it actually covers.
          _LicencesHeld(employeeId: _checklist.employeeId),
          if (_checklist.overallNotes?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 18),
            const SectionHeader('Notes', icon: Icons.sticky_note_2_outlined),
            AppCard(
              child: Text(
                _checklist.overallNotes!.trim(),
                style: TextStyle(color: bos.text, fontSize: 13, height: 1.4),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.checklist});

  final OffboardingChecklist checklist;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final done = checklist.stepsDone;
    final total = checklist.steps.length;

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  checklist.completed
                      ? 'Everything is done'
                      : '$done of $total steps done',
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (checklist.completed)
                const StatusChip('COMPLETED', label: 'Done', dense: true)
              else if (checklist.isOverdue)
                const StatusChip('OVERDUE', label: 'Overdue', dense: true),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 7,
              backgroundColor: bos.neutralSoft,
              valueColor: AlwaysStoppedAnimation(
                checklist.completed ? bos.success : bos.brand,
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (checklist.offboardingDate != null)
            _Line(
              icon: Icons.event_busy_outlined,
              text: 'Last day ${Fmt.date(checklist.offboardingDate)}',
            ),
          if (checklist.targetCompletionDate != null)
            _Line(
              icon: Icons.flag_outlined,
              text: checklist.completed
                  ? 'Completed ${Fmt.date(checklist.completionDate)}'
                  : 'Target ${Fmt.date(checklist.targetCompletionDate)}',
              tone: checklist.isOverdue ? bos.danger : null,
            ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, this.tone});

  final IconData icon;
  final String text;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(icon, size: 14, color: tone ?? bos.muted),
          const SizedBox(width: 7),
          Text(
            text,
            style: TextStyle(
              color: tone ?? bos.muted,
              fontSize: 12.5,
              fontWeight: tone == null ? FontWeight.w500 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.canManage,
    required this.busy,
    required this.onComplete,
  });

  final OffboardingStep step;
  final bool canManage;
  final bool busy;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              step.done
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 22,
              color: step.done ? bos.success : bos.border,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.label,
                    style: TextStyle(
                      color: step.done ? bos.textSecondary : bos.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (step.done && step.date != null)
                    Text(
                      '${Fmt.date(step.date)}'
                      '${step.by != null ? ' · ${step.by}' : ''}',
                      style: TextStyle(color: bos.muted, fontSize: 11.5),
                    ),
                  if (step.notes?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 6),
                    Text(
                      step.notes!.trim(),
                      style: TextStyle(
                        color: bos.textSecondary,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!step.done && canManage) ...[
              const SizedBox(width: 8),
              if (busy)
                const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                TextButton(
                  onPressed: onComplete,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Mark done'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Optional notes against a step. Optional server-side too, so Skip is a real
/// choice rather than a way to abandon the action.
class _NotesDialog extends StatefulWidget {
  const _NotesDialog({required this.step});

  final OffboardingStep step;

  @override
  State<_NotesDialog> createState() => _NotesDialogState();
}

class _NotesDialogState extends State<_NotesDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.step.label),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MessageBanner.warning(
            'This cannot be undone from the app — there is no endpoint to '
            'clear a step once it is marked done.',
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 2,
            maxLength: 300,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              hintText: 'e.g. Laptop and charger returned, dock still out',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Mark done'),
        ),
      ],
    );
  }
}

/// The software seats one person still holds.
///
/// Read straight from the licence register rather than from the checklist:
/// the checklist records that revoking *happened*, and this says what there
/// is to revoke.
class _LicencesHeld extends ConsumerWidget {
  const _LicencesHeld({required this.employeeId});

  final int employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(licencesHeldProvider(employeeId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Software they hold',
            icon: Icons.workspaces_outline),
        const SizedBox(height: 8),
        async.when(
          loading: () => const Loader(padding: 8),
          // A failure here must not look like "they hold nothing" — that would
          // invite ticking the step off wrongly.
          error: (error, _) => MessageBanner.warning(
            'Could not check what software they hold.',
          ),
          data: (seats) {
            if (seats.isEmpty) {
              return AppCard(
                child: Text(
                  'No software seats are assigned to them.',
                  style: TextStyle(color: bos.muted, fontSize: 13),
                ),
              );
            }
            return AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final seat in seats)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Icon(Icons.circle, size: 6, color: bos.muted),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              seat.softwareName ?? 'Licence ${seat.id}',
                              style:
                                  TextStyle(color: bos.text, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
