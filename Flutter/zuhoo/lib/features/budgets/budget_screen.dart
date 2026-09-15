import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/config_list.dart';
import '../../shared/widgets/form_sheet.dart';
import '../../shared/widgets/prompts.dart';
import '../../shared/widgets/primitives.dart';
import 'budget_models.dart';
import 'budget_repository.dart';

/// Per-category spending caps for a fiscal year, with what's actually been
/// spent tracked live against each one.
class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final permissions = ref.watch(permissionControllerProvider);
    final year = ref.watch(budgetYearProvider);
    final canManage = permissions.has(BudgetPermissions.manage);

    if (!permissions.loaded && permissions.codes.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Budgets')),
        body: const Loader(),
      );
    }

    if (!permissions.has(BudgetPermissions.view)) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Budgets')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Not available to you',
          message: 'Budgets needs the BUDGET_VIEW permission.',
        ),
      );
    }

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(
        title: const Text('Budgets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Previous year',
            onPressed: () =>
                ref.read(budgetYearProvider.notifier).set(year - 1),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text('FY $year', style: TextStyle(color: bos.text)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Next year',
            onPressed: () =>
                ref.read(budgetYearProvider.notifier).set(year + 1),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => showBudgetSheet(context, fiscalYear: year),
              backgroundColor: bos.brand,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New'),
            )
          : null,
      body: _BudgetList(canManage: canManage),
    );
  }
}

class _BudgetList extends ConsumerStatefulWidget {
  const _BudgetList({required this.canManage});

  final bool canManage;

  @override
  ConsumerState<_BudgetList> createState() => _BudgetListState();
}

class _BudgetListState extends ConsumerState<_BudgetList> {
  int? _busyId;

