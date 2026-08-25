import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/config_list.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import '../finance/finance_models.dart' show Expense, ExpenseStatus;
import 'platform_models.dart';
import 'platform_repository.dart';

/// The platform's own spending — the operator's books, not a tenant's.
///
/// Same shape as a company's expenses, and the same DTO underneath, so the
/// models come from the finance module rather than being written twice. What
/// differs is who may see it: `PLATFORM_ACCOUNTANT` or `SUPER_ADMIN`.
///
/// **Editing is deliberately absent.** The PATCH assigns description, amount,
/// category, expense account, date, receipt and notes with no null check, and
/// the response does not carry the expense account's id — so an edit posted
/// from here would silently detach the expense from its account. Rejecting and
/// re-filing is the honest path, and it is what the status flow is for.

/// Which slice of the ledger is showing. Null is everything; [mineFilter] is
/// the one entry that is not a status.
class PlatformExpenseFilterController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? value) {
    if (state == value) return;
    state = value;
  }
}

final platformExpenseFilterProvider =
    NotifierProvider<PlatformExpenseFilterController, String?>(
  PlatformExpenseFilterController.new,
);

/// Not an `ExpenseStatus` — a pseudo-filter for `/my-expenses`.
const mineFilter = 'MINE';

class PlatformExpensesController extends AsyncNotifier<List<Expense>> {
  @override
  Future<List<Expense>> build() {
    ref.watch(currentUserProvider);
    ref.watch(platformExpenseFilterProvider);
    return _load();
  }

  Future<List<Expense>> _load() async {
    final filter = ref.read(platformExpenseFilterProvider);
    final page = await ref.read(platformRepositoryProvider).platformExpenses(
          status: filter == mineFilter ? null : filter,
          mineOnly: filter == mineFilter,
        );
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  void remove(int id) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current)
        if (row.id != id) row,
    ]);
  }
}

final platformExpensesProvider =
    AsyncNotifierProvider<PlatformExpensesController, List<Expense>>(
  PlatformExpensesController.new,
);

class PlatformExpensesTab extends ConsumerStatefulWidget {
  const PlatformExpensesTab({super.key});

  @override
  ConsumerState<PlatformExpensesTab> createState() =>
      _PlatformExpensesTabState();
}

class _PlatformExpensesTabState extends ConsumerState<PlatformExpensesTab> {
  int? _busyId;

