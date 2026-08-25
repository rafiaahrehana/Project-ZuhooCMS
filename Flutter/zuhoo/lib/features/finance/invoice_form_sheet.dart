import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/date_field.dart';
import '../../shared/widgets/primitives.dart';
import '../crm/crm_controllers.dart';
import '../portal/portal_models.dart' show Invoice, InvoiceItem;
import 'finance_models.dart';
import 'finance_repository.dart';

/// Raises an invoice against a client.
Future<void> showNewInvoiceSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _InvoiceFormSheet(),
  );
}

/// Edits a draft invoice. Returns the server's version, or null if dismissed.
Future<Invoice?> showEditInvoiceSheet(BuildContext context, Invoice invoice) {
  return showModalBottomSheet<Invoice>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _InvoiceFormSheet(existing: invoice),
  );
}

/// One editable line. Held as controllers rather than values so the fields keep
/// their cursor position while the total above them recomputes on every keystroke.
class _LineControllers {
  _LineControllers({String description = '', String quantity = '1', String unitPrice = ''})
      : description = TextEditingController(text: description),
        quantity = TextEditingController(text: quantity),
        unitPrice = TextEditingController(text: unitPrice);

  final TextEditingController description;
  final TextEditingController quantity;
  final TextEditingController unitPrice;

  double get amount =>
      (double.tryParse(quantity.text.trim()) ?? 0) *
      (double.tryParse(unitPrice.text.trim()) ?? 0);

  bool get isBlank =>
      description.text.trim().isEmpty &&
      unitPrice.text.trim().isEmpty;

  InvoiceItem toItem() => InvoiceItem(
        description: description.text,
        quantity: double.tryParse(quantity.text.trim()) ?? 0,
        unitPrice: double.tryParse(unitPrice.text.trim()) ?? 0,
      );

  void dispose() {
    description.dispose();
    quantity.dispose();
    unitPrice.dispose();
  }
}

class _InvoiceFormSheet extends ConsumerStatefulWidget {
  const _InvoiceFormSheet({this.existing});

  final Invoice? existing;

  @override
  ConsumerState<_InvoiceFormSheet> createState() => _InvoiceFormSheetState();
}

