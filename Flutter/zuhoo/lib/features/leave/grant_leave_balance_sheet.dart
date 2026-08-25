import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/employee_picker.dart';
import '../../shared/widgets/primitives.dart';
import '../directory/directory_models.dart';
import 'leave_models.dart';
import 'leave_repository.dart';

/// Grants somebody a leave entitlement for a year.
///
/// HR configuration rather than self-service, so it is gated on
/// LEAVE_BALANCE_CREATE — a different code from approving leave, because
/// deciding a request and granting the days are different jobs.
Future<void> showGrantLeaveBalanceSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _GrantLeaveBalanceSheet(),
  );
}

class _GrantLeaveBalanceSheet extends ConsumerStatefulWidget {
  const _GrantLeaveBalanceSheet();

  @override
  ConsumerState<_GrantLeaveBalanceSheet> createState() =>
      _GrantLeaveBalanceSheetState();
}

class _GrantLeaveBalanceSheetState
    extends ConsumerState<_GrantLeaveBalanceSheet> {
  final _formKey = GlobalKey<FormState>();
  final _days = TextEditingController();

  Person? _employee;
  String _leaveType = allLeaveTypes.first;
  late int _year = DateTime.now().year;

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  Future<void> _pickEmployee() async {
    final person =
        await EmployeePicker.show(context, title: 'Grant leave days to');
    if (person != null) setState(() => _employee = person);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_employee == null) {
      setState(() => _error = 'Choose who the days are for.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(leaveRepositoryProvider).createBalance(
            LeaveBalanceRequest(
              employeeId: _employee!.id,
              leaveType: _leaveType,
              year: _year,
              totalDays: int.parse(_days.text.trim()),
            ),
          );
      // Whoever is looking at their own balances may now have a new one.
      ref.invalidate(leaveControllerProvider);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${_days.text.trim()} ${Fmt.label(_leaveType).toLowerCase()} days '
            'granted to ${_employee!.fullName}.',
          ),
        ),
      );
    } on ApiException catch (e) {
      // "A SICK balance for 2026 already exists for this employee" lands here
      // and names exactly what clashed, so it is shown as written.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not grant that balance.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final thisYear = DateTime.now().year;
    // Last year for a correction, this year, next year for planning ahead.
    final years = [thisYear - 1, thisYear, thisYear + 1];

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
                'Grant a leave balance',
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
              DropdownButtonFormField<String>(
                initialValue: _leaveType,
                decoration: const InputDecoration(
                  labelText: 'Leave type',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: [
                  for (final type in allLeaveTypes)
                    DropdownMenuItem(value: type, child: Text(Fmt.label(type))),
                ],
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _leaveType = value ?? _leaveType),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: _year,
                decoration: const InputDecoration(
                  labelText: 'Year',
                  prefixIcon: Icon(Icons.calendar_today_rounded),
                ),
                items: [
                  for (final year in years)
                    DropdownMenuItem(value: year, child: Text('$year')),
                ],
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _year = value ?? _year),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _days,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Total days',
                  prefixIcon: Icon(Icons.event_available_outlined),
                ),
                validator: (value) {
                  final parsed = int.tryParse(value?.trim() ?? '');
                  // Whole days only: the field is an Integer server-side, even
                  // though a balance reads back with halves used against it.
                  if (parsed == null) return 'Enter a whole number of days.';
                  return parsed < 0 ? 'Cannot be negative.' : null;
                },
              ),
              const SizedBox(height: 18),
              LoadingButton(
                label: 'Grant balance',
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