  /// Every action here returns an empty body, so the list is reloaded rather
  /// than patched — the status change also moves the row between filters.
  Future<void> _run(
    int id,
    Future<void> Function() action,
    String success,
    String failure,
  ) async {
    setState(() => _busyId = id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      await ref.read(platformExpensesProvider.notifier).refresh();
      messenger.showSnackBar(SnackBar(content: Text(success)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failure)));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _approve(Expense expense) async {
    final notes = await askForText(
      context,
      title: 'Approve ${expense.expenseNumber}?',
      message: 'A note is required — the endpoint refuses an approval without '
          'one.',
      label: 'Note',
      action: 'Approve',
      required: true,
    );
    if (notes == null || !mounted) return;
    final repo = ref.read(platformRepositoryProvider);
    await _run(
      expense.id,
      () => repo.approvePlatformExpense(expense.id, notes),
      'Approved.',
      'Could not approve that expense.',
    );
  }

  Future<void> _reject(Expense expense) async {
    final reason = await askForText(
      context,
      title: 'Reject ${expense.expenseNumber}?',
      message: 'The reason is shown to whoever filed it, and is required.',
      label: 'Reason',
      action: 'Reject',
      required: true,
      destructive: true,
    );
    if (reason == null || !mounted) return;
    final repo = ref.read(platformRepositoryProvider);
    await _run(
      expense.id,
      () => repo.rejectPlatformExpense(expense.id, reason),
      'Rejected.',
      'Could not reject that expense.',
    );
  }

  Future<void> _markPaid(Expense expense) async {
    final result = await showDialog<({String method, String reference})>(
      context: context,
      builder: (dialogContext) => const _MarkPaidDialog(),
    );
    if (result == null || !mounted) return;
    final repo = ref.read(platformRepositoryProvider);
    await _run(
      expense.id,
      () => repo.markPlatformExpensePaid(
        expense.id,
        method: result.method,
        reference: result.reference,
      ),
      'Marked as paid.',
      'Could not record that payment.',
    );
  }

  Future<void> _delete(Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${expense.expenseNumber}?'),
        content: const Text(
          'It goes from the ledger entirely, leaving no record that it was '
          'ever filed. Rejecting it keeps the trail.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Never mind'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).bos.danger,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyId = expense.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(platformRepositoryProvider)
          .deletePlatformExpense(expense.id);
      ref.read(platformExpensesProvider.notifier).remove(expense.id);
      messenger.showSnackBar(
        SnackBar(content: Text('${expense.expenseNumber} deleted.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not delete that expense.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(platformExpenseFilterProvider);
    final canDelete =
        ref.watch(currentUserProvider)?.hasAnyRole(platformExpenseDeleteRoles) ??
            false;

    return ConfigList<Expense>(
      async: ref.watch(platformExpensesProvider),
      onRefresh: ref.read(platformExpensesProvider.notifier).refresh,
      emptyIcon: Icons.receipt_long_outlined,
      emptyTitle: filter == null ? 'Nothing filed yet' : 'Nothing here',
      emptyMessage: filter == null
          ? "The platform's own spending is recorded here — hosting, tools, "
              'travel and anything else the operator pays for.'
          : 'Try another filter, or clear it to see everything.',
      errorMessage: 'Could not load the expenses.',
      header: FilterBar(
        selected: filter,
        onSelected: ref.read(platformExpenseFilterProvider.notifier).set,
        options: [
          (value: null, label: 'All'),
          (value: mineFilter, label: 'Mine'),
          for (final status in ExpenseStatus.all)
            (value: status, label: Fmt.label(status)),
        ],
      ),
      itemBuilder: (context, expense) => _ExpenseRow(
        expense: expense,
        busy: _busyId == expense.id,
        onApprove: () => _approve(expense),
        onReject: () => _reject(expense),
        onMarkPaid: () => _markPaid(expense),
        onDelete: canDelete ? () => _delete(expense) : null,
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({
    required this.expense,
    required this.busy,
    required this.onApprove,
    required this.onReject,
    required this.onMarkPaid,
    this.onDelete,
  });

  final Expense expense;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onMarkPaid;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    // Only a pending expense can be decided, and only an approved one can be
    // paid. Anything else offers nothing but deletion.
    final actions = <RowAction>[
      if (expense.status == ExpenseStatus.pending) ...[
        RowAction(label: 'Approve', onSelected: onApprove),
        RowAction(label: 'Reject', onSelected: onReject),
      ],
      if (expense.status == ExpenseStatus.approved)
        RowAction(label: 'Mark as paid', onSelected: onMarkPaid),
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
                  child: Text(
                    expense.title ?? expense.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  Fmt.money(expense.amount),
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                expense.expenseNumber,
                Fmt.date(expense.expenseDate),
                if (expense.vendorName != null) expense.vendorName!,
                if (expense.submittedByName != null) expense.submittedByName!,
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: bos.muted, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                StatusChip(expense.status, dense: true),
                const Spacer(),
                if (busy)
                  const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (actions.isNotEmpty)
                  PopupMenuButton<int>(
                    padding: EdgeInsets.zero,
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
          ],
        ),
      ),
    );
  }
}

/// How the reimbursement was made. Both fields are optional server-side, so
/// this can be confirmed empty.
class _MarkPaidDialog extends StatefulWidget {
  const _MarkPaidDialog();

  @override
  State<_MarkPaidDialog> createState() => _MarkPaidDialogState();
}

class _MarkPaidDialogState extends State<_MarkPaidDialog> {
  final _method = TextEditingController();
  final _reference = TextEditingController();

  @override
  void dispose() {
    _method.dispose();
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record the payment'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _method,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'How it was paid (optional)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reference,
            decoration: const InputDecoration(
              labelText: 'Reference (optional)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Never mind'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            (method: _method.text, reference: _reference.text),
          ),
          child: const Text('Mark as paid'),
        ),
      ],
    );
  }
}
