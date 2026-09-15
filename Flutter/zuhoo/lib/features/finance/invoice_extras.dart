import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/form_sheet.dart';
import '../../shared/widgets/primitives.dart';
import '../portal/portal_models.dart' show Invoice;
import 'finance_repository.dart';

/// A drafted note about an invoice.
///
/// Nothing is saved. The backend's own summary says "not persisted" — what
/// comes back is text to paste into an email or a comment if it is any good.
Future<void> showInvoiceSummarySheet(
  BuildContext context, {
  required Invoice invoice,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SummarySheet(invoice: invoice),
    );

class _SummarySheet extends ConsumerStatefulWidget {
  const _SummarySheet({required this.invoice});

  final Invoice invoice;

  @override
  ConsumerState<_SummarySheet> createState() => _SummarySheetState();
}

class _SummarySheetState extends ConsumerState<_SummarySheet> {
  late final Future<String> _summary =
      ref.read(financeRepositoryProvider).invoiceSummary(widget.invoice.id);

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
            widget.invoice.invoiceNumber,
            style: TextStyle(
              color: bos.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          FutureBuilder<String>(
            future: _summary,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Loader(padding: 20, message: 'Writing it');
              }
              if (snapshot.hasError) {
                final error = snapshot.error;
                return MessageBanner.error(
                  error is ApiException
                      ? error.message
                      : 'Could not draft a summary.',
                );
              }

              final summary = snapshot.data ?? '';
              if (summary.trim().isEmpty) {
                return Text(
                  'Nothing came back. The assistant may not be configured.',
                  style: TextStyle(color: bos.muted, fontSize: 13),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SelectableText(
                    summary,
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 13.5,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: summary));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied.')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 17),
                    label: const Text('Copy'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Not saved anywhere. Closing this loses it.',
                    style: TextStyle(color: bos.muted, fontSize: 11.5),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Moves what an invoice records as paid, without raising a receipt.
///
/// Deliberately not the same thing as "Record payment", which creates a
/// payment receipt against the client and is what real money should go
/// through. This endpoint only shifts the figure, and leaves no document
/// behind — it is for correcting a balance, not for taking money.
Future<void> showAdjustPaidSheet(
  BuildContext context, {
  required Invoice invoice,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AdjustPaidSheet(invoice: invoice),
    );

class _AdjustPaidSheet extends ConsumerStatefulWidget {
  const _AdjustPaidSheet({required this.invoice});

  final Invoice invoice;

  @override
  ConsumerState<_AdjustPaidSheet> createState() => _AdjustPaidSheetState();
}

class _AdjustPaidSheetState extends ConsumerState<_AdjustPaidSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();

  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(financeRepositoryProvider).recordInvoicePayment(
            widget.invoice.id,
            double.parse(_amount.text.trim()),
          );
      // Empty response, so the list is reloaded rather than patched.
      await ref.read(invoicesProvider.notifier).refresh();
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
    final outstanding = widget.invoice.balanceAmount;

    return FormSheetFrame(
      title: 'Adjust what is paid',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'Record it',
      submitting: _busy,
      onSubmit: _submit,
      children: [
        Text(
          '${Fmt.money(outstanding)} still owed on '
          '${widget.invoice.invoiceNumber}.',
          style: TextStyle(color: bos.text, fontSize: 14),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount received'),
          validator: (value) {
            final amount = double.tryParse(value?.trim() ?? '');
            if (amount == null) return 'A figure, please.';
            if (amount <= 0) return 'More than nothing.';
            if (amount > outstanding) {
              return 'That is more than is owed.';
            }
            return null;
          },
        ),
        const SizedBox(height: 10),
        MessageBanner.warning(
          'This only moves the invoice figure. No receipt is raised and there '
          'is nothing to show the client. For money actually received, use '
          'Record payment instead.',
        ),
      ],
    );
  }
}
