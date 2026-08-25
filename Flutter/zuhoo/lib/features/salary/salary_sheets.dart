import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/date_field.dart';
import '../../shared/widgets/employee_picker.dart';
import '../../shared/widgets/form_sheet.dart';
import '../../shared/widgets/primitives.dart';
import 'salary_models.dart';
import 'salary_repository.dart';

// ── Salary structures ─────────────────────────────────────────

/// Sets or changes what somebody is paid.
///
/// Three ways in. With [existing] it edits that structure — only allowed on
/// the current one. With [employeeId] it creates one for that person, which
/// supersedes whatever they had. With neither it asks who first.
Future<void> showStructureSheet(
  BuildContext context, {
  SalaryStructure? existing,
  int? employeeId,
  String? employeeName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _StructureSheet(
      existing: existing,
      employeeId: employeeId,
      employeeName: employeeName,
    ),
  );
}

class _StructureSheet extends ConsumerStatefulWidget {
  const _StructureSheet({this.existing, this.employeeId, this.employeeName});

  final SalaryStructure? existing;
  final int? employeeId;
  final String? employeeName;

  @override
  ConsumerState<_StructureSheet> createState() => _StructureSheetState();
}

class _StructureSheetState extends ConsumerState<_StructureSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _gross = _money(widget.existing?.grossSalary);
  late final TextEditingController _basic = _money(widget.existing?.basicSalary);
  late final TextEditingController _houseRent = _money(widget.existing?.houseRent);
  late final TextEditingController _medical =
      _money(widget.existing?.medicalAllowance);
  late final TextEditingController _transport =
      _money(widget.existing?.transportAllowance);
  late final TextEditingController _food =
      _money(widget.existing?.foodAllowance);
  late final TextEditingController _special =
      _money(widget.existing?.specialAllowance);
  late final TextEditingController _providentFund =
      _money(widget.existing?.providentFund);
  late final TextEditingController _tax = _money(widget.existing?.taxDeduction);
  late final TextEditingController _notes =
      TextEditingController(text: widget.existing?.notes ?? '');

  late DateTime? _effectiveFrom =
      Fmt.parse(widget.existing?.effectiveFrom) ?? DateTime.now();

  late int? _employeeId = widget.existing?.employeeId ?? widget.employeeId;
  late String? _employeeName =
      widget.existing?.employeeName ?? widget.employeeName;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  /// A plain number, never formatted — `Fmt.money` adds a currency symbol that
  /// would not parse back out of the field.
  static TextEditingController _money(double? value) => TextEditingController(
        text: value == null || value == 0
            ? ''
            : (value == value.roundToDouble()
                ? '${value.round()}'
                : '$value'),
      );

  @override
  void dispose() {
    for (final controller in [
      _gross,
      _basic,
      _houseRent,
      _medical,
      _transport,
      _food,
      _special,
      _providentFund,
      _tax,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  double _read(TextEditingController controller) =>
      double.tryParse(controller.text.trim()) ?? 0;

  Future<void> _pickEmployee() async {
    final person = await EmployeePicker.show(context, title: 'Whose pay?');
    if (person == null || !mounted) return;
    setState(() {
      _employeeId = person.id;
      _employeeName = person.fullName;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final employeeId = _employeeId;
    if (employeeId == null) {
      setState(() => _error = 'Pick whose pay this is.');
      return;
    }
    final effectiveFrom = _effectiveFrom;
    if (effectiveFrom == null) {
      setState(() => _error = 'Pick the date it takes effect.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(salaryRepositoryProvider);
    final request = SalaryStructureRequest(
      employeeId: employeeId,
      effectiveFrom: Fmt.isoDate(effectiveFrom),
      grossSalary: _read(_gross),
      basicSalary: _read(_basic),
      houseRent: _read(_houseRent),
      medicalAllowance: _read(_medical),
      transportAllowance: _read(_transport),
      foodAllowance: _read(_food),
      specialAllowance: _read(_special),
      providentFund: _read(_providentFund),
      taxDeduction: _read(_tax),
      notes: _notes.text,
    );

    try {
      if (_isEdit) {
        final updated =
            await repo.updateStructure(widget.existing!.id, request);
        ref.read(salaryStructuresProvider.notifier).apply(updated);
      } else {
        await repo.createStructure(request);
        // A create supersedes the previous structure, so the row before it
        // changes too — reload rather than insert.
        await ref.read(salaryStructuresProvider.notifier).refresh();
      }
      ref.invalidate(structureHistoryProvider(employeeId));
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _isEdit
                ? 'Pay updated.'
                : 'Pay set. It supersedes anything that came before.',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save that pay.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _required(String? value) {
    final parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null) return 'An amount is required.';
    // Matches @DecimalMin("0.01") — a structure with no pay in it is refused.
    return parsed <= 0 ? 'More than zero.' : null;
  }

  String? _optional(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final parsed = double.tryParse(trimmed);
    if (parsed == null) return 'A number.';
    return parsed < 0 ? 'Zero or more.' : null;
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    final gross = _read(_gross);
    final allocated = _read(_basic) +
        _read(_houseRent) +
        _read(_medical) +
        _read(_transport) +
        _read(_food) +
        _read(_special);
    final difference = gross - allocated;

    return FormSheetFrame(
      title: _isEdit ? 'Edit pay' : 'Set pay',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: _isEdit ? 'Save changes' : 'Set it',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        if (_isEdit)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              _employeeName ?? 'This employee',
              style: TextStyle(
                color: bos.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else ...[
          // Whose pay this is cannot change on an edit — the structure belongs
          // to one person for good.
          InkWell(
            onTap: _pickEmployee,
            borderRadius: BorderRadius.circular(10),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Employee',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              child: Text(
                _employeeName ?? 'Tap to choose',
                style: TextStyle(
                  color: _employeeName == null ? bos.muted : bos.text,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        DateField(
          label: 'Takes effect',
          value: _effectiveFrom,
          clearable: false,
          onChanged: (value) => setState(() => _effectiveFrom = value),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _gross,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Gross'),
                validator: _required,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _basic,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Basic'),
                validator: _required,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _Label('Allowances'),
        _MoneyPair(
          left: _houseRent,
          leftLabel: 'House rent',
          right: _medical,
          rightLabel: 'Medical',
          validator: _optional,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 16),
        _MoneyPair(
          left: _transport,
          leftLabel: 'Transport',
          right: _food,
          rightLabel: 'Food',
          validator: _optional,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _special,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Special allowance'),
          validator: _optional,
          onChanged: (_) => setState(() {}),
        ),
        if (gross > 0 && difference.abs() >= 0.01) ...[
          const SizedBox(height: 12),
          // Payroll uses these figures exactly as entered, so a mismatch is
          // worth surfacing while it can still be fixed. It is not refused —
          // the backend accepts it, and some companies genuinely run a gap.
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 15, color: bos.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  difference > 0
                      ? '${Fmt.money(difference)} of gross is not allocated to '
                          'basic or any allowance.'
                      : 'Basic and allowances come to ${Fmt.money(-difference)} '
                          'more than gross.',
                  style: TextStyle(color: bos.warning, fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 18),
        _Label('Deductions'),
        _MoneyPair(
          left: _providentFund,
          leftLabel: 'Provident fund',
          right: _tax,
          rightLabel: 'Tax',
          validator: _optional,
          onChanged: () {},
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
        const SizedBox(height: 10),
        Text(
          'An empty box means zero, not "leave it alone" — the backend treats '
          'a missing figure as nil.',
          style: TextStyle(color: bos.muted, fontSize: 12, height: 1.45),
        ),
      ],
    );
  }
}

/// Two money fields side by side. The structure form has four such pairs and
/// they are identical but for their labels.
class _MoneyPair extends StatelessWidget {
  const _MoneyPair({
    required this.left,
    required this.leftLabel,
    required this.right,
    required this.rightLabel,
    required this.validator,
    required this.onChanged,
  });

  final TextEditingController left;
  final String leftLabel;
  final TextEditingController right;
  final String rightLabel;
  final String? Function(String?) validator;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: left,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: leftLabel),
            validator: validator,
            onChanged: (_) => onChanged(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: right,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: rightLabel),
            validator: validator,
            onChanged: (_) => onChanged(),
          ),
        ),
      ],
    );
  }
}

// ── Loans ─────────────────────────────────────────────────────

Future<void> showLoanSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _LoanSheet(),
  );
}

class _LoanSheet extends ConsumerStatefulWidget {
  const _LoanSheet();

  @override
  ConsumerState<_LoanSheet> createState() => _LoanSheetState();
}

class _LoanSheetState extends ConsumerState<_LoanSheet> {
  final _formKey = GlobalKey<FormState>();
  final _principal = TextEditingController();
  final _installment = TextEditingController();
  final _reason = TextEditingController();
  final _notes = TextEditingController();

  String _type = 'LOAN';
  DateTime? _disbursedDate = DateTime.now();
  int? _employeeId;
  String? _employeeName;

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _principal.dispose();
    _installment.dispose();
    _reason.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickEmployee() async {
    final person = await EmployeePicker.show(context, title: 'Who is it for?');
    if (person == null || !mounted) return;
    setState(() {
      _employeeId = person.id;
      _employeeName = person.fullName;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final employeeId = _employeeId;
    final disbursedDate = _disbursedDate;
    if (employeeId == null) {
      setState(() => _error = 'Pick who it is for.');
      return;
    }
    if (disbursedDate == null) {
      setState(() => _error = 'Pick the date it was paid out.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(salaryRepositoryProvider).createLoan(
            CreateLoanRequest(
              employeeId: employeeId,
              type: _type,
              principalAmount: double.parse(_principal.text.trim()),
              disbursedDate: Fmt.isoDate(disbursedDate),
              monthlyInstallment: double.parse(_installment.text.trim()),
              reason: _reason.text,
              notes: _notes.text,
            ),
          );
      await ref.read(loansProvider.notifier).refresh();
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Recorded. Payroll recovers it from next month.'),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not record that.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _money(String? value) {
    final parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null) return 'An amount is required.';
    // Both figures are @DecimalMin("0.01").
    return parsed <= 0 ? 'More than zero.' : null;
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    final principal = double.tryParse(_principal.text.trim()) ?? 0;
    final installment = double.tryParse(_installment.text.trim()) ?? 0;
    final months =
        (principal > 0 && installment > 0) ? (principal / installment).ceil() : null;

    return FormSheetFrame(
      title: 'Record a loan or advance',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'Record it',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        InkWell(
          onTap: _pickEmployee,
          borderRadius: BorderRadius.circular(10),
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Employee',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            child: Text(
              _employeeName ?? 'Tap to choose',
              style: TextStyle(
                color: _employeeName == null ? bos.muted : bos.text,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _type,
          decoration: const InputDecoration(
            labelText: 'Kind',
            prefixIcon: Icon(Icons.account_balance_wallet_outlined),
          ),
          items: [
            for (final type in loanTypes)
              DropdownMenuItem(value: type, child: Text(Fmt.label(type))),
          ],
          onChanged: (value) => setState(() => _type = value ?? _type),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _principal,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount'),
                validator: _money,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _installment,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Per month'),
                validator: _money,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        if (months != null) ...[
          const SizedBox(height: 8),
          Text(
            months == 1
                ? 'Recovered in one instalment.'
                : 'Recovered over $months months, the last one short.',
            style: TextStyle(color: bos.muted, fontSize: 12.5),
          ),
        ],
        const SizedBox(height: 16),
        DateField(
          label: 'Paid out on',
          value: _disbursedDate,
          clearable: false,
          lastDate: DateTime.now(),
          onChanged: (value) => setState(() => _disbursedDate = value),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _reason,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
            prefixIcon: Icon(Icons.notes_rounded),
          ),
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
        const SizedBox(height: 10),
        MessageBanner.info(
          'There is no editing a loan afterwards — payroll acts on it. A '
          'mistake is cancelled and recorded again.',
        ),
      ],
    );
  }
}

// ── Component catalogue ───────────────────────────────────────

Future<void> showComponentSheet(
  BuildContext context, {
  SalaryComponent? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ComponentSheet(existing: existing),
  );
}

class _ComponentSheet extends ConsumerStatefulWidget {
  const _ComponentSheet({this.existing});

  final SalaryComponent? existing;

  @override
  ConsumerState<_ComponentSheet> createState() => _ComponentSheetState();
}

class _ComponentSheetState extends ConsumerState<_ComponentSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _sortOrder = TextEditingController(
    text: '${widget.existing?.sortOrder ?? 0}',
  );

  late String _type = widget.existing?.type ?? componentTypes.first;
  late String _calculationType =
      widget.existing?.calculationType ?? calculationTypes.first;
  late bool _taxable = widget.existing?.taxable ?? true;
  late bool _active = widget.existing?.active ?? true;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _sortOrder.dispose();
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
    final repo = ref.read(salaryRepositoryProvider);
    final request = SalaryComponentRequest(
      name: _name.text,
      type: _type,
      calculationType: _calculationType,
      taxable: _taxable,
      active: _active,
      sortOrder: int.tryParse(_sortOrder.text.trim()) ?? 0,
    );

    try {
      if (_isEdit) {
        final updated =
            await repo.updateComponent(widget.existing!.id, request);
        ref.read(salaryComponentsProvider.notifier).apply(updated);
      } else {
        await repo.createComponent(request);
        await ref.read(salaryComponentsProvider.notifier).refresh();
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(_isEdit ? 'Component updated.' : 'Component added.'),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save that component.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: _isEdit ? 'Edit component' : 'New component',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: _isEdit ? 'Save changes' : 'Add component',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        TextFormField(
          controller: _name,
          autofocus: !_isEdit,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            helperText: 'What it appears as on a payslip',
            prefixIcon: Icon(Icons.label_outline_rounded),
          ),
          validator: (value) =>
              (value?.trim().isEmpty ?? true) ? 'A name is required.' : null,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _type,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Kind'),
          items: [
            for (final type in componentTypes)
              DropdownMenuItem(value: type, child: Text(Fmt.label(type))),
          ],
          onChanged: (value) => setState(() => _type = value ?? _type),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _calculationType,
          decoration: const InputDecoration(labelText: 'Worked out as'),
          items: [
            for (final type in calculationTypes)
              DropdownMenuItem(
                value: type,
                child: Text(type == 'FIXED' ? 'A fixed amount' : 'A percentage'),
              ),
          ],
          onChanged: (value) =>
              setState(() => _calculationType = value ?? _calculationType),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _sortOrder,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Position on the payslip',
            prefixIcon: Icon(Icons.format_list_numbered_rounded),
          ),
          validator: (value) {
            final trimmed = value?.trim() ?? '';
            if (trimmed.isEmpty) return null;
            return int.tryParse(trimmed) == null ? 'A whole number.' : null;
          },
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          value: _taxable,
          onChanged: (value) => setState(() => _taxable = value),
          title: Text('Taxable', style: TextStyle(color: bos.text, fontSize: 14)),
          subtitle: Text(
            'Counts towards the tax deduction',
            style: TextStyle(color: bos.muted, fontSize: 11.5),
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        SwitchListTile(
          value: _active,
          onChanged: (value) => setState(() => _active = value),
          title: Text('In use', style: TextStyle(color: bos.text, fontSize: 14)),
          subtitle: Text(
            'Structures that already use it keep it',
            style: TextStyle(color: bos.muted, fontSize: 11.5),
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
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
