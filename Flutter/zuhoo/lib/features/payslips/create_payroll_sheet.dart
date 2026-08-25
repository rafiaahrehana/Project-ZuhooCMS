import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/employee_picker.dart';
import '../../shared/widgets/primitives.dart';
import '../directory/directory_models.dart';
import 'payslip_models.dart';
import 'payslip_repository.dart';

/// Creates one payroll record by hand.
///
/// The exception, not the routine: the monthly run is a batch action on the
/// web that drafts a record for everybody with a salary structure. This is for
/// the person that run missed — a new joiner, or a correction.
Future<void> showCreatePayrollSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _CreatePayrollSheet(),
  );
}

class _CreatePayrollSheet extends ConsumerStatefulWidget {
  const _CreatePayrollSheet();

  @override
  ConsumerState<_CreatePayrollSheet> createState() =>
      _CreatePayrollSheetState();
}

class _CreatePayrollSheetState extends ConsumerState<_CreatePayrollSheet> {
  final _formKey = GlobalKey<FormState>();
  final _basic = TextEditingController();
  final _houseRent = TextEditingController();
  final _medical = TextEditingController();
  final _transport = TextEditingController();
  final _bonus = TextEditingController();
  final _deductions = TextEditingController();
  final _notes = TextEditingController();

  Person? _employee;

  /// Last month, because payroll is run for a period that has finished.
  late int _month = _previousMonth().month;
  late int _year = _previousMonth().year;

  bool _submitting = false;
  String? _error;

  static DateTime _previousMonth() {
    final now = DateTime.now();
    return DateTime(now.year, now.month - 1);
  }

  @override
  void dispose() {
    _basic.dispose();
    _houseRent.dispose();
    _medical.dispose();
    _transport.dispose();
    _bonus.dispose();
    _deductions.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickEmployee() async {
    final person = await EmployeePicker.show(context, title: 'Run payroll for');
    if (person != null) setState(() => _employee = person);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_employee == null) {
      setState(() => _error = 'Choose who this record is for.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(payslipRepositoryProvider).create(
            CreatePayrollRequest(
              employeeId: _employee!.id,
              payMonth: _month,
              payYear: _year,
              basicSalary: double.tryParse(_basic.text.trim()),
              houseRent: double.tryParse(_houseRent.text.trim()),
              medicalAllowance: double.tryParse(_medical.text.trim()),
              transportAllowance: double.tryParse(_transport.text.trim()),
              bonus: double.tryParse(_bonus.text.trim()),
              deductions: double.tryParse(_deductions.text.trim()),
              notes: _notes.text,
            ),
          );
      // The signed-in user may have been the subject of it.
      ref.invalidate(myPayslipsProvider);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${Fmt.monthYear(_month, _year)} payroll created for '
            '${_employee!.fullName}.',
          ),
        ),
      );
    } on ApiException catch (e) {
      // "Payroll already exists for this employee and period" lands here.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not create that record.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final thisYear = DateTime.now().year;
    final years = [thisYear - 1, thisYear];

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
                'Create a payroll record',
                style: TextStyle(
                  color: bos.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              if (_error != null) ...[
                MessageBanner.error(
                  _error!,
                  onDismiss: () => setState(() => _error = null),
                ),
                const SizedBox(height: 14),
              ],
              InkWell(
                onTap: _submitting ? null : _pickEmployee,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Employee',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  child: Text(
                    _employee?.fullName ?? 'Choose a colleague',
                    style: TextStyle(
                      color: _employee == null ? bos.muted : bos.text,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<int>(
                      initialValue: _month,
                      decoration: const InputDecoration(labelText: 'Month'),
                      items: [
                        for (var month = 1; month <= 12; month++)
                          DropdownMenuItem(
                            value: month,
                            child: Text(Fmt.monthName(month)),
                          ),
                      ],
                      onChanged: _submitting
                          ? null
                          : (value) => setState(() => _month = value ?? _month),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<int>(
                      initialValue: _year,
                      decoration: const InputDecoration(labelText: 'Year'),
                      items: [
                        for (final year in years)
                          DropdownMenuItem(value: year, child: Text('$year')),
                      ],
                      onChanged: _submitting
                          ? null
                          : (value) => setState(() => _year = value ?? _year),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const SectionHeader('Figures', icon: Icons.payments_outlined),
              const SizedBox(height: 4),
              Text(
                'Leave a field blank to take it from the employee’s salary '
                'structure. The net is worked out by the backend from '
                'attendance, overtime and any loan repayments.',
                style: TextStyle(color: bos.muted, fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _basic,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Basic'),
                      validator: _money,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _houseRent,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'House rent'),
                      validator: _money,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _medical,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Medical'),
                      validator: _money,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _transport,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Transport'),
                      validator: _money,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _bonus,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Bonus'),
                      validator: _money,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _deductions,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Deductions'),
                      validator: _money,
                    ),
                  ),
                ],
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
                label: 'Create record',
                loading: _submitting,
                icon: Icons.add_rounded,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String? _money(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final parsed = double.tryParse(trimmed);
    if (parsed == null) return 'Enter a number, or leave it blank.';
    return parsed < 0 ? 'Cannot be negative.' : null;
  }
}
