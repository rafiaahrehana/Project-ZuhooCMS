import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/date_field.dart';
import '../../shared/widgets/form_sheet.dart';
import '../../shared/widgets/primitives.dart';
import '../finance/finance_models.dart' show paymentMethods;
import 'payroll_models.dart';
import 'payroll_repository.dart';

// ── Opening a run ─────────────────────────────────────────────

/// Opens the monthly run.
///
/// The month and year come from the screen rather than being pickable here:
/// there is exactly one run per period, and choosing a different one from
/// inside this sheet would leave the screen showing something else.
Future<void> showOpenRunSheet(
  BuildContext context, {
  required int month,
  required int year,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _OpenRunSheet(month: month, year: year),
  );
}

class _OpenRunSheet extends ConsumerStatefulWidget {
  const _OpenRunSheet({required this.month, required this.year});

  final int month;
  final int year;

  @override
  ConsumerState<_OpenRunSheet> createState() => _OpenRunSheetState();
}

class _OpenRunSheetState extends ConsumerState<_OpenRunSheet> {
  final _formKey = GlobalKey<FormState>();
  final _remarks = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(payrollRepositoryProvider)
          .createRun(widget.month, widget.year, _remarks.text);
      await ref.read(payrollRunsProvider.notifier).refresh();
      ref.invalidate(payrollDashboardProvider);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Run opened. Generate the lines next.')),
      );
    } on ApiException catch (e) {
      // A run for this period already existing is refused with a message
      // naming the run that does — worth showing as written.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open that run.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: 'Open ${Fmt.monthYear(widget.month, widget.year)}',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'Open the run',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        Text(
          'A run groups everybody’s payroll for the month into one batch that '
          'is approved and paid together. There can only be one per period.',
          style: TextStyle(color: bos.muted, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 18),
        TextFormField(
          controller: _remarks,
          autofocus: true,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Remarks (optional)',
            helperText: 'Anything the approver should know before signing off',
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }
}

// ── Paying a run ──────────────────────────────────────────────

/// Pays every unpaid line in the run.
///
/// The one irreversible step in the sequence, so it says what it is about to
/// do — how many people, how much — before it does it.
Future<void> showPayRunSheet(
  BuildContext context, {
  required PayrollRun run,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PayRunSheet(run: run),
  );
}

class _PayRunSheet extends ConsumerStatefulWidget {
  const _PayRunSheet({required this.run});

  final PayrollRun run;

  @override
  ConsumerState<_PayRunSheet> createState() => _PayRunSheetState();
}

class _PayRunSheetState extends ConsumerState<_PayRunSheet> {
  final _formKey = GlobalKey<FormState>();
  final _prefix = TextEditingController();

  String _method = 'BANK_TRANSFER';
  DateTime? _paymentDate = DateTime.now();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _prefix.dispose();
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
    try {
      final updated =
          await ref.read(payrollRepositoryProvider).pay(
                widget.run.id,
                paymentMethod: _method,
                referencePrefix: _prefix.text,
                paymentDate:
                    _paymentDate == null ? null : Fmt.isoDate(_paymentDate!),
              );
      ref.read(payrollRunsProvider.notifier).apply(updated);
      ref.invalidate(payrollDashboardProvider);
      ref.invalidate(payrollLinesProvider);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text('${widget.run.runNumber} paid.'),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not pay that run.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final run = widget.run;

    return FormSheetFrame(
      title: 'Pay ${run.runNumber}',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'Pay it',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        MessageBanner.info(
          run.totalEmployees == 1
              ? 'One employee, ${Fmt.money(run.totalNet)}. This cannot be '
                  'undone.'
              : '${run.totalEmployees} employees, ${Fmt.money(run.totalNet)}. '
                  'This cannot be undone.',
        ),
        const SizedBox(height: 18),
        DropdownButtonFormField<String>(
          initialValue: _method,
          decoration: const InputDecoration(
            labelText: 'Paid by',
            prefixIcon: Icon(Icons.account_balance_rounded),
          ),
          items: [
            for (final method in paymentMethods)
              DropdownMenuItem(value: method, child: Text(Fmt.label(method))),
          ],
          onChanged: (value) => setState(() => _method = value ?? _method),
        ),
        const SizedBox(height: 16),
        DateField(
          label: 'Payment date',
          value: _paymentDate,
          clearable: false,
          onChanged: (value) => setState(() => _paymentDate = value),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _prefix,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: 'Reference prefix (optional)',
            helperText: 'Each line gets this plus a sequence — '
                'without one the run number is used',
            prefixIcon: const Icon(Icons.tag_rounded),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Lines already paid or cancelled are skipped.',
          style: TextStyle(color: bos.muted, fontSize: 12, height: 1.45),
        ),
      ],
    );
  }
}

