import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/date_field.dart';
import '../../shared/widgets/employee_picker.dart';
import '../../shared/widgets/primitives.dart';
import '../directory/directory_models.dart';
import 'attendance_models.dart';
import 'attendance_repository.dart';

/// The shifts available to assign somebody to.
///
/// Fetched only when the sheet opens rather than kept alive: it is a short,
/// rarely-changing list needed on one screen, and a stale one would offer a
/// shift that has since been retired.
final activeShiftsProvider = FutureProvider.autoDispose<List<Shift>>(
  (ref) => ref.read(attendanceRepositoryProvider).activeShifts(),
);

/// Puts somebody on a shift.
Future<void> showAssignShiftSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _AssignShiftSheet(),
  );
}

class _AssignShiftSheet extends ConsumerStatefulWidget {
  const _AssignShiftSheet();

  @override
  ConsumerState<_AssignShiftSheet> createState() => _AssignShiftSheetState();
}

class _AssignShiftSheetState extends ConsumerState<_AssignShiftSheet> {
  final _reason = TextEditingController();

  Person? _employee;
  int? _shiftId;
  late DateTime _startDate = DateTime.now();
  DateTime? _endDate;

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickEmployee() async {
    final person = await EmployeePicker.show(context, title: 'Assign a shift to');
    if (person != null) setState(() => _employee = person);
  }

  Future<void> _submit() async {
    if (_submitting) return;

    if (_employee == null) {
      setState(() => _error = 'Choose who the shift is for.');
      return;
    }
    if (_shiftId == null) {
      setState(() => _error = 'Choose a shift.');
      return;
    }
    if (_endDate != null && _endDate!.isBefore(_startDate)) {
      setState(() => _error = 'The assignment ends before it starts.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(attendanceRepositoryProvider).assignShift(
            ShiftAssignmentRequest(
              employeeId: _employee!.id,
              shiftId: _shiftId!,
              assignmentStartDate: Fmt.isoDate(_startDate),
              assignmentEndDate:
                  _endDate == null ? null : Fmt.isoDate(_endDate!),
              reason: _reason.text,
            ),
          );
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text('${_employee!.fullName} assigned to the shift.')),
      );
    } on ApiException catch (e) {
      // An overlapping assignment is refused, and the message names the clash.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not assign that shift.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final now = DateTime.now();
    final shifts = ref.watch(activeShiftsProvider);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Assign a shift',
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
            shifts.when(
              loading: () => const Loader(padding: 12),
              error: (_, _) => const MessageBanner.error(
                'Could not load the shifts to choose from.',
              ),
              data: (available) {
                if (available.isEmpty) {
                  return const MessageBanner.info(
                    'No active shifts to assign. They are set up on the web.',
                  );
                }
                return DropdownButtonFormField<int>(
                  initialValue: _shiftId,
                  decoration: const InputDecoration(
                    labelText: 'Shift',
                    prefixIcon: Icon(Icons.schedule_rounded),
                  ),
                  items: [
                    for (final shift in available)
                      DropdownMenuItem(
                        value: shift.id,
                        child: Text('${shift.name} · ${shift.hoursLabel}'),
                      ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _shiftId = value),
                );
              },
            ),
            const SizedBox(height: 16),
            DateField(
              label: 'From',
              value: _startDate,
              enabled: !_submitting,
              clearable: false,
              firstDate: DateTime(now.year - 1),
              lastDate: DateTime(now.year + 2),
              onChanged: (date) {
                if (date != null) setState(() => _startDate = date);
              },
            ),
            const SizedBox(height: 16),
            DateField(
              label: 'Until (optional)',
              value: _endDate,
              enabled: !_submitting,
              firstDate: DateTime(now.year - 1),
              lastDate: DateTime(now.year + 3),
              emptyText: 'Open-ended',
              onChanged: (date) => setState(() => _endDate = date),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reason,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'Covering the late shift while Karim is away',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 18),
            LoadingButton(
              label: 'Assign shift',
              loading: _submitting,
              icon: Icons.check_rounded,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
