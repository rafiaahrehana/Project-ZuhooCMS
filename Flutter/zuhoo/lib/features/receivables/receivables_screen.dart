import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/config_list.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import 'receivables_models.dart';
import 'receivables_repository.dart';
import 'receivables_sheets.dart';

/// What happens to an invoice after it goes out.
///
/// Three tabs for the three documents that follow it: the receipt that records
/// money arriving, the refund that sends money back, and the credit note that
/// reduces what is owed without any money moving at all.
class ReceivablesScreen extends ConsumerWidget {
  const ReceivablesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final permissions = ref.watch(permissionControllerProvider);

    if (!permissions.loaded && permissions.codes.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Receipts')),
        body: const Loader(),
      );
    }

    final tabs = <({String label, Widget view, VoidCallback? create})>[
      if (permissions.has(ReceivablesPermissions.receiptView))
        (label: 'Receipts', view: const _ReceiptsTab(), create: null),
      if (permissions.has(ReceivablesPermissions.invoiceView)) ...[
        (label: 'Refunds', view: const _RefundsTab(), create: null),
        (
          label: 'Credit notes',
          view: const _CreditNotesTab(),
          create: permissions.has(ReceivablesPermissions.creditNote)
              ? () => showCreditNoteSheet(context)
              : null,
        ),
      ],
    ];

    if (tabs.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Receipts')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Not available to you',
          message:
              'Receipts, refunds and credit notes need the invoice and payment '
              'permissions.',
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
                  title: const Text('Receipts'),
                  bottom: TabBar(
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

// ── Receipts ──────────────────────────────────────────────────

class _ReceiptsTab extends ConsumerStatefulWidget {
  const _ReceiptsTab();

  @override
  ConsumerState<_ReceiptsTab> createState() => _ReceiptsTabState();
}

class _ReceiptsTabState extends ConsumerState<_ReceiptsTab> {
  int? _busyId;

  /// Every receipt action answers with an empty body, so the list reloads
  /// rather than being patched — the status change also moves the row.
  Future<void> _act(
    int id,
    Future<void> Function(ReceivablesRepository repo) action,
    String success,
    String failure,
  ) async {
    setState(() => _busyId = id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action(ref.read(receivablesRepositoryProvider));
      await ref.read(receiptsProvider.notifier).refresh();
      messenger.showSnackBar(SnackBar(content: Text(success)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failure)));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _deposit(PaymentReceipt receipt) async {
    final bank = await askForText(
      context,
      title: 'Banked where?',
      message:
          'Which account the money was paid into. The endpoint requires it, so '
          'it cannot be left blank.',
      label: 'Bank',
      action: 'Record it',
      required: true,
    );
    if (bank == null || !mounted) return;
    await _act(
      receipt.id,
      (repo) => repo.depositReceipt(receipt.id, bank),
      'Recorded as banked.',
      'Could not record that deposit.',
    );
  }

  Future<void> _reverse(PaymentReceipt receipt) async {
    final reason = await askForText(
      context,
      title: 'Reverse ${receipt.receiptNumber}?',
      message:
          'For a bounced payment, or one applied to the wrong invoice. What it '
          'was against goes back to being owed.',
      label: 'Reason (optional)',
      action: 'Reverse it',
      destructive: true,
    );
    if (reason == null || !mounted) return;
    await _act(
      receipt.id,
      (repo) => repo.reverseReceipt(receipt.id, reason),
      'Reversed.',
      'Could not reverse that receipt.',
    );
  }

  Future<void> _delete(PaymentReceipt receipt) async {
    final confirmed = await confirmAction(
      context,
      title: 'Delete ${receipt.receiptNumber}?',
      message:
          'It goes without a trace. Reversing it keeps the record of what '
          'happened, which is usually what is wanted.',
      action: 'Delete',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyId = receipt.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(receivablesRepositoryProvider)
          .deleteReceipt(receipt.id);
      ref.read(receiptsProvider.notifier).remove(receipt.id);
      messenger.showSnackBar(const SnackBar(content: Text('Deleted.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not delete that receipt.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(permissionControllerProvider);
    final canConfirm = permissions.has(ReceivablesPermissions.receiptConfirm);
    final canDelete = permissions.has(ReceivablesPermissions.receiptDelete);

    return ConfigList<PaymentReceipt>(
      async: ref.watch(receiptsProvider),
      onRefresh: ref.read(receiptsProvider.notifier).refresh,
      emptyIcon: Icons.receipt_long_outlined,
      emptyTitle: 'No receipts yet',
      emptyMessage:
          'A receipt records money arriving against an invoice. It is confirmed '
          'once the payment clears, then marked as banked.',
      errorMessage: 'Could not load the receipts.',
      itemBuilder: (context, receipt) => _ReceiptCard(
        receipt: receipt,
        busy: _busyId == receipt.id,
        onConfirm: canConfirm && receipt.canConfirm
            ? () => _act(
                  receipt.id,
                  (repo) => repo.confirmReceipt(receipt.id),
                  'Confirmed.',
                  'Could not confirm that receipt.',
                )
            : null,
        onDeposit:
            canConfirm && receipt.canDeposit ? () => _deposit(receipt) : null,
        onReverse:
            canConfirm && receipt.canReverse ? () => _reverse(receipt) : null,
        onDelete: canDelete ? () => _delete(receipt) : null,
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({
    required this.receipt,
    required this.busy,
    this.onConfirm,
    this.onDeposit,
    this.onReverse,
    this.onDelete,
  });

  final PaymentReceipt receipt;
  final bool busy;
  final VoidCallback? onConfirm;
  final VoidCallback? onDeposit;
  final VoidCallback? onReverse;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    final actions = <RowAction>[
      if (onConfirm != null)
        RowAction(label: 'Confirm it cleared', onSelected: onConfirm!),
      if (onDeposit != null)
        RowAction(label: 'Mark as banked', onSelected: onDeposit!),
      if (onReverse != null)
        RowAction(label: 'Reverse', destructive: true, onSelected: onReverse!),
      if (onDelete != null)
        RowAction(label: 'Delete', destructive: true, onSelected: onDelete!),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        receipt.clientName ?? receipt.receiptNumber,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          receipt.receiptNumber,
                          if (receipt.invoiceNumber != null)
                            receipt.invoiceNumber!,
                          if (receipt.paymentMethod != null)
                            Fmt.label(receipt.paymentMethod),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: bos.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Fmt.money(receipt.amount),
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    StatusChip(receipt.status, dense: true),
                  ],
                ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (actions.isNotEmpty)
                  PopupMenuButton<int>(
                    onSelected: (index) => actions[index].onSelected(),
                    itemBuilder: (context) => [
                      for (var i = 0; i < actions.length; i++)
                        PopupMenuItem(
                          value: i,
                          child: Text(
                            actions[i].label,
                            style: actions[i].destructive
                                ? TextStyle(color: bos.danger)
                                : null,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [
                Fmt.date(receipt.paymentDate),
                if (receipt.depositedToBank != null)
                  'banked at ${receipt.depositedToBank}',
                if (receipt.transactionReference != null)
                  receipt.transactionReference!,
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: bos.muted, fontSize: 11.5),
            ),
            if (receipt.reversalReason != null) ...[
              const SizedBox(height: 8),
              Text(
                'Reversed: ${receipt.reversalReason}',
                style: TextStyle(color: bos.warning, fontSize: 11.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Refunds ───────────────────────────────────────────────────

class _RefundsTab extends ConsumerStatefulWidget {
  const _RefundsTab();

  @override
  ConsumerState<_RefundsTab> createState() => _RefundsTabState();
}

class _RefundsTabState extends ConsumerState<_RefundsTab> {
  int? _busyId;

  Future<void> _act(
    int id,
    Future<void> Function(ReceivablesRepository repo) action,
    String success,
    String failure,
  ) async {
    setState(() => _busyId = id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action(ref.read(receivablesRepositoryProvider));
      await ref.read(refundsProvider.notifier).refresh();
      messenger.showSnackBar(SnackBar(content: Text(success)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failure)));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _process(Refund refund) async {
    final confirmed = await confirmAction(
      context,
      title: 'Refund ${Fmt.money(refund.requestedAmount)}?',
      message:
          'The money goes back to ${refund.clientName ?? 'the client'}. This '
          'cannot be undone from here.',
      action: 'Refund it',
      destructive: false,
    );
    if (!confirmed || !mounted) return;
    await _act(
      refund.id,
      (repo) => repo.processRefund(refund.id),
      'Refunded.',
      'Could not process that refund.',
    );
  }

  Future<void> _reject(Refund refund) async {
    final reason = await askForText(
      context,
      title: 'Turn this refund down?',
      message: 'The reason is kept on the record and shown to whoever asked.',
      label: 'Reason (optional)',
      action: 'Reject',
      destructive: true,
    );
    if (reason == null || !mounted) return;
    await _act(
      refund.id,
      (repo) => repo.rejectRefund(refund.id, reason),
      'Rejected.',
      'Could not reject that refund.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final filter = ref.watch(refundFilterProvider);
    final canDecide =
        ref.watch(permissionControllerProvider).has(ReceivablesPermissions.invoiceRefund);

    return ConfigList<Refund>(
      async: ref.watch(refundsProvider),
      onRefresh: ref.read(refundsProvider.notifier).refresh,
      emptyIcon: Icons.undo_rounded,
      emptyTitle: filter == null ? 'No refunds asked for' : 'None like that',
      emptyMessage:
          'Refunds are raised against a cancelled request or a disputed '
          'invoice, and are processed or turned down here.',
      errorMessage: 'Could not load the refunds.',
      header: FilterBar(
        selected: filter,
        onSelected: ref.read(refundFilterProvider.notifier).set,
        options: [
          (value: null, label: 'All'),
          for (final status in RefundStatus.all)
            (value: status, label: Fmt.label(status)),
        ],
      ),
      itemBuilder: (context, refund) => ConfigRow(
        title: refund.clientName ?? 'Refund ${refund.id}',
        // A settled refund is drawn muted — it is history, not a decision
        // waiting on somebody.
        active: !refund.isSettled,
        inactiveLabel: Fmt.label(refund.status),
        subtitle: [
          if (refund.invoiceNumber != null) refund.invoiceNumber!,
          if (refund.serviceRequestTitle != null) refund.serviceRequestTitle!,
          // Whichever reason applies: why it was asked for, or why it was
          // turned down.
          if (refund.rejectionReason != null)
            refund.rejectionReason!
          else if (refund.reason != null)
            refund.reason!,
        ].join(' · '),
        trailingLabel: Fmt.money(refund.requestedAmount),
        busy: _busyId == refund.id,
        actions: [
          if (canDecide && refund.canDecide) ...[
            RowAction(label: 'Refund it', onSelected: () => _process(refund)),
            RowAction(
              label: 'Turn it down',
              destructive: true,
              onSelected: () => _reject(refund),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Credit notes ──────────────────────────────────────────────

class _CreditNotesTab extends ConsumerWidget {
  const _CreditNotesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ConfigList<CreditNote>(
      async: ref.watch(creditNotesProvider),
      onRefresh: ref.read(creditNotesProvider.notifier).refresh,
      emptyIcon: Icons.note_alt_outlined,
      emptyTitle: 'No credit notes',
      emptyMessage:
          'A credit note reduces what an invoice is owed without any money '
          'moving — a discount agreed after the fact, or a billing error.',
      errorMessage: 'Could not load the credit notes.',
      itemBuilder: (context, note) => ConfigRow(
        title: note.clientName ?? note.creditNoteNumber,
        active: true,
        subtitle: [
          note.creditNoteNumber,
          if (note.invoiceNumber != null) 'against ${note.invoiceNumber}',
          if (note.reason != null) note.reason!,
        ].join(' · '),
        trailingLabel: Fmt.money(note.amount),
      ),
    );
  }
}
