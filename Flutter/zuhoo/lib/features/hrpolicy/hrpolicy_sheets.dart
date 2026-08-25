import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/date_field.dart';
import '../../shared/widgets/employee_picker.dart';
import '../../shared/widgets/form_sheet.dart';
import '../ai/ai_models.dart' show AiPermissions;
import '../directory/directory_models.dart' show employmentTypes;
import '../leave/leave_models.dart' show allLeaveTypes;
import 'hrpolicy_models.dart';
import 'hrpolicy_repository.dart';

// ── Holidays ──────────────────────────────────────────────────

Future<void> showHolidaySheet(BuildContext context, {Holiday? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _HolidaySheet(existing: existing),
  );
}

class _HolidaySheet extends ConsumerStatefulWidget {
  const _HolidaySheet({this.existing});

  final Holiday? existing;

  @override
  ConsumerState<_HolidaySheet> createState() => _HolidaySheetState();
}

class _HolidaySheetState extends ConsumerState<_HolidaySheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.existing?.description ?? '');

  late DateTime? _date = Fmt.parse(widget.existing?.holidayDate);
  late String _type = widget.existing?.holidayType ?? holidayTypes.first;

  bool _submitting = false;
  bool _drafting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  /// Asks for one holiday from a phrase, then fills the form in. Nothing is
  /// saved until it is saved.
  Future<void> _draft() async {
    final instruction = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const _InstructionDialog(
        title: 'Which holiday?',
        hint: 'Eid al-Fitr next year',
      ),
    );
    if (instruction == null || instruction.trim().isEmpty || !mounted) return;

    setState(() {
      _drafting = true;
      _error = null;
    });
    try {
      final draft =
          await ref.read(hrPolicyRepositoryProvider).draftHoliday(instruction);
      if (!mounted) return;
      setState(() {
        if (draft.name.isNotEmpty) _name.text = draft.name;
        if (draft.description != null) _description.text = draft.description!;
        if (holidayTypes.contains(draft.type)) _type = draft.type;
        final parsed = Fmt.parse(draft.date);
        if (parsed != null) _date = parsed;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not draft that just now.');
    } finally {
      if (mounted) setState(() => _drafting = false);
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final date = _date;
    if (date == null) {
      setState(() => _error = 'Pick the date.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(hrPolicyRepositoryProvider);
    final request = HolidayRequest(
      name: _name.text,
      holidayDate: Fmt.isoDate(date),
      holidayType: _type,
      description: _description.text,
    );

    try {
      if (_isEdit) {
        final updated = await repo.updateHoliday(widget.existing!.id, request);
        ref.read(holidaysProvider.notifier).apply(updated);
      } else {
        await repo.createHoliday(request);
        // The year the holiday falls in may not be the year on screen.
        ref.read(holidayYearProvider.notifier).set(date.year);
        await ref.read(holidaysProvider.notifier).refresh();
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text(_isEdit ? 'Holiday updated.' : 'Holiday added.')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save that holiday.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canDraft =
        ref.watch(permissionControllerProvider).has(AiPermissions.chat);

    return FormSheetFrame(
      title: _isEdit ? 'Edit holiday' : 'New holiday',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: _isEdit ? 'Save changes' : 'Add holiday',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        TextFormField(
          controller: _name,
          autofocus: !_isEdit,
          textCapitalization: TextCapitalization.words,
          maxLength: 150,
          decoration: InputDecoration(
            labelText: 'Name',
            prefixIcon: const Icon(Icons.celebration_outlined),
            suffixIcon: !canDraft || _isEdit
                ? null
                : IconButton(
                    onPressed: _drafting ? null : _draft,
                    tooltip: 'Look one up',
                    icon: _drafting
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome_outlined),
                  ),
          ),
          validator: (value) =>
              (value?.trim().isEmpty ?? true) ? 'A name is required.' : null,
        ),
        DateField(
          label: 'Date',
          value: _date,
          clearable: false,
          onChanged: (value) => setState(() => _date = value),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _type,
          decoration: const InputDecoration(labelText: 'Kind'),
          items: [
            for (final type in holidayTypes)
              DropdownMenuItem(value: type, child: Text(Fmt.label(type))),
          ],
          onChanged: (value) => setState(() => _type = value ?? _type),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _description,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Description (optional)',
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }
}

// ── Leave policies ────────────────────────────────────────────

Future<void> showLeavePolicySheet(
  BuildContext context, {
  LeavePolicy? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _LeavePolicySheet(existing: existing),
  );
}

class _LeavePolicySheet extends ConsumerStatefulWidget {
  const _LeavePolicySheet({this.existing});

  final LeavePolicy? existing;

  @override
  ConsumerState<_LeavePolicySheet> createState() => _LeavePolicySheetState();
}

class _LeavePolicySheetState extends ConsumerState<_LeavePolicySheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _entitlement = TextEditingController(
    text: '${widget.existing?.annualEntitlement ?? 0}',
  );
  late final TextEditingController _carryForward = TextEditingController(
    text: '${widget.existing?.maxCarryForward ?? 0}',
  );
  late final TextEditingController _consecutive = TextEditingController(
    text: widget.existing?.maxConsecutiveDays == null
        ? ''
        : '${widget.existing!.maxConsecutiveDays}',
  );
  late final TextEditingController _fromMonths = TextEditingController(
    text: '${widget.existing?.applicableFromMonths ?? 0}',
  );

  late String _leaveType = widget.existing?.leaveType ?? allLeaveTypes.first;
  late String? _employmentType = widget.existing?.employmentType;
  late bool _requiresApproval = widget.existing?.requiresApproval ?? true;
  late bool _canCarryForward = widget.existing?.canCarryForward ?? false;
  late bool _paid = widget.existing?.paid ?? true;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _entitlement.dispose();
    _carryForward.dispose();
    _consecutive.dispose();
    _fromMonths.dispose();
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
    final repo = ref.read(hrPolicyRepositoryProvider);
    final request = LeavePolicyRequest(
      leaveType: _leaveType,
      annualEntitlement: int.tryParse(_entitlement.text.trim()) ?? 0,
      requiresApproval: _requiresApproval,
      canCarryForward: _canCarryForward,
      paid: _paid,
      employmentType: _employmentType,
      // Only meaningful when carrying forward is allowed at all.
      maxCarryForward:
          _canCarryForward ? int.tryParse(_carryForward.text.trim()) : 0,
      maxConsecutiveDays: int.tryParse(_consecutive.text.trim()),
      applicableFromMonths: int.tryParse(_fromMonths.text.trim()),
    );

    try {
      if (_isEdit) {
        final updated = await repo.updatePolicy(widget.existing!.id, request);
        ref.read(leavePoliciesProvider.notifier).apply(updated);
      } else {
        await repo.createPolicy(request);
        await ref.read(leavePoliciesProvider.notifier).refresh();
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text(_isEdit ? 'Policy updated.' : 'Policy added.')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save that policy.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _wholeDays(String? value, {bool required = false}) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return required ? 'A number of days is required.' : null;
    final parsed = int.tryParse(trimmed);
    if (parsed == null) return 'Whole days only.';
    return parsed < 0 ? 'Zero or more.' : null;
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: _isEdit ? 'Edit leave policy' : 'New leave policy',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: _isEdit ? 'Save changes' : 'Add policy',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        DropdownButtonFormField<String>(
          initialValue:
              allLeaveTypes.contains(_leaveType) ? _leaveType : allLeaveTypes.first,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Leave type',
            prefixIcon: Icon(Icons.beach_access_outlined),
          ),
          items: [
            for (final type in allLeaveTypes)
              DropdownMenuItem(value: type, child: Text(Fmt.label(type))),
          ],
          onChanged: (value) => setState(() => _leaveType = value ?? _leaveType),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String?>(
          initialValue: _employmentType,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Applies to',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('Everybody')),
            for (final type in employmentTypes)
              DropdownMenuItem(value: type, child: Text(Fmt.label(type))),
          ],
          onChanged: (value) => setState(() => _employmentType = value),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _entitlement,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Days a year',
            helperText: 'Zero means the type exists but grants nothing',
            prefixIcon: Icon(Icons.event_available_outlined),
          ),
          validator: (value) => _wholeDays(value, required: true),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _consecutive,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Max in a row'),
                validator: _wholeDays,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _fromMonths,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'After (months)'),
                validator: _wholeDays,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          value: _paid,
          onChanged: (value) => setState(() => _paid = value),
          title: Text('Paid', style: TextStyle(color: bos.text, fontSize: 14)),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        SwitchListTile(
          value: _requiresApproval,
          onChanged: (value) => setState(() => _requiresApproval = value),
          title: Text(
            'Needs approval',
            style: TextStyle(color: bos.text, fontSize: 14),
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        SwitchListTile(
          value: _canCarryForward,
          onChanged: (value) => setState(() => _canCarryForward = value),
          title: Text(
            'Unused days carry over',
            style: TextStyle(color: bos.text, fontSize: 14),
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        if (_canCarryForward) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _carryForward,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'How many carry over at most',
              prefixIcon: Icon(Icons.arrow_forward_rounded),
            ),
            validator: _wholeDays,
          ),
        ],
      ],
    );
  }
}

// ── Shifts ────────────────────────────────────────────────────

Future<void> showShiftSheet(BuildContext context, {Shift? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ShiftSheet(existing: existing),
  );
}

class _ShiftSheet extends ConsumerStatefulWidget {
  const _ShiftSheet({this.existing});

  final Shift? existing;

  @override
  ConsumerState<_ShiftSheet> createState() => _ShiftSheetState();
}

class _ShiftSheetState extends ConsumerState<_ShiftSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _grace = TextEditingController(
    text: '${widget.existing?.gracePeriodMinutes ?? 15}',
  );
  late final TextEditingController _offDays =
      TextEditingController(text: widget.existing?.weeklyOffDays ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.existing?.description ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.existing?.notes ?? '');

  late String _type = widget.existing?.shiftType ?? 'FULL_DAY';
  late TimeOfDay _start = _parse(widget.existing?.startTime, 9);
  late TimeOfDay _end = _parse(widget.existing?.endTime, 17);
  late bool _flexible = widget.existing?.flexible ?? false;
  late bool _nightShift = widget.existing?.nightShift ?? false;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  /// The backend sends `HH:mm:ss`; anything unparseable falls back to a
  /// sensible office hour rather than midnight.
  static TimeOfDay _parse(String? value, int fallbackHour) {
    if (value != null && value.length >= 5) {
      final hour = int.tryParse(value.substring(0, 2));
      final minute = int.tryParse(value.substring(3, 5));
      if (hour != null && minute != null) {
        return TimeOfDay(hour: hour, minute: minute);
      }
    }
    return TimeOfDay(hour: fallbackHour, minute: 0);
  }

  /// `LocalTime` on the other end wants seconds.
  static String _iso(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}:00';

  @override
  void dispose() {
    _name.dispose();
    _grace.dispose();
    _offDays.dispose();
    _description.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickTime({required bool start}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? _start : _end,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
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
    final repo = ref.read(hrPolicyRepositoryProvider);
    final request = ShiftRequest(
      name: _name.text,
      shiftType: _type,
      startTime: _iso(_start),
      endTime: _iso(_end),
      flexible: _flexible,
      nightShift: _nightShift,
      gracePeriodMinutes: int.tryParse(_grace.text.trim()),
      weeklyOffDays: _offDays.text,
      description: _description.text,
      notes: _notes.text,
    );

    try {
      if (_isEdit) {
        final updated = await repo.updateShift(widget.existing!.id, request);
        ref.read(hrShiftsProvider.notifier).apply(updated);
      } else {
        await repo.createShift(request);
        await ref.read(hrShiftsProvider.notifier).refresh();
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text(_isEdit ? 'Shift updated.' : 'Shift added.')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save that shift.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    // Worked out the same way the backend does, so the form and the saved
    // record agree.
    final raw =
        (_end.hour * 60 + _end.minute) - (_start.hour * 60 + _start.minute);
    // A shift that ends before it starts runs past midnight.
    final overnight = raw < 0;
    final minutes = overnight ? raw + (24 * 60) : raw;

    return FormSheetFrame(
      title: _isEdit ? 'Edit shift' : 'New shift',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: _isEdit ? 'Save changes' : 'Add shift',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        TextFormField(
          controller: _name,
          autofocus: !_isEdit,
          textCapitalization: TextCapitalization.words,
          maxLength: 100,
          decoration: const InputDecoration(
            labelText: 'Name',
            prefixIcon: Icon(Icons.schedule_rounded),
          ),
          validator: (value) =>
              (value?.trim().isEmpty ?? true) ? 'A name is required.' : null,
        ),
        DropdownButtonFormField<String>(
          initialValue: _type,
          decoration: const InputDecoration(labelText: 'Kind'),
          items: [
            for (final type in shiftTypes)
              DropdownMenuItem(value: type, child: Text(Fmt.label(type))),
          ],
          onChanged: (value) => setState(() => _type = value ?? _type),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _pickTime(start: true),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Starts',
                        style: TextStyle(color: bos.muted, fontSize: 11)),
                    Text(
                      _start.format(context),
                      style: TextStyle(color: bos.text, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _pickTime(start: false),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Ends',
                        style: TextStyle(color: bos.muted, fontSize: 11)),
                    Text(
                      _end.format(context),
                      style: TextStyle(color: bos.text, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          overnight
              ? '${Fmt.hours(minutes / 60)} a day, running past midnight'
              : '${Fmt.hours(minutes / 60)} a day',
          style: TextStyle(color: bos.muted, fontSize: 12.5),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _grace,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Grace period (minutes)',
            helperText: 'How late somebody can be before it counts',
            prefixIcon: Icon(Icons.timer_outlined),
          ),
          validator: (value) {
            final trimmed = value?.trim() ?? '';
            if (trimmed.isEmpty) return null;
            final parsed = int.tryParse(trimmed);
            if (parsed == null) return 'Whole minutes.';
            return parsed < 0 ? 'Zero or more.' : null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _offDays,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Weekly off days (optional)',
            helperText: 'Comma separated — "Friday, Saturday"',
            prefixIcon: Icon(Icons.weekend_outlined),
          ),
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          value: _flexible,
          onChanged: (value) => setState(() => _flexible = value),
          title: Text(
            'Flexible hours',
            style: TextStyle(color: bos.text, fontSize: 14),
          ),
          subtitle: Text(
            'The times are a guide rather than a rule',
            style: TextStyle(color: bos.muted, fontSize: 11.5),
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        SwitchListTile(
          value: _nightShift,
          onChanged: (value) => setState(() => _nightShift = value),
          title: Text(
            'Night shift',
            style: TextStyle(color: bos.text, fontSize: 14),
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _description,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Description (optional)',
            alignLabelWithHint: true,
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
      ],
    );
  }
}

// ── Letters ───────────────────────────────────────────────────

Future<void> showLetterSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _LetterSheet(),
  );
}

class _LetterSheet extends ConsumerStatefulWidget {
  const _LetterSheet();

  @override
  ConsumerState<_LetterSheet> createState() => _LetterSheetState();
}

class _LetterSheetState extends ConsumerState<_LetterSheet> {
  final _formKey = GlobalKey<FormState>();
  final _content = TextEditingController();
  final _reference = TextEditingController();
  final _signedBy = TextEditingController();

  String _type = letterTypes.first;
  DateTime? _issueDate = DateTime.now();
  int? _employeeId;
  String? _employeeName;

  bool _submitting = false;
  bool _drafting = false;
  String? _error;

  @override
  void dispose() {
    _content.dispose();
    _reference.dispose();
    _signedBy.dispose();
    super.dispose();
  }

  Future<void> _pickEmployee() async {
    final person = await EmployeePicker.show(context, title: 'Who is it about?');
    if (person == null || !mounted) return;
    setState(() {
      _employeeId = person.id;
      _employeeName = person.fullName;
      _error = null;
    });
  }

  /// Writes the body for the chosen person and type.
  Future<void> _draft() async {
    setState(() {
      _drafting = true;
      _error = null;
    });
    try {
      final content = await ref.read(hrPolicyRepositoryProvider).draftLetter(
            letterType: _type,
            employeeId: _employeeId,
          );
      if (!mounted) return;
      setState(() {
        if (content.isNotEmpty) _content.text = content;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not draft that just now.');
    } finally {
      if (mounted) setState(() => _drafting = false);
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final issueDate = _issueDate;
    if (issueDate == null) {
      setState(() => _error = 'Pick the date it is issued.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(hrPolicyRepositoryProvider).createLetter(
            HrLetterRequest(
              letterType: _type,
              issueDate: Fmt.isoDate(issueDate),
              content: _content.text,
              employeeId: _employeeId,
              referenceNumber: _reference.text,
              signedBy: _signedBy.text,
            ),
          );
      await ref.read(lettersProvider.notifier).refresh();
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Drafted. Issue it when it is ready.')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save that letter.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final canDraft =
        ref.watch(permissionControllerProvider).has(AiPermissions.chat);

    return FormSheetFrame(
      title: 'New letter',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'Save as draft',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _type,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Kind',
            prefixIcon: Icon(Icons.description_outlined),
          ),
          items: [
            for (final type in letterTypes)
              DropdownMenuItem(value: type, child: Text(Fmt.label(type))),
          ],
          onChanged: (value) => setState(() => _type = value ?? _type),
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: _pickEmployee,
          borderRadius: BorderRadius.circular(10),
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'About',
              // An offer letter goes to somebody who is not an employee yet;
              // that case is raised from the recruitment screen instead.
              helperText: 'An employee. Offers to candidates start in hiring.',
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
        DateField(
          label: 'Issue date',
          value: _issueDate,
          clearable: false,
          onChanged: (value) => setState(() => _issueDate = value),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _reference,
                textCapitalization: TextCapitalization.characters,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Reference',
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _signedBy,
                textCapitalization: TextCapitalization.words,
                maxLength: 150,
                decoration: const InputDecoration(
                  labelText: 'Signed by',
                  counterText: '',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _content,
          maxLines: 10,
          minLines: 6,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'The letter',
            alignLabelWithHint: true,
            suffixIcon: !canDraft
                ? null
                : IconButton(
                    onPressed: _drafting ? null : _draft,
                    tooltip: 'Draft it',
                    icon: _drafting
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome_outlined),
                  ),
          ),
          validator: (value) => (value?.trim().isEmpty ?? true)
              ? 'A letter needs something in it.'
              : null,
        ),
      ],
    );
  }
}

/// One line of instruction for a draft.
class _InstructionDialog extends StatefulWidget {
  const _InstructionDialog({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  State<_InstructionDialog> createState() => _InstructionDialogState();
}

class _InstructionDialogState extends State<_InstructionDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: widget.hint),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Never mind'),
        ),
        TextButton(
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _controller.text),
          child: const Text('Look it up'),
        ),
      ],
    );
  }
}

/// Drafts the leave policy document from the entitlements already configured.
///
/// Prose, not a record — this is the document handed to staff, written from
/// the policies that exist. Nothing is saved; it is shown to be copied.
Future<void> showPolicyDocumentSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _PolicyDocumentSheet(),
  );
}

class _PolicyDocumentSheet extends ConsumerStatefulWidget {
  const _PolicyDocumentSheet();

  @override
  ConsumerState<_PolicyDocumentSheet> createState() =>
      _PolicyDocumentSheetState();
}

class _PolicyDocumentSheetState
    extends ConsumerState<_PolicyDocumentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _context = TextEditingController();

  bool _remoteWork = false;
  bool _drafting = false;
  String? _document;
  String? _error;

  @override
  void dispose() {
    _context.dispose();
    super.dispose();
  }

  Future<void> _draft() async {
    setState(() {
      _drafting = true;
      _error = null;
    });
    try {
      final document =
          await ref.read(hrPolicyRepositoryProvider).draftPolicyDocument(
                remoteWorkAllowed: _remoteWork,
                additionalContext: _context.text,
              );
      if (mounted) setState(() => _document = document);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not draft the document just now.');
      }
    } finally {
      if (mounted) setState(() => _drafting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: 'Draft the policy document',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: _document == null ? 'Draft it' : 'Draft it again',
      submitting: _drafting,
      onSubmit: _draft,
      children: [
        Text(
          'Writes the leave policy staff are handed, from the entitlements '
          'already set up here. Nothing is saved — copy what you want.',
          style: TextStyle(color: bos.muted, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 14),
        SwitchListTile(
          value: _remoteWork,
          onChanged: (value) => setState(() => _remoteWork = value),
          title: Text(
            'Remote work is allowed',
            style: TextStyle(color: bos.text, fontSize: 14),
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _context,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Anything else it should say (optional)',
            alignLabelWithHint: true,
          ),
        ),
        if (_document != null) ...[
          const SizedBox(height: 18),
          SelectableText(
            _document!,
            style: TextStyle(color: bos.text, fontSize: 13.5, height: 1.55),
          ),
        ],
      ],
    );
  }
}