// ── Settings ──────────────────────────────────────────────────

/// How pay is worked out.
///
/// The one update in the codebase that is fully null-guarded server-side, so
/// nothing here can be cleared by accident — but the form still sends every
/// field, because it shows every field.
Future<void> showPayrollSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _SettingsSheet(),
  );
}

class _SettingsSheet extends ConsumerStatefulWidget {
  const _SettingsSheet();

  @override
  ConsumerState<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends ConsumerState<_SettingsSheet> {
  final _formKey = GlobalKey<FormState>();

  /// Seeded once, from the server's answer, then owned by the sheet.
  bool _seeded = false;

  final _multiplier = TextEditingController();
  final _hours = TextEditingController();
  final _houseRent = TextEditingController();
  final _medical = TextEditingController();
  final _transport = TextEditingController();
  final _food = TextEditingController();
  final _providentFund = TextEditingController();
  final _tax = TextEditingController();

  String _perDayBasis = perDayBases.first.value;
  String _absenceBase = 'GROSS';
  String _overtimeBase = 'BASIC';
  bool _overtimeEnabled = false;

  bool _submitting = false;
  String? _error;

  void _seed(PayrollSettings settings) {
    _seeded = true;
    _multiplier.text = _plain(settings.overtimeMultiplier);
    _hours.text = _plain(settings.standardHoursPerDay);
    _houseRent.text = _plain(settings.houseRentPercent);
    _medical.text = _plain(settings.medicalPercent);
    _transport.text = _plain(settings.transportPercent);
    _food.text = _plain(settings.foodPercent);
    _providentFund.text = _plain(settings.providentFundPercent);
    _tax.text = _plain(settings.taxPercent);
    _perDayBasis = settings.perDayBasis;
    _absenceBase = settings.absenceDeductionBase;
    _overtimeBase = settings.overtimeBase;
    _overtimeEnabled = settings.overtimeEnabled;
  }

  /// A plain number for a text field. `Fmt.money` and friends add symbols and
  /// suffixes that would not parse back.
  static String _plain(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : '$value';

  @override
  void dispose() {
    _multiplier.dispose();
    _hours.dispose();
    _houseRent.dispose();
    _medical.dispose();
    _transport.dispose();
    _food.dispose();
    _providentFund.dispose();
    _tax.dispose();
    super.dispose();
  }

  double _read(TextEditingController controller, double fallback) =>
      double.tryParse(controller.text.trim()) ?? fallback;

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(payrollRepositoryProvider).updateSettings(
            PayrollSettingsRequest(
              perDayBasis: _perDayBasis,
              absenceDeductionBase: _absenceBase,
              overtimeEnabled: _overtimeEnabled,
              overtimeMultiplier: _read(_multiplier, 2),
              overtimeBase: _overtimeBase,
              standardHoursPerDay: _read(_hours, 8),
              houseRentPercent: _read(_houseRent, 0),
              medicalPercent: _read(_medical, 0),
              transportPercent: _read(_transport, 0),
              foodPercent: _read(_food, 0),
              providentFundPercent: _read(_providentFund, 0),
              taxPercent: _read(_tax, 0),
            ),
          );
      ref.invalidate(payrollSettingsProvider);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Saved. It applies the next time payroll is worked out.'),
        ),
      );
    } on ApiException catch (e) {
      // Out-of-range values come back named — "Overtime multiplier must be
      // between 1 and 5" — so they are shown as written.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save those settings.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _percent(String? value) {
    final parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null) return 'A percentage.';
    return (parsed < 0 || parsed > 100) ? '0 to 100.' : null;
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final settings = ref.watch(payrollSettingsProvider);

    if (settings.hasError && !_seeded) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: ErrorState(
          message: settings.error is ApiException
              ? (settings.error! as ApiException).message
              : 'Could not load the payroll settings.',
          onRetry: () => ref.invalidate(payrollSettingsProvider),
        ),
      );
    }
    if (!settings.hasValue && !_seeded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Loader(),
      );
    }
    if (!_seeded) _seed(settings.value!);

    final allowances = _read(_houseRent, 0) +
        _read(_medical, 0) +
        _read(_transport, 0) +
        _read(_food, 0);

    return FormSheetFrame(
      title: 'How pay is worked out',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'Save',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        _Label('A day’s pay'),
        DropdownButtonFormField<String>(
          initialValue: perDayBases.any((b) => b.value == _perDayBasis)
              ? _perDayBasis
              : perDayBases.first.value,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Divide the month by'),
          items: [
            for (final basis in perDayBases)
              DropdownMenuItem(value: basis.value, child: Text(basis.label)),
          ],
          onChanged: (value) =>
              setState(() => _perDayBasis = value ?? _perDayBasis),
        ),
        const SizedBox(height: 6),
        Text(
          perDayBases
              .firstWhere(
                (b) => b.value == _perDayBasis,
                orElse: () => perDayBases.first,
              )
              .hint,
          style: TextStyle(color: bos.muted, fontSize: 12, height: 1.45),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _absenceBase,
          decoration: const InputDecoration(labelText: 'Deduct absence from'),
          items: [
            for (final base in salaryBases)
              DropdownMenuItem(value: base, child: Text(Fmt.label(base))),
          ],
          onChanged: (value) =>
              setState(() => _absenceBase = value ?? _absenceBase),
        ),
        const SizedBox(height: 20),
        _Label('Overtime'),
        SwitchListTile(
          value: _overtimeEnabled,
          onChanged: (value) => setState(() => _overtimeEnabled = value),
          title: Text(
            'Pay overtime',
            style: TextStyle(color: bos.text, fontSize: 14),
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        if (_overtimeEnabled) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _multiplier,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Multiplier'),
                  validator: (value) {
                    final parsed = double.tryParse(value?.trim() ?? '');
                    if (parsed == null) return 'A number.';
                    // Matches the backend's 1–5 range check.
                    return (parsed < 1 || parsed > 5) ? '1 to 5.' : null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _hours,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Hours a day'),
                  validator: (value) {
                    final parsed = double.tryParse(value?.trim() ?? '');
                    if (parsed == null) return 'A number.';
                    return (parsed < 1 || parsed > 24) ? '1 to 24.' : null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _overtimeBase,
            decoration: const InputDecoration(labelText: 'Rate based on'),
            items: [
              for (final base in salaryBases)
                DropdownMenuItem(value: base, child: Text(Fmt.label(base))),
            ],
            onChanged: (value) =>
                setState(() => _overtimeBase = value ?? _overtimeBase),
          ),
        ],
        const SizedBox(height: 20),
        _Label('Allowances, as a share of basic'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _houseRent,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'House rent %'),
                validator: _percent,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _medical,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Medical %'),
                validator: _percent,
                onChanged: (_) => setState(() {}),
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
                controller: _transport,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Transport %'),
                validator: _percent,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _food,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Food %'),
                validator: _percent,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        if (allowances > 100) ...[
          const SizedBox(height: 10),
          // The backend checks each percentage on its own but never the total,
          // so this is a warning rather than a validation failure.
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 15, color: bos.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'The allowances add up to ${Fmt.percent(allowances)} of '
                  'basic. That is allowed, but it is unusual.',
                  style: TextStyle(color: bos.warning, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        _Label('Deductions'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _providentFund,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: 'Provident fund %'),
                validator: _percent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _tax,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Tax %'),
                validator: _percent,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          color: bos.muted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
