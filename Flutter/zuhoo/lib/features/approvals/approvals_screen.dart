import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/form_sheet.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/skeleton.dart' show SkeletonList;
import 'approval_models.dart';
import 'approval_repository.dart';

/// The mobile-first "what's waiting on me" inbox: every pending leave
/// request, expense claim, vendor bill, journal entry, payroll run and
/// service-request stage approval this account can decide, in one list,
/// instead of hunting across each module's own tab. Every action here calls
/// straight through to that module's own repository — this screen adds no
/// new backend behaviour, only a unified front door to what already exists.
class ApprovalsScreen extends ConsumerWidget {
  const ApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(approvalInboxProvider);
    final bos = Theme.of(context).bos;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Approvals'
          '${async.value != null && async.value!.isNotEmpty ? ' (${async.value!.length})' : ''}',
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(approvalInboxProvider.notifier).refresh(),
        child: switch (async) {
          AsyncData(:final value) when value.isEmpty => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                EmptyState(
                  icon: Icons.task_alt_rounded,
                  title: 'Nothing waiting on you',
                  message: 'Approvals across the app will show up here.',
                ),
              ],
            ),
          AsyncData(:final value) => ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: value.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _ApprovalCard(item: value[i]),
            ),
          AsyncError() => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                ErrorState(
                  message: 'Could not load your approvals.',
                  onRetry: () =>
                      ref.read(approvalInboxProvider.notifier).refresh(),
                ),
              ],
            ),
          _ => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [SkeletonList(rows: 4, hasLeading: false)],
            ),
        },
      ),
      backgroundColor: bos.bgSubtle,
    );
  }
}

class _ApprovalCard extends ConsumerStatefulWidget {
  const _ApprovalCard({required this.item});

  final ApprovalItem item;

  @override
  ConsumerState<_ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends ConsumerState<_ApprovalCard> {
  bool _busy = false;

  Future<void> _decide({required bool approve}) async {
    final item = widget.item;
    String? reason;

    if (!approve) {
      reason = await _askReason(item);
      if (reason == null) return;
    } else if (item.rejectRequiresReason) {
      // Requiring a reason to reject but not to approve mirrors every other
      // approval screen in the app (leave, expenses, requests) — a decision
      // to proceed needs no justification, a refusal does.
      final confirmed = await _confirmApprove(item);
      if (confirmed != true) return;
    }

    if (!mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(approvalInboxProvider.notifier)
          .decide(item, approve: approve, reason: reason);
      messenger.showSnackBar(
        SnackBar(content: Text(approve ? 'Approved.' : 'Rejected.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not record that decision.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmApprove(ApprovalItem item) => showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) {
          final bos = Theme.of(sheetContext).bos;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Approve this ${item.kind.label.toLowerCase()}?',
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.title,
                  style: TextStyle(color: bos.textSecondary, fontSize: 13.5),
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Approve'),
                ),
              ],
            ),
          );
        },
      );

  Future<String?> _askReason(ApprovalItem item) {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => FormSheetFrame(
        title: 'Why are you turning this down?',
        formKey: formKey,
        error: null,
        onDismissError: () {},
        action: 'Reject',
        submitting: false,
        onSubmit: () {
          if (!(formKey.currentState?.validate() ?? false)) return;
          Navigator.pop(sheetContext, controller.text.trim());
        },
        children: [
          Text(
            item.title,
            style: TextStyle(
              color: Theme.of(sheetContext).bos.muted,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: controller,
            maxLines: 3,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Reason',
              alignLabelWithHint: true,
            ),
            validator: (value) => (value == null || value.trim().isEmpty)
                ? 'A reason is required.'
                : null,
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  static IconData _iconFor(ApprovalKind kind) => switch (kind) {
        ApprovalKind.leave => Icons.event_note_rounded,
        ApprovalKind.expense => Icons.payments_outlined,
        ApprovalKind.vendorBill => Icons.outbox_outlined,
        ApprovalKind.journalEntry => Icons.edit_note_outlined,
        ApprovalKind.payrollRun => Icons.request_quote_outlined,
        ApprovalKind.serviceRequestStage => Icons.fact_check_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final item = widget.item;
    final canReject = kindSupportsReject(item.kind);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 34,
                width: 34,
                decoration: BoxDecoration(
                  color: bos.brandSoft,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(_iconFor(item.kind), size: 17, color: bos.brandInk),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.kind.label,
                      style: TextStyle(
                        color: bos.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (item.amount != null)
                Text(
                  Fmt.money(item.amount),
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                StatusChip(item.status, dense: true),
            ],
          ),
          if (item.subtitle != null && item.subtitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              item.subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: bos.textSecondary, fontSize: 13),
            ),
          ],
          if (item.requestedBy != null || item.date != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (item.requestedBy != null) ...[
                  Icon(Icons.person_outline_rounded, size: 13, color: bos.muted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      item.requestedBy!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: bos.muted, fontSize: 12),
                    ),
                  ),
                ],
                if (item.date != null)
                  Text(
                    Fmt.relative(item.date),
                    style: TextStyle(color: bos.muted, fontSize: 11.5),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          if (_busy)
            const Loader(padding: 6)
          else
            Row(
              children: [
                if (canReject) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _decide(approve: false),
                      icon: const Icon(Icons.close_rounded, size: 17),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: bos.danger,
                        side:
                            BorderSide(color: bos.danger.withValues(alpha: 0.4)),
                        minimumSize: const Size.fromHeight(42),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _decide(approve: true),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(42),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
