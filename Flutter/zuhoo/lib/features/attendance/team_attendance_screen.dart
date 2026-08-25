import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/config_list.dart';
import '../../shared/widgets/date_field.dart';
import '../../shared/widgets/employee_picker.dart';
import '../../shared/widgets/form_sheet.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import '../../shared/widgets/stat_card.dart';
import 'attendance_admin_repository.dart';
import 'attendance_models.dart';

/// Who turned up, and who did not.
///
/// One day at a time, because that is how attendance is actually checked —
/// somebody looks at today, sees who is missing, and fixes the records that
/// are wrong. The month's figures sit underneath for context.
class TeamAttendanceScreen extends ConsumerWidget {
  const TeamAttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final permissions = ref.watch(permissionControllerProvider);

    if (!permissions.loaded && permissions.codes.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Who is in')),
        body: const Loader(),
      );
    }

    if (!permissions.has(AttendanceAdminPermissions.view)) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Who is in')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Not available to you',
          message:
              'Seeing everybody’s attendance needs the attendance permissions. '
              'Your own is on the Attendance screen.',
        ),
      );
    }

    final day = ref.watch(attendanceDayProvider);
    final canMark = permissions.has(AttendanceAdminPermissions.mark);
    final isOwner = ref.watch(currentUserProvider)?.isCompanyOwner ?? false;

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(
        title: const Text('Who is in'),
        actions: [
          // Backfilling is the company owner's alone, and only ever needed
          // when the nightly marker did not run.
          if (isOwner)
            IconButton(
              onPressed: () => showBackfillSheet(context),
              tooltip: 'Fill in missing absences',
              icon: const Icon(Icons.event_repeat_rounded),
            ),
        ],
      ),
      floatingActionButton: canMark
          ? FloatingActionButton.extended(
              onPressed: () => showManualAttendanceSheet(context, day: day),
              backgroundColor: bos.brand,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.edit_calendar_outlined),
              label: const Text('Record a day'),
            )
          : null,
      body: const _Body(),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body();

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  int? _busyId;

  Future<void> _approve(AttendanceRecord record) async {
    setState(() => _busyId = record.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(attendanceAdminRepositoryProvider)
          .approveRecord(record.id);
      // No response body, so the list reloads rather than being patched.
      await ref.read(teamAttendanceProvider.notifier).refresh();
      messenger.showSnackBar(const SnackBar(content: Text('Approved.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not approve that record.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final day = ref.watch(attendanceDayProvider);
    final daily = ref.watch(dailyReportProvider).value;
    final canApprove =
        ref.watch(permissionControllerProvider).has(
              AttendanceAdminPermissions.approve,
            );

    final today = DateTime.now();
    final atToday = day.year == today.year &&
        day.month == today.month &&
        day.day == today.day;

    return ConfigList<AttendanceRecord>(
      async: ref.watch(teamAttendanceProvider),
      onRefresh: () async {
        ref.invalidate(dailyReportProvider);
        ref.invalidate(monthlyReportProvider);
        await ref.read(teamAttendanceProvider.notifier).refresh();
      },
      emptyIcon: Icons.event_busy_outlined,
      emptyTitle: 'Nothing recorded',
      emptyMessage:
          'No attendance has been recorded for this day yet. If it has passed, '
          'the nightly absentee marker may not have run.',
      errorMessage: 'Could not load the attendance.',
      header: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppCard(
              child: Row(
                children: [
                  IconButton(
                    onPressed: () =>
                        ref.read(attendanceDayProvider.notifier).shift(-1),
                    icon: const Icon(Icons.chevron_left_rounded),
                    tooltip: 'Previous day',
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        atToday ? 'Today' : Fmt.dayDate(Fmt.isoDate(day)),
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    // Attendance for a day that has not happened is not a
                    // thing, so forward stops at today.
                    onPressed: atToday
                        ? null
                        : () =>
                            ref.read(attendanceDayProvider.notifier).shift(1),
                    icon: const Icon(Icons.chevron_right_rounded),
                    tooltip: 'Next day',
                  ),
                ],
              ),
            ),
            if (daily != null) ...[
              const SizedBox(height: 12),
              _DayFigures(report: daily),
            ],
          ],
        ),
      ),
      itemBuilder: (context, record) => _RecordRow(
        record: record,
        busy: _busyId == record.id,
        onApprove: canApprove ? () => _approve(record) : null,
      ),
    );
  }
}

class _DayFigures extends ConsumerWidget {
  const _DayFigures({required this.report});

