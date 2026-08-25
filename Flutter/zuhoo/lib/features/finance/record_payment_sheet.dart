import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/date_field.dart';
import '../../shared/widgets/primitives.dart';
import '../crm/crm_controllers.dart';
import '../portal/portal_models.dart' show Invoice;
import 'finance_models.dart';
import 'finance_repository.dart';

/// Records money received.
///
/// Opened either from an invoice — where the client and the amount owed are
/// already known — or from the invoice list, where neither is.
Future<void> showRecordPaymentSheet(
  BuildContext context, {
  Invoice? against,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _RecordPaymentSheet(against: against),
  );
}

class _RecordPaymentSheet extends ConsumerStatefulWidget {
  const _RecordPaymentSheet({this.against});

  final Invoice? against;

  @override
  ConsumerState<_RecordPaymentSheet> createState() =>
      _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends ConsumerState<_RecordPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount = TextEditingController(
    // Defaults to what is still owed — the common case is somebody paying a
    // bill off, not a part payment.
    text: widget.against == null ? '' : '${widget.against!.balanceAmount}',
  );
  final _reference = TextEditingController();
  final _notes = TextEditingController();

  late int? _clientId = widget.against?.clientId;
  late DateTime _paymentDate = DateTime.now();
  String _method = paymentMethods.first;

  bool _submitting = false;
  String? _error;

  bool get _againstInvoice => widget.against != null;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_clientId == null) {
      setState(() => _error = 'Choose who paid.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(financeRepositoryProvider).createReceipt(
            CreatePaymentReceiptRequest(
              clientId: _clientId!,
              amount: double.parse(_amount.text.trim()),
              paymentDate: Fmt.isoDate(_paymentDate),
              paymentMethod: _method,
              invoiceId: widget.against?.id,
              transactionReference: _reference.text,
              notes: _notes.text,
            ),
          );
      // The balance on the invoice list has moved.
      ref.invalidate(invoicesProvider);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text('${Fmt.money(double.tryParse(_amount.text.trim()))} '
              'recorded.'),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not record that payment.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final now = DateTime.now();
    final clients = ref.watch(clientsProvider);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Record a payment',
                style: TextStyle(
                  color: bos.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (_againstInvoice) ...[
                const SizedBox(height: 4),
                Text(
                  'Against ${widget.against!.invoiceNumber} · '
                  '${Fmt.money(widget.against!.balanceAmount)} outstanding',
                  style: TextStyle(color: bos.muted, fontSize: 13),
                ),
              ],
              const SizedBox(height: 18),
              if (_error != null) ...[
                MessageBanner.error(
                  _error!,
                  onDismiss: () => setState(() => _error = null),
                ),
                const SizedBox(height: 14),
              ],
              if (_againstInvoice)
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Client',
                    prefixIcon: Icon(Icons.business_outlined),
                  ),
                  child: Text(
                    widget.against!.clientName ?? 'From the invoice',
                    style: TextStyle(color: bos.text, fontSize: 15),
                  ),
                )
              else
                clients.when(
                  loading: () => const Loader(padding: 12),
                  error: (_, _) => const MessageBanner.error(
                    'Could not load your clients.',
                  ),
                  data: (state) => DropdownButtonFormField<int>(
                    initialValue: _clientId,
                    decoration: const InputDecoration(
                      labelText: 'Client',
                      prefixIcon: Icon(Icons.business_outlined),
                    ),
                    items: [
                      for (final client in state.items)
                        DropdownMenuItem(
                          value: client.id,
                          child: Text(
                            client.headline,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _submitting
                        ? null
                        : (value) => setState(() => _clientId = value),
                  ),
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: (value) {
                  final parsed = double.tryParse(value?.trim() ?? '');
                  if (parsed == null) return 'How much was paid?';
                  return parsed <= 0 ? 'More than nothing.' : null;
                },
              ),
              const SizedBox(height: 16),
              DateField(
                label: 'Paid on',
                value: _paymentDate,
                enabled: !_submitting,
                clearable: false,
                // Money arrives in the past; a payment dated tomorrow has not
                // happened yet.
                firstDate: DateTime(now.year - 2),
                lastDate: now,
                onChanged: (date) {
                  if (date != null) setState(() => _paymentDate = date);
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _method,
                decoration: const InputDecoration(
                  labelText: 'Method',
                  prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                ),
                items: [
                  for (final method in paymentMethods)
                    DropdownMenuItem(
                      value: method,
                      child: Text(Fmt.label(method)),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _method = value ?? _method),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _reference,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Reference (optional)',
                  hintText: 'Transaction or cheque number',
                  prefixIcon: Icon(Icons.tag_rounded),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notes,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              const _Note(
                'Recording a receipt does not confirm it. Confirming and '
                'depositing are separate steps on the web.',
              ),
              const SizedBox(height: 18),
              LoadingButton(
                label: 'Record payment',
                loading: _submitting,
                icon: Icons.check_rounded,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 15, color: bos.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: bos.muted, fontSize: 12.5, height: 1.4),
          ),
        ),
      ],
    );
  }
}