  Future<void> _delete(Budget budget) async {
    final confirmed = await confirmAction(
      context,
      title: 'Delete the ${budget.category} budget?',
      message: 'FY ${budget.fiscalYear}. This cannot be undone.',
      action: 'Delete',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyId = budget.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(budgetRepositoryProvider).delete(budget.id);
      ref.read(budgetsProvider.notifier).remove(budget.id);
      messenger.showSnackBar(const SnackBar(content: Text('Budget deleted.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not delete that budget.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final year = ref.watch(budgetYearProvider);

    return ConfigList<Budget>(
      async: ref.watch(budgetsProvider),
      onRefresh: ref.read(budgetsProvider.notifier).refresh,
      emptyIcon: Icons.savings_outlined,
      emptyTitle: 'No budgets for $year',
      emptyMessage: 'Set a spending cap per category to track actuals against '
          'it through the year.',
      errorMessage: 'Could not load the budgets.',
      itemBuilder: (context, budget) => _BudgetCard(
        budget: budget,
        busy: _busyId == budget.id,
        onEdit: widget.canManage
            ? () => showBudgetSheet(context, fiscalYear: year, existing: budget)
            : null,
        onDelete: widget.canManage ? () => _delete(budget) : null,
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.budget,
    required this.busy,
    this.onEdit,
    this.onDelete,
  });

  final Budget budget;
  final bool busy;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final barColor = budget.usedPercent > 100
        ? bos.danger
        : budget.usedPercent >= 80
            ? bos.warning
            : bos.success;

    final actions = <RowAction>[
      if (onEdit != null) RowAction(label: 'Edit', onSelected: onEdit!),
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
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              budget.category,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: bos.text,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (budget.overBudget) ...[
                            const SizedBox(width: 6),
                            StatusChip('CANCELLED',
                                label: 'Over budget', dense: true),
                          ],
                        ],
                      ),
                      if (budget.notes != null &&
                          budget.notes!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          budget.notes!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: bos.muted, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  Fmt.money(budget.amount),
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
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
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: budget.progress,
                minHeight: 6,
                backgroundColor: bos.borderLight,
                color: barColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${Fmt.money(budget.actualSpend)} spent · '
              '${Fmt.money(budget.remaining)} ${budget.remaining < 0 ? 'over' : 'left'} · '
              '${budget.usedPercent.toStringAsFixed(0)}%',
              style: TextStyle(
                color: budget.overBudget ? bos.danger : bos.muted,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Create / edit sheet ─────────────────────────────────────────

Future<void> showBudgetSheet(
  BuildContext context, {
  required int fiscalYear,
  Budget? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        _BudgetSheet(fiscalYear: fiscalYear, existing: existing),
  );
}

class _BudgetSheet extends ConsumerStatefulWidget {
  const _BudgetSheet({required this.fiscalYear, this.existing});

  final int fiscalYear;
  final Budget? existing;

  @override
  ConsumerState<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends ConsumerState<_BudgetSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _category =
      TextEditingController(text: widget.existing?.category ?? '');
  late final TextEditingController _fiscalYear = TextEditingController(
    text: '${widget.existing?.fiscalYear ?? widget.fiscalYear}',
  );
  late final TextEditingController _amount = TextEditingController(
    text: widget.existing == null ? '' : '${widget.existing!.amount}',
  );
  late final TextEditingController _notes =
      TextEditingController(text: widget.existing?.notes ?? '');

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _category.dispose();
    _fiscalYear.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(budgetRepositoryProvider);
    final request = BudgetRequest(
      category: _category.text,
      fiscalYear: int.parse(_fiscalYear.text.trim()),
      amount: double.parse(_amount.text.trim()),
      notes: _notes.text,
    );

    try {
      if (_isEdit) {
        final updated = await repo.update(widget.existing!.id, request);
        ref.read(budgetsProvider.notifier).apply(updated);
      } else {
        await repo.create(request);
        await ref.read(budgetsProvider.notifier).refresh();
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text(_isEdit ? 'Budget updated.' : 'Budget added.')),
      );
    } on ApiException catch (e) {
      // "A budget for this category and fiscal year already exists" is worth
      // reading as written.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save that budget.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories =
        ref.watch(budgetCategoriesProvider).value ?? const <String>[];

    return FormSheetFrame(
      title: _isEdit ? 'Edit budget' : 'New budget',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: _isEdit ? 'Save changes' : 'Create budget',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        Autocomplete<String>(
          initialValue: TextEditingValue(text: _category.text),
          optionsBuilder: (value) {
            if (value.text.isEmpty) return categories;
            return categories.where(
              (c) => c.toLowerCase().contains(value.text.toLowerCase()),
            );
          },
          onSelected: (value) => _category.text = value,
          fieldViewBuilder: (context, controller, focusNode, onSubmit) {
            // Keeps the real controller (used at submit time) and the
            // Autocomplete's own internal one in sync either way.
            controller.text = _category.text;
            controller.addListener(() => _category.text = controller.text);
            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              autofocus: !_isEdit,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Category',
                helperText: 'e.g. Marketing, Rent, Software',
                prefixIcon: Icon(Icons.sell_outlined),
              ),
              validator: (value) {
                final trimmed = value?.trim() ?? '';
                if (trimmed.isEmpty) return 'A category is required.';
                return trimmed.length > 100 ? '100 characters at most.' : null;
              },
            );
          },
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _fiscalYear,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Fiscal year'),
                validator: (value) {
                  final parsed = int.tryParse(value?.trim() ?? '');
                  if (parsed == null) return 'Required.';
                  return (parsed < 2000 || parsed > 2100) ? '2000–2100.' : null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount'),
                validator: (value) {
                  final parsed = double.tryParse(value?.trim() ?? '');
                  if (parsed == null) return 'Required.';
                  // @DecimalMin("0.01").
                  return parsed <= 0 ? 'More than zero.' : null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _notes,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            alignLabelWithHint: true,
          ),
          validator: (value) {
            final trimmed = value?.trim() ?? '';
            return trimmed.length > 500 ? '500 characters at most.' : null;
          },
        ),
      ],
    );
  }
}