  final DailyAttendanceReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final monthly = ref.watch(monthlyReportProvider).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'In',
                value: '${report.presentCount + report.lateCount}',
                suffix: 'of ${report.totalEmployees}',
                icon: Icons.how_to_reg_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                label: 'Late',
                value: '${report.lateCount}',
                icon: Icons.schedule_rounded,
                tone: report.lateCount > 0 ? bos.warning : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'Absent',
                value: '${report.absentCount}',
                icon: Icons.person_off_outlined,
                tone: report.absentCount > 0 ? bos.danger : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                label: 'On leave',
                value: '${report.onLeaveCount}',
                icon: Icons.beach_access_outlined,
              ),
            ),
          ],
        ),
        if (report.unaccounted > 0) ...[
          const SizedBox(height: 10),
          // Nobody has a record at all for this day — almost always the
          // nightly absentee marker not having run.
          MessageBanner.warning(
            report.unaccounted == 1
                ? '1 person has no record for this day at all.'
                : '${report.unaccounted} people have no record for this day at '
                    'all.',
          ),
        ],
        if (monthly != null) ...[
          const SizedBox(height: 12),
          AppCard(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${Fmt.monthYear(monthly.month, monthly.year)}: '
                    '${Fmt.percent(monthly.attendancePercentage)} attendance '
                    'over ${monthly.totalWorkingDays} working days',
                    style: TextStyle(color: bos.muted, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({
    required this.record,
    required this.busy,
    this.onApprove,
  });

  final AttendanceRecord record;
  final bool busy;
  final VoidCallback? onApprove;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.employeeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (record.checkInTime != null)
                        'in ${Fmt.clock(record.checkInTime)}',
                      if (record.checkOutTime != null)
                        'out ${Fmt.clock(record.checkOutTime)}',
                      if (record.checkInTime == null &&
                          record.checkOutTime == null)
                        'no times recorded',
                    ].join(' · '),
                    style: TextStyle(color: bos.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            StatusChip(record.status, dense: true),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(10),
                child: SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (onApprove != null)
              IconButton(
                onPressed: onApprove,
                icon: const Icon(Icons.check_rounded, size: 18),
                tooltip: 'Approve',
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Recording a day by hand ───────────────────────────────────

Future<void> showManualAttendanceSheet(
  BuildContext context, {
  required DateTime day,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ManualSheet(day: day),
  );
}

class _ManualSheet extends ConsumerStatefulWidget {
  const _ManualSheet({required this.day});

  final DateTime day;

  @override
  ConsumerState<_ManualSheet> createState() => _ManualSheetState();
}

class _ManualSheetState extends ConsumerState<_ManualSheet> {
  final _formKey = GlobalKey<FormState>();
  final _notes = TextEditingController();
  final _lateReason = TextEditingController();

  late DateTime? _date = widget.day;
  String _status = AttendanceStatus.present;
  TimeOfDay? _checkIn = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay? _checkOut = const TimeOfDay(hour: 17, minute: 0);
  int? _employeeId;
  String? _employeeName;

  bool _submitting = false;
  String? _error;

  /// Only PRESENT and LATE carry times; the rest are whole-day states.
  bool get _hasTimes =>
      _status == AttendanceStatus.present || _status == AttendanceStatus.late;

  @override
  void dispose() {
    _notes.dispose();
    _lateReason.dispose();
    super.dispose();
  }

  Future<void> _pickEmployee() async {
    final person = await EmployeePicker.show(context, title: 'Whose day?');
    if (person == null || !mounted) return;
    setState(() {
      _employeeId = person.id;
      _employeeName = person.fullName;
      _error = null;
    });
  }

  Future<void> _pickTime({required bool start}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime:
          (start ? _checkIn : _checkOut) ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _checkIn = picked;
      } else {
        _checkOut = picked;
      }
    });
  }

  static String _iso(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}:00';

  Future<void> _submit() async {
    if (_submitting) return;
    final employeeId = _employeeId;
    final date = _date;
    if (employeeId == null) {
      setState(() => _error = 'Pick whose day this is.');
      return;
    }
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
    try {
      await ref.read(attendanceAdminRepositoryProvider).createManual(
            ManualAttendanceRequest(
              employeeId: employeeId,
              attendanceDate: Fmt.isoDate(date),
              status: _status,
              checkInTime:
                  _hasTimes && _checkIn != null ? _iso(_checkIn!) : null,
              checkOutTime:
                  _hasTimes && _checkOut != null ? _iso(_checkOut!) : null,
              // Taken from the status rather than asked: a human guessing at
              // lateness against a shift they cannot see would be worse.
              isLate: _status == AttendanceStatus.late,
              lateReason:
                  _status == AttendanceStatus.late ? _lateReason.text : null,
              notes: _notes.text,
            ),
          );
      ref.read(attendanceDayProvider.notifier).set(date);
      await ref.read(teamAttendanceProvider.notifier).refresh();
      ref.invalidate(dailyReportProvider);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Recorded.')));
    } on ApiException catch (e) {
      // A second record for the same person and day is refused by name.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not record that day.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: 'Record a day',
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
        DateField(
          label: 'Date',
          value: _date,
          clearable: false,
          lastDate: DateTime.now(),
          onChanged: (value) => setState(() => _date = value),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _status,
          decoration: const InputDecoration(
            labelText: 'What happened',
            prefixIcon: Icon(Icons.fact_check_outlined),
          ),
          items: [
            for (final status in AttendanceStatus.manuallySettable)
              DropdownMenuItem(value: status, child: Text(Fmt.label(status))),
          ],
          onChanged: (value) => setState(() => _status = value ?? _status),
        ),
        if (_hasTimes) ...[
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
                      Text('In',
                          style: TextStyle(color: bos.muted, fontSize: 11)),
                      Text(
                        _checkIn?.format(context) ?? '—',
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
                      Text('Out',
                          style: TextStyle(color: bos.muted, fontSize: 11)),
                      Text(
                        _checkOut?.format(context) ?? '—',
                        style: TextStyle(color: bos.text, fontSize: 15),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
        if (_status == AttendanceStatus.late) ...[
          const SizedBox(height: 16),
          TextFormField(
            controller: _lateReason,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Why they were late (optional)',
              prefixIcon: Icon(Icons.schedule_rounded),
            ),
          ),
        ],
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
        const SizedBox(height: 12),
        MessageBanner.info(
          'Recorded as a manual entry, so it is clear it did not come from a '
          'terminal.',
        ),
      ],
    );
  }
}

// ── Backfilling absences ──────────────────────────────────────

/// Fills in the ABSENT days the nightly marker missed.
///
/// Company owner only, and idempotent — running it twice over the same range
/// creates nothing the second time.
Future<void> showBackfillSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _BackfillSheet(),
  );
}