class _InvoiceFormSheetState extends ConsumerState<_InvoiceFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _notes = TextEditingController();
  final _taxRate = TextEditingController();
  final _discount = TextEditingController();

  final List<_LineControllers> _lines = [];

  int? _clientId;
  late DateTime _invoiceDate;
  late DateTime _dueDate;
  String? _paymentTerms;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _clientId = existing?.clientId;
    _invoiceDate = Fmt.parse(existing?.invoiceDate) ?? DateTime.now();
    _dueDate = Fmt.parse(existing?.dueDate) ??
        DateTime.now().add(const Duration(days: 30));
    _paymentTerms = existing?.paymentTerms;
    _description.text = existing?.description ?? '';
    _notes.text = existing?.notes ?? '';
    _taxRate.text =
        existing?.taxRatePercent == null ? '' : '${existing!.taxRatePercent}';
    _discount.text =
        existing?.discountAmount == null ? '' : '${existing!.discountAmount}';

    if (existing != null && existing.items.isNotEmpty) {
      for (final item in existing.items) {
        _lines.add(_LineControllers(
          description: item.description,
          quantity: '${item.quantity}',
          unitPrice: '${item.unitPrice}',
        ));
      }
    } else {
      _lines.add(_LineControllers());
    }
  }

  @override
  void dispose() {
    _description.dispose();
    _notes.dispose();
    _taxRate.dispose();
    _discount.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  double get _subtotal =>
      _lines.fold(0, (total, line) => total + line.amount);

  double get _total {
    final rate = double.tryParse(_taxRate.text.trim()) ?? 0;
    final discount = double.tryParse(_discount.text.trim()) ?? 0;
    return _subtotal + (_subtotal * rate / 100) - discount;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_clientId == null) {
      setState(() => _error = 'Choose who the invoice is for.');
      return;
    }
    final items = _lines.where((line) => !line.isBlank).toList();
    if (items.isEmpty) {
      // @NotEmpty server-side, on create and on edit alike.
      setState(() => _error = 'An invoice needs at least one line.');
      return;
    }
    if (_dueDate.isBefore(_invoiceDate)) {
      setState(() => _error = 'The invoice falls due before it is raised.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final request = InvoiceRequest(
      clientId: _clientId!,
      invoiceDate: Fmt.isoDate(_invoiceDate),
      dueDate: Fmt.isoDate(_dueDate),
      items: [for (final line in items) line.toItem()],
      // Sent as the rate, not the amount: the backend recomputes tax from the
      // rate when one is present, and the two disagreeing is how an invoice
      // ends up totalling something nobody typed.
      taxRatePercent: double.tryParse(_taxRate.text.trim()),
      discountAmount: double.tryParse(_discount.text.trim()),
      paymentTerms: _paymentTerms,
      description: _description.text,
      notes: _notes.text,
    );

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final controller = ref.read(invoicesProvider.notifier);
    try {
      if (_isEdit) {
        final updated = await controller.update(widget.existing!.id, request);
        if (!mounted) return;
        navigator.pop(updated);
        messenger.showSnackBar(
          const SnackBar(content: Text('Invoice updated.')),
        );
      } else {
        await controller.create(request);
        if (!mounted) return;
        navigator.pop();
        messenger.showSnackBar(
          const SnackBar(content: Text('Invoice raised as a draft.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = _isEdit
            ? 'Could not update that invoice.'
            : 'Could not raise that invoice.');
      }
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
                _isEdit ? 'Edit invoice' : 'New invoice',
                style: TextStyle(
                  color: bos.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (_isEdit) ...[
                const SizedBox(height: 4),
                Text(
                  widget.existing!.invoiceNumber,
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

              // The client cannot move once the invoice exists: the endpoint
              // takes a clientId but reassigning a raised invoice is not a
              // thing this form should quietly allow.
              if (_isEdit)
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Client',
                    prefixIcon: Icon(Icons.business_outlined),
                  ),
                  child: Text(
                    widget.existing!.clientName ?? 'Unchanged',
                    style: TextStyle(color: bos.text, fontSize: 15),
                  ),
                )
              else
                clients.when(
                  loading: () => const Loader(padding: 12),
                  error: (_, _) => const MessageBanner.error(
                    'Could not load your clients.',
                  ),
                  data: (state) {
                    if (state.items.isEmpty) {
                      return const MessageBanner.info(
                        'No clients yet. An invoice needs one.',
                      );
                    }
                    return DropdownButtonFormField<int>(
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
                    );
                  },
                ),
              const SizedBox(height: 16),
              DateField(
                label: 'Invoice date',
                value: _invoiceDate,
                enabled: !_submitting,
                clearable: false,
                firstDate: DateTime(now.year - 2),
                lastDate: DateTime(now.year + 1),
                onChanged: (date) {
                  if (date != null) setState(() => _invoiceDate = date);
                },
              ),
              const SizedBox(height: 16),
              DateField(
                label: 'Due',
                icon: Icons.hourglass_bottom_rounded,
                value: _dueDate,
                enabled: !_submitting,
                clearable: false,
                firstDate: DateTime(now.year - 2),
                lastDate: DateTime(now.year + 3),
                onChanged: (date) {
                  if (date != null) setState(() => _dueDate = date);
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: paymentTermsOptions.contains(_paymentTerms)
                    ? _paymentTerms
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Payment terms (optional)',
                  prefixIcon: Icon(Icons.schedule_rounded),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Not set')),
                  for (final terms in paymentTermsOptions)
                    DropdownMenuItem(
                      value: terms,
                      child: Text(Fmt.label(terms)),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _paymentTerms = value),
              ),
              const SizedBox(height: 22),
              SectionHeader(
                'Lines',
                icon: Icons.list_alt_rounded,
                trailing: TextButton.icon(
                  onPressed: _submitting
                      ? null
                      : () => setState(() => _lines.add(_LineControllers())),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add'),
                ),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _lines.length; i++)
                _LineRow(
                  key: ObjectKey(_lines[i]),
                  line: _lines[i],
                  enabled: !_submitting,
                  onChanged: () => setState(() {}),
                  onRemove: _lines.length == 1
                      ? null
                      : () => setState(() => _lines.removeAt(i).dispose()),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _taxRate,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Tax %'),
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        final trimmed = value?.trim() ?? '';
                        if (trimmed.isEmpty) return null;
                        final parsed = double.tryParse(trimmed);
                        if (parsed == null) return 'Enter a number.';
                        return parsed < 0 || parsed > 100
                            ? 'Between 0 and 100.'
                            : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _discount,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Discount'),
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        final trimmed = value?.trim() ?? '';
                        if (trimmed.isEmpty) return null;
                        final parsed = double.tryParse(trimmed);
                        if (parsed == null) return 'Enter a number.';
                        return parsed < 0 ? 'Cannot be negative.' : null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AppCard(
                child: Column(
                  children: [
                    _TotalRow(label: 'Subtotal', amount: _subtotal),
                    const SizedBox(height: 6),
                    _TotalRow(label: 'Total', amount: _total, emphasised: true),
                    const SizedBox(height: 6),
                    Text(
                      'The backend works the real totals out; this is a preview.',
                      style: TextStyle(color: bos.muted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _description,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  alignLabelWithHint: true,
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
              const SizedBox(height: 18),
              LoadingButton(
                label: _isEdit ? 'Save invoice' : 'Raise invoice',
                loading: _submitting,
                icon: _isEdit ? Icons.check_rounded : Icons.receipt_long_rounded,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    super.key,
    required this.line,
    required this.enabled,
    required this.onChanged,
    required this.onRemove,
  });

  final _LineControllers line;
  final bool enabled;
  final VoidCallback onChanged;

  /// Null on the last remaining line: an invoice cannot have none.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: line.description,
                  enabled: enabled,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Description'),
                  onChanged: (_) => onChanged(),
                ),
              ),
              if (onRemove != null)
                IconButton(
                  icon: Icon(Icons.close_rounded, size: 18, color: bos.muted),
                  tooltip: 'Remove line',
                  onPressed: enabled ? onRemove : null,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: line.quantity,
                  enabled: enabled,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Qty'),
                  onChanged: (_) => onChanged(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: line.unitPrice,
                  enabled: enabled,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Unit price'),
                  onChanged: (_) => onChanged(),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 84,
                child: Text(
                  Fmt.money(line.amount),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
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

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.amount,
    this.emphasised = false,
  });

  final String label;
  final double amount;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: emphasised ? bos.text : bos.muted,
            fontSize: emphasised ? 14.5 : 13,
            fontWeight: emphasised ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        Text(
          Fmt.money(amount),
          style: TextStyle(
            color: bos.text,
            fontSize: emphasised ? 15.5 : 13.5,
            fontWeight: emphasised ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
