import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/stat_card.dart';
import 'attendance_admin_repository.dart';
import 'attendance_models.dart';

/// The window an employee's attendance is being read over.
///
/// Defaults to the month so far, which is what somebody asking "how has this
/// person been" almost always means.
({DateTime from, DateTime to}) _defaultRange() {
  final now = DateTime.now();
  return (from: DateTime(now.year, now.month, 1), to: now);
}

class AttendanceRangeController
    extends Notifier<({DateTime from, DateTime to})> {
  @override
  ({DateTime from, DateTime to}) build() => _defaultRange();

  void set(DateTime from, DateTime to) => state = (from: from, to: to);
}

final attendanceRangeProvider = NotifierProvider<AttendanceRangeController,
    ({DateTime from, DateTime to})>(AttendanceRangeController.new);

String _iso(DateTime day) => '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// One person's figures over the window in view.
final employeeSummaryProvider =
    FutureProvider.autoDispose.family<EmployeeAttendanceSummary, int>(
  (ref, employeeId) {
    final range = ref.watch(attendanceRangeProvider);
    return ref.read(attendanceAdminRepositoryProvider).employeeSummary(
          employeeId,
          _iso(range.from),
          _iso(range.to),
        );
  },
);

/// One person's records.
final employeeRecordsProvider =
    FutureProvider.autoDispose.family<List<AttendanceRecord>, int>(
  (ref, employeeId) async {
    final page = await ref
        .read(attendanceAdminRepositoryProvider)
        .recordsFor(employeeId);
    return page.content;
  },
);

/// One person's timesheets.
final employeeTimesheetsProvider =
    FutureProvider.autoDispose.family<List<Timesheet>, int>(
  (ref, employeeId) async {
    final range = ref.watch(attendanceRangeProvider);
    // The range endpoint rather than the paged one: over a month it is a
    // handful of rows, and asking for exactly the window on screen means the
    // list and the figures above it always agree.
    return ref.read(attendanceAdminRepositoryProvider).timesheetRange(
          employeeId,
          _iso(range.from),
          _iso(range.to),
        );
  },
);

/// How one person has been: their figures, their days, and their timesheets.
///
/// Opened from the team view or from a profile, where the question is about a
/// person rather than about a day.
class EmployeeAttendanceScreen extends ConsumerWidget {
  const EmployeeAttendanceScreen({
    super.key,
    required this.employeeId,
    required this.name,
  });

  final int employeeId;
  final String name;

  static void open(
    BuildContext context, {
    required int employeeId,
    required String name,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EmployeeAttendanceScreen(
          employeeId: employeeId,
          name: name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final range = ref.watch(attendanceRangeProvider);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(
        title: Text(name),
        actions: [
          IconButton(
            tooltip: 'Change the period',
            icon: const Icon(Icons.date_range_outlined),
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(DateTime.now().year - 3),
                lastDate: DateTime.now(),
                initialDateRange:
                    DateTimeRange(start: range.from, end: range.to),
              );
              if (picked == null) return;
              ref
                  .read(attendanceRangeProvider.notifier)
                  .set(picked.start, picked.end);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: bos.brand,
        backgroundColor: bos.bgCard,
        onRefresh: () async {
          ref.invalidate(employeeSummaryProvider(employeeId));
          ref.invalidate(employeeRecordsProvider(employeeId));
          ref.invalidate(employeeTimesheetsProvider(employeeId));
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Text(
              '${Fmt.dateShort(_iso(range.from))} — '
              '${Fmt.dateShort(_iso(range.to))}',
              style: TextStyle(color: bos.muted, fontSize: 12),
            ),
            const SizedBox(height: 10),
            _Summary(employeeId: employeeId),
            const SizedBox(height: 20),
            const SectionHeader('Timesheets', icon: Icons.timer_outlined),
            _Timesheets(employeeId: employeeId),
            const SizedBox(height: 20),
            const SectionHeader(
              'Recent days',
              icon: Icons.calendar_today_outlined,
            ),
            _Records(employeeId: employeeId),
          ],
        ),
      ),
    );
  }
}

class _Summary extends ConsumerWidget {
  const _Summary({required this.employeeId});

  final int employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(employeeSummaryProvider(employeeId));

