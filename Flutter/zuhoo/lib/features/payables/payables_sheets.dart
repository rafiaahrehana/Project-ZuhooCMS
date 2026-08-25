import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/date_field.dart';
import '../../shared/widgets/form_sheet.dart';
import '../../shared/widgets/primitives.dart';
import '../accounting/accounting_models.dart' show Account;
import '../accounting/accounting_repository.dart' show postableAccountsProvider;
import 'payables_models.dart';
import 'payables_repository.dart';

// ── Vendors ───────────────────────────────────────────────────

Future<void> showVendorSheet(BuildContext context, {Vendor? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _VendorSheet(existing: existing),
  );
}

class _VendorSheet extends ConsumerStatefulWidget {
  const _VendorSheet({this.existing});

  final Vendor? existing;

  @override
  ConsumerState<_VendorSheet> createState() => _VendorSheetState();
}

class _VendorSheetState extends ConsumerState<_VendorSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _contact =
      TextEditingController(text: widget.existing?.contactPerson ?? '');
  late final TextEditingController _email =
      TextEditingController(text: widget.existing?.email ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.existing?.phone ?? '');
  late final TextEditingController _taxId =
      TextEditingController(text: widget.existing?.taxId ?? '');
  late final TextEditingController _address =
      TextEditingController(text: widget.existing?.address ?? '');
  late final TextEditingController _terms =
      TextEditingController(text: widget.existing?.paymentTerms ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.existing?.notes ?? '');

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    for (final c in [
      _name,
      _contact,
      _email,
      _phone,
      _taxId,
      _address,
      _terms,
      _notes,
    ]) {
      c.dispose();
    }
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
    final repo = ref.read(payablesRepositoryProvider);
    final request = VendorRequest(
      name: _name.text,
      contactPerson: _contact.text,
      email: _email.text,
      phone: _phone.text,
      taxId: _taxId.text,
      address: _address.text,
      paymentTerms: _terms.text,
      notes: _notes.text,
    );

    try {
      if (_isEdit) {
        final updated = await repo.updateVendor(widget.existing!.id, request);
        ref.read(vendorsProvider.notifier).apply(updated);
      } else {
        await repo.createVendor(request);
        await ref.read(vendorsProvider.notifier).refresh();
      }
      ref.invalidate(activeVendorsProvider);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text(_isEdit ? 'Vendor updated.' : 'Vendor added.')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save that vendor.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// The backend caps several of these; enforcing it here beats a 400.
  String? Function(String?) _max(int limit) => (value) {
        final trimmed = value?.trim() ?? '';
        return trimmed.length > limit ? '$limit characters at most.' : null;
      };

  @override
  Widget build(BuildContext context) {
    return FormSheetFrame(
      title: _isEdit ? 'Edit vendor' : 'New vendor',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: _isEdit ? 'Save changes' : 'Add vendor',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        TextFormField(
          controller: _name,
          autofocus: !_isEdit,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            prefixIcon: Icon(Icons.storefront_outlined),
          ),
          validator: (value) =>
              (value?.trim().isEmpty ?? true) ? 'A name is required.' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _contact,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Contact person (optional)',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
          validator: _max(150),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email (optional)',
            prefixIcon: Icon(Icons.alternate_email_rounded),
          ),
          validator: _max(150),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone'),
                validator: _max(50),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _taxId,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Tax ID'),
                validator: _max(100),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _terms,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Payment terms (optional)',
            helperText: 'How long they give you — "Net 30", "On delivery"',
            prefixIcon: Icon(Icons.schedule_rounded),
          ),
          validator: _max(100),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _address,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Address (optional)',
            alignLabelWithHint: true,
          ),
          validator: _max(500),
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
        ),
      ],
    );
  }
}

// ── Bills ─────────────────────────────────────────────────────

Future<void> showBillSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _BillSheet(),
  );
}

class _BillSheet extends ConsumerStatefulWidget {
  const _BillSheet();

  @override
  ConsumerState<_BillSheet> createState() => _BillSheetState();
}

class _BillSheetState extends ConsumerState<_BillSheet> {
  final _formKey = GlobalKey<FormState>();
  final _subtotal = TextEditingController();
  final _tax = TextEditingController();
  final _reference = TextEditingController();
  final _description = TextEditingController();

