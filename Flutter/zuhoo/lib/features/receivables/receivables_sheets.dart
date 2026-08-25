import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/form_sheet.dart';
import '../../shared/widgets/primitives.dart';
import '../finance/finance_repository.dart' show invoicesProvider;
import '../portal/portal_models.dart' show Invoice;
import 'receivables_models.dart';
import 'receivables_repository.dart';

/// Issues a credit note against an invoice.
///
/// A credit note reduces what an invoice is owed without any money moving —
/// a discount agreed after the fact, or a billing error. There is no editing
/// one afterwards: correcting a credit note means issuing another.
Future<void> showCreditNoteSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _CreditNoteSheet(),
  );
}

class _CreditNoteSheet extends ConsumerStatefulWidget {
  const _CreditNoteSheet();

  @override
  ConsumerState<_CreditNoteSheet> createState() => _CreditNoteSheetState();
}

class _CreditNoteSheetState extends ConsumerState<_CreditNoteSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reason = TextEditingController();

  int? _invoiceId;

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final invoiceId = _invoiceId;
    if (invoiceId == null) {
      setState(() => _error = 'Pick which invoice it is against.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(receivablesRepositoryProvider).issueCreditNote(
            CreditNoteRequest(
              clientInvoiceId: invoiceId,
              amount: double.parse(_amount.text.trim()),
              reason: _reason.text,
            ),
          );
      await ref.read(creditNotesProvider.notifier).refresh();
      // What the invoice is owed has changed.
      await ref.read(invoicesProvider.notifier).refresh();
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Credit note issued.')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not issue that credit note.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final invoices =
        ref.watch(invoicesProvider).value?.items ?? const <Invoice>[];

    // Only an invoice with something still owed can be credited; crediting a
    // settled one would take it negative.
    final options = [
      for (final invoice in invoices)
        if (invoice.balanceAmount > 0) invoice,
    ];

    final chosen = options.where((i) => i.id == _invoiceId);
    final balance = chosen.isEmpty ? null : chosen.first.balanceAmount;
    final amount = double.tryParse(_amount.text.trim());

    return FormSheetFrame(
      title: 'New credit note',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'Issue it',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        if (options.isEmpty)
          MessageBanner.info(
            'Nothing is currently owed on any invoice, so there is nothing to '
            'credit.',
          )
        else
          DropdownButtonFormField<int>(
            initialValue: _invoiceId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Against',
              prefixIcon: Icon(Icons.receipt_long_outlined),
            ),
            items: [
              for (final invoice in options)
                DropdownMenuItem(
                  value: invoice.id,
                  child: Text(
                    '${invoice.invoiceNumber} · '
                    '${Fmt.money(invoice.balanceAmount)} owed',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => setState(() {
              _invoiceId = value;
              _error = null;
            }),
          ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Amount',
            prefixIcon: Icon(Icons.payments_outlined),
          ),
          onChanged: (_) => setState(() {}),
          validator: (value) {
            final parsed = double.tryParse(value?.trim() ?? '');
            if (parsed == null) return 'An amount is required.';
            // @DecimalMin("0.01").
            return parsed <= 0 ? 'More than zero.' : null;
          },
        ),
        if (balance != null && amount != null && amount > balance) ...[
          const SizedBox(height: 8),
          // The backend does not check this, so it is a warning rather than a
          // refusal — but crediting more than is owed is almost always a slip.
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 15, color: bos.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'That is more than the ${Fmt.money(balance)} still owed.',
                  style: TextStyle(color: bos.warning, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        TextFormField(
          controller: _reason,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Why (optional)',
            helperText: 'Kept on the record and shown to the client',
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }
}