    return async.when(
      loading: () => const Loader(padding: 20),
      error: (error, _) => MessageBanner.error(
        error is ApiException
            ? error.message
            : 'Could not work out the figures.',
      ),
      data: (summary) => Column(
        children: [
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'Present',
                  value: summary.presentDays.toString(),
                  icon: Icons.how_to_reg_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  label: 'Absent',
                  value: summary.absentDays.toString(),
                  icon: Icons.person_off_outlined,
                  tone: summary.absentDays > 0 ? bos.warning : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'Late',
                  value: summary.lateDays.toString(),
                  icon: Icons.running_with_errors_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  label: 'Turned up',
                  // The backend's own figure rather than one worked out here.
                  // It counts against days with a record, not against the
                  // calendar, so it does not fall when somebody is on leave.
                  value: summary.attendancePercentage.toStringAsFixed(0),
                  suffix: '%',
                  icon: Icons.percent_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Timesheets extends ConsumerStatefulWidget {
  const _Timesheets({required this.employeeId});

  final int employeeId;

  @override
  ConsumerState<_Timesheets> createState() => _TimesheetsState();
}

class _TimesheetsState extends ConsumerState<_Timesheets> {
  int? _busyId;

  Future<void> _approve(Timesheet timesheet) async {
    setState(() => _busyId = timesheet.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(attendanceAdminRepositoryProvider)
          .approveTimesheet(timesheet.id);
      ref.invalidate(employeeTimesheetsProvider(widget.employeeId));
      messenger.showSnackBar(const SnackBar(content: Text('Approved.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not approve that.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(employeeTimesheetsProvider(widget.employeeId));
    final canApprove = ref
        .watch(permissionControllerProvider)
        .has(AttendanceAdminPermissions.timesheetApprove);

    return AppCard(
      child: async.when(
        loading: () => const Loader(padding: 12),
        error: (error, _) => MessageBanner.error(
          error is ApiException
              ? error.message
              : 'Could not load the timesheets.',
        ),
        data: (timesheets) => timesheets.isEmpty
            ? Text(
                'Nothing logged over this period.',
                style: TextStyle(color: bos.muted, fontSize: 13),
              )
            : Column(
                children: [
                  for (final timesheet in timesheets)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  Fmt.dayDate(timesheet.workDate),
                                  style: TextStyle(
                                    color: bos.text,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  [
                                    Fmt.hours(timesheet.hoursWorked),
                                    if (timesheet.projectName != null)
                                      timesheet.projectName!,
                                  ].join('  ·  '),
                                  style: TextStyle(
                                    color: bos.muted,
                                    fontSize: 11.5,
                                  ),
                                ),
                                if (timesheet.description != null)
                                  Text(
                                    timesheet.description!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: bos.muted,
                                      fontSize: 11.5,
                                      height: 1.4,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (_busyId == timesheet.id)
                            const SizedBox(
                              height: 16,
                              width: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          // Only a submitted sheet can be approved. One still
                          // being written is the employee's to change.
                          else if (canApprove &&
                              timesheet.status == TimesheetStatus.submitted)
                            TextButton(
                              onPressed: () => _approve(timesheet),
                              child: const Text('Approve'),
                            )
                          else
                            StatusChip(timesheet.status, dense: true),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _Records extends ConsumerWidget {
  const _Records({required this.employeeId});

  final int employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(employeeRecordsProvider(employeeId));

    return AppCard(
      child: async.when(
        loading: () => const Loader(padding: 12),
        error: (error, _) => MessageBanner.error(
          error is ApiException
              ? error.message
              : 'Could not load their days.',
        ),
        data: (records) => records.isEmpty
            ? Text(
                'Nothing recorded.',
                style: TextStyle(color: bos.muted, fontSize: 13),
              )
            : Column(
                children: [
                  for (final record in records.take(30))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              Fmt.dayDate(record.attendanceDate),
                              style:
                                  TextStyle(color: bos.text, fontSize: 12.5),
                            ),
                          ),
                          if (record.checkInTime != null)
                            Text(
                              [
                                Fmt.clock(record.checkInTime),
                                if (record.checkOutTime != null)
                                  Fmt.clock(record.checkOutTime),
                              ].join(' — '),
                              style:
                                  TextStyle(color: bos.muted, fontSize: 11.5),
                            ),
                          // A pin rather than the place name itself: a manager
                          // scanning 30 rows for anomalies needs "was this
                          // tagged at all", not the address, on every row —
                          // long-press for the actual place.
                          if ((record.checkInLocation
                                      ?.trim()
                                      .isNotEmpty ??
                                  false) ||
                              (record.checkOutLocation
                                      ?.trim()
                                      .isNotEmpty ??
                                  false)) ...[
                            const SizedBox(width: 6),
                            Tooltip(
                              message: [
                                if (record.checkInLocation
                                        ?.trim()
                                        .isNotEmpty ??
                                    false)
                                  'In: ${record.checkInLocation}',
                                if (record.checkOutLocation
                                        ?.trim()
                                        .isNotEmpty ??
                                    false)
                                  'Out: ${record.checkOutLocation}',
                              ].join('\n'),
                              child: Icon(
                                Icons.location_on_outlined,
                                size: 14,
                                color: bos.muted,
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                          StatusChip(record.status, dense: true),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