class _BackfillSheet extends ConsumerStatefulWidget {
  const _BackfillSheet();

  @override
  ConsumerState<_BackfillSheet> createState() => _BackfillSheetState();
}

class _BackfillSheetState extends ConsumerState<_BackfillSheet> {
  final _formKey = GlobalKey<FormState>();

  DateTime? _from = DateTime.now().subtract(const Duration(days: 7));
  DateTime? _to = DateTime.now();

  bool _submitting = false;
  String? _error;

  Future<void> _submit() async {
    if (_submitting) return;
    final from = _from;
    final to = _to;
    if (from == null || to == null) {
      setState(() => _error = 'Both dates are needed.');
      return;
    }
    if (from.isAfter(to)) {
      // The backend refuses this too, but saying so here is quicker.
      setState(() => _error = 'The start cannot be after the end.');
      return;
    }
    if (to.difference(from).inDays > 366) {
      setState(() => _error = 'The range cannot be longer than a year.');
      return;
    }

    final confirmed = await confirmAction(
      context,
      title: 'Fill in missing absences?',
      message:
          'Anybody with no record on a working day in that range is marked '
          'absent. Running it again over the same range does nothing.',
      action: 'Fill them in',
      destructive: false,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      final created = await ref
          .read(attendanceAdminRepositoryProvider)
          .backfillAbsentees(Fmt.isoDate(from), Fmt.isoDate(to));
      await ref.read(teamAttendanceProvider.notifier).refresh();
      ref.invalidate(dailyReportProvider);
      ref.invalidate(monthlyReportProvider);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            created == 0
                ? 'Nothing was missing.'
                : created == 1
                    ? '1 absence recorded.'
                    : '$created absences recorded.',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not fill those in.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: 'Fill in missing absences',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'Fill them in',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        Text(
          'The nightly job marks anybody with no record as absent at 23:00. '
          'If it did not run, this does the same thing for a range of days.',
          style: TextStyle(color: bos.muted, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: DateField(
                label: 'From',
                value: _from,
                clearable: false,
                lastDate: DateTime.now(),
                onChanged: (value) => setState(() => _from = value),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DateField(
                label: 'To',
                value: _to,
                clearable: false,
                lastDate: DateTime.now(),
                onChanged: (value) => setState(() => _to = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        MessageBanner.info(
          'Future dates are ignored, and the range cannot exceed a year.',
        ),
      ],
    );
  }
}
