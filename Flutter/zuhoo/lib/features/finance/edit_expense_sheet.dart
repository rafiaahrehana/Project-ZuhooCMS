import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/date_field.dart';
import '../../shared/widgets/form_sheet.dart';
import 'finance_models.dart';
import 'finance_repository.dart';

/// Changing a claim that has not been decided on yet.
///
/// Seeded from the whole expense rather than from the fields on screen. The
/// endpoint assigns most of what it is sent without a null check, so anything
/// this form does not show — the chart-of-accounts row it posts to, the
/// receipt, the currency — has to be carried across or it is cleared.
Future<void> showEditExpenseSheet(
  BuildContext context, {
  required Expense expense,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditExpenseSheet(expense: expense),
    );

class _EditExpenseSheet extends ConsumerStatefulWidget {
  const _EditExpenseSheet({required this.expense});

  final Expense expense;

  @override
  ConsumerState<_EditExpenseSheet> createState() => _EditExpenseSheetState();
}

class _EditExpenseSheetState extends ConsumerState<_EditExpenseSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title =
      TextEditingController(text: widget.expense.title ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.expense.description);
  late final TextEditingController _amount =
      TextEditingController(text: widget.expense.amount.toString());
  late final TextEditingController _vendor =
      TextEditingController(text: widget.expense.vendorName ?? '');
  late final TextEditingController _category =
      TextEditingController(text: widget.expense.category ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.expense.notes ?? '');
  late DateTime? _date = Fmt.parse(widget.expense.expenseDate);

  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _amount.dispose();
    _vendor.dispose();
    _category.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(expensesProvider.notifier).edit(
            widget.expense.id,
            UpdateExpenseRequest.from(widget.expense).copyWith(
              title: _title.text.trim(),
              description: _description.text.trim(),
              amount: double.parse(_amount.text.trim()),
              expenseDate: Fmt.isoDate(_date!),
              vendorName: _vendor.text.trim(),
              category: _category.text.trim(),
              notes: _notes.text.trim(),
            ),
          );
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      // "Can only update pending expenses" arrives here when somebody else
      // decided it while this sheet was open.
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not save that claim.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: 'Edit claim',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'Save',
      submitting: _busy,
      onSubmit: _submit,
      children: [
        TextFormField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _description,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'What it was for'),
          validator: (value) => (value?.trim().isEmpty ?? true)
              ? 'Say what it was for.'
              : null,
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  suffixText: widget.expense.currency,
                ),
                validator: (value) {
                  final amount = double.tryParse(value?.trim() ?? '');
                  if (amount == null) return 'A figure, please.';
                  if (amount <= 0) return 'More than nothing.';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DateField(
                label: 'Date',
                value: _date,
                lastDate: DateTime.now(),
                onChanged: (value) => setState(() => _date = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _vendor,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Who it was paid to'),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _category,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Category'),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _notes,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Notes'),
        ),
        if (widget.expense.expenseAccountName != null) ...[
          const SizedBox(height: 10),
          Text(
            'Posts to ${widget.expense.expenseAccountName}. That is set on the '
            'web and is kept as it is.',
            style: TextStyle(color: bos.muted, fontSize: 11.5, height: 1.5),
          ),
        ],
        if (widget.expense.receiptUrl != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'The receipt already attached stays attached.',
              style: TextStyle(color: bos.muted, fontSize: 11.5, height: 1.5),
            ),
          ),
      ],
    );
  }
}

/// Recording that an approved claim has been paid back.
///
/// Both details are optional, and both are query parameters rather than a
/// body. Neither can be corrected afterwards — there is no endpoint to unpay
/// an expense — so the sheet says so before it sends.
Future<void> showMarkPaidSheet(
  BuildContext context, {
  required Expense expense,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MarkPaidSheet(expense: expense),
    );

class _MarkPaidSheet extends ConsumerStatefulWidget {
  const _MarkPaidSheet({required this.expense});

  final Expense expense;

  @override
  ConsumerState<_MarkPaidSheet> createState() => _MarkPaidSheetState();
}

class _MarkPaidSheetState extends ConsumerState<_MarkPaidSheet> {
  final _formKey = GlobalKey<FormState>();
  final _reference = TextEditingController();
  String _method = _methods.first;

  String? _error;
  bool _busy = false;

  // Unlike payroll payout, the backend's `reimbursementMethod` is a plain
  // String with no enum/guard behind it — Angular's own form is free text.
  // This list is just a curated picker for UX, not a contract to keep in
  // sync with `payrollPaymentMethods`, but the mobile-money rails belong
  // here too: an employee can be reimbursed by bKash/Nagad/Rocket same as
  // any other claim payout.
  static const _methods = <String>[
    'BANK_TRANSFER',
    'BKASH',
    'NAGAD',
    'ROCKET',
    'CASH',
    'CHEQUE',
    'PAYROLL',
    'CARD',
  ];

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(expensesProvider.notifier).markPaid(
            widget.expense.id,
            method: _method,
            reference: _reference.text,
          );
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not record that.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: 'Reimbursed',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'Record it',
      submitting: _busy,
      onSubmit: _submit,
      children: [
        Text(
          '${Fmt.money(widget.expense.amount)} to '
          '${widget.expense.submittedByName ?? "whoever claimed it"}.',
          style: TextStyle(color: bos.text, fontSize: 14),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: _method,
          decoration: const InputDecoration(labelText: 'Paid by'),
          items: [
            for (final value in _methods)
              DropdownMenuItem(value: value, child: Text(Fmt.label(value))),
          ],
          onChanged: (value) => setState(() => _method = value ?? _method),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _reference,
          decoration: const InputDecoration(
            labelText: 'Reference',
            hintText: 'A transfer or cheque number, if there is one.',
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'There is no way to undo this. A claim recorded as reimbursed stays '
          'that way.',
          style: TextStyle(color: bos.muted, fontSize: 11.5, height: 1.5),
        ),
      ],
    );
  }
}