  int? _vendorId;
  int? _expenseAccountId;
  DateTime? _billDate = DateTime.now();
  DateTime? _dueDate = DateTime.now().add(const Duration(days: 30));

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _subtotal.dispose();
    _tax.dispose();
    _reference.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final vendorId = _vendorId;
    final billDate = _billDate;
    final dueDate = _dueDate;
    if (vendorId == null) {
      setState(() => _error = 'Pick who the bill is from.');
      return;
    }
    if (billDate == null || dueDate == null) {
      setState(() => _error = 'Both dates are needed.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(payablesRepositoryProvider).createBill(
            VendorBillRequest(
              vendorId: vendorId,
              billDate: Fmt.isoDate(billDate),
              dueDate: Fmt.isoDate(dueDate),
              subtotal: double.parse(_subtotal.text.trim()),
              taxAmount: double.tryParse(_tax.text.trim()) ?? 0,
              vendorReference: _reference.text,
              description: _description.text,
              expenseAccountId: _expenseAccountId,
            ),
          );
      await ref.read(billsProvider.notifier).refresh();
      ref.invalidate(apAgeingProvider);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Bill entered. Somebody else has to approve it.'),
        ),
      );
    } on ApiException catch (e) {
      // A non-expense account comes back named, with its type.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not enter that bill.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final vendors = ref.watch(activeVendorsProvider).value ?? const <Vendor>[];
    // Only expense accounts may back a bill — the service refuses anything
    // else, so only those are offered.
    final accounts = [
      for (final account
          in ref.watch(postableAccountsProvider).value ?? const <Account>[])
        if (account.type == 'EXPENSE') account,
    ];

    final subtotal = double.tryParse(_subtotal.text.trim()) ?? 0;
    final tax = double.tryParse(_tax.text.trim()) ?? 0;

    return FormSheetFrame(
      title: 'New bill',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'Enter it',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        if (vendors.isEmpty)
          MessageBanner.warning(
            'There are no active vendors yet. Add one before entering a bill.',
          )
        else
          DropdownButtonFormField<int>(
            initialValue: _vendorId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'From',
              prefixIcon: Icon(Icons.storefront_outlined),
            ),
            items: [
              for (final vendor in vendors)
                DropdownMenuItem(
                  value: vendor.id,
                  child: Text(
                    vendor.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => setState(() {
              _vendorId = value;
              _error = null;
            }),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: DateField(
                label: 'Bill date',
                value: _billDate,
                clearable: false,
                onChanged: (value) => setState(() => _billDate = value),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DateField(
                label: 'Due',
                value: _dueDate,
                clearable: false,
                onChanged: (value) => setState(() => _dueDate = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _subtotal,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount'),
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  final parsed = double.tryParse(value?.trim() ?? '');
                  if (parsed == null) return 'An amount is required.';
                  // @DecimalMin("0.01").
                  return parsed <= 0 ? 'More than zero.' : null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _tax,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Tax'),
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) return null;
                  final parsed = double.tryParse(trimmed);
                  if (parsed == null) return 'A number.';
                  return parsed < 0 ? 'Zero or more.' : null;
                },
              ),
            ),
          ],
        ),
        if (subtotal > 0) ...[
          const SizedBox(height: 8),
          Text(
            'Total ${Fmt.money(subtotal + tax)}.',
            style: TextStyle(
              color: bos.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (accounts.isNotEmpty)
          DropdownButtonFormField<int>(
            initialValue: _expenseAccountId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Post against (optional)',
              helperText: 'An expense account. Anything else is refused.',
              prefixIcon: Icon(Icons.account_tree_outlined),
            ),
            items: [
              for (final account in accounts)
                DropdownMenuItem(
                  value: account.id,
                  child: Text(
                    '${account.accountCode}  ${account.accountName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => setState(() => _expenseAccountId = value),
          ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _reference,
          decoration: const InputDecoration(
            labelText: 'Their reference (optional)',
            helperText: 'The number on their invoice',
            prefixIcon: Icon(Icons.tag_rounded),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _description,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'What it is for (optional)',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        MessageBanner.info(
          'A bill cannot be edited once entered. A wrong one is cancelled and '
          'entered again.',
        ),
      ],
    );
  }
}

/// Records a payment against a bill.
///
/// Defaults to the whole outstanding balance, because that is what usually
/// happens, and refuses more than it — the backend does too, naming the
/// balance.
Future<double?> askForPayment(
  BuildContext context, {
  required VendorBill bill,
}) async {
  final controller = TextEditingController(
    text: bill.balanceAmount == bill.balanceAmount.roundToDouble()
        ? '${bill.balanceAmount.round()}'
        : '${bill.balanceAmount}',
  );

  final result = await showDialog<double>(
    context: context,
    builder: (dialogContext) {
      final bos = Theme.of(dialogContext).bos;
      return StatefulBuilder(
        builder: (context, setState) {
          final amount = double.tryParse(controller.text.trim());
          final valid = amount != null &&
              amount > 0 &&
              amount <= bill.balanceAmount + 0.005;
          return AlertDialog(
            title: Text('Pay ${bill.billNumber}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${Fmt.money(bill.balanceAmount)} outstanding to '
                  '${bill.vendorName ?? 'this vendor'}.',
                  style: TextStyle(color: bos.muted, fontSize: 13, height: 1.45),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount'),
                  onChanged: (_) => setState(() {}),
                ),
                if (amount != null && amount > bill.balanceAmount + 0.005) ...[
                  const SizedBox(height: 8),
                  Text(
                    'More than is outstanding.',
                    style: TextStyle(color: bos.danger, fontSize: 12),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Never mind'),
              ),
              TextButton(
                onPressed:
                    valid ? () => Navigator.pop(dialogContext, amount) : null,
                child: const Text('Record it'),
              ),
            ],
          );
        },
      );
    },
  );

  controller.dispose();
  return result;
}
