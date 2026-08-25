import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import 'attendance_models.dart';

/// Other people's attendance: reading it, correcting it and reporting on it.
///
/// Its own repository rather than more methods on the existing one. That one
/// is about *your own* attendance — check in, check out, my records — and this
/// is the administrator's view of everybody's. Two different jobs, two
/// different permission sets, and mixing them would blur both.
class AttendanceAdminRepository {
  AttendanceAdminRepository(this._api);

  final ApiClient _api;

  static const _base = '/company/attendance';
  static const _reports = '/company/attendance/reports';
  static const _assignments = '/hrm/attendance/shift-assignments';
  static const _timesheets = '/hr/timesheets';

  // ── Reading other people's ──────────────────────────────────

  /// Everybody's records. Unusually for this codebase the filters are query
  /// parameters and several can apply at once.
  Future<PagedResponse<AttendanceRecord>> records({
    String? status,
    String? date,
    String? search,
    int page = 0,
    int size = 30,
  }) =>
      _api.getPaged(
        _base,
        AttendanceRecord.fromJson,
        page: page,
        size: size,
        query: {
          if (status != null) 'status': status,
          if (date != null) 'date': date,
          if (search != null && search.isNotEmpty) 'search': search,
        },
      );

  /// One person's records, optionally on one day.
  Future<PagedResponse<AttendanceRecord>> recordsFor(
    int employeeId, {
    String? date,
    int page = 0,
    int size = 30,
  }) =>
      _api.getPaged(
        '$_base/employee/$employeeId',
        AttendanceRecord.fromJson,
        page: page,
        size: size,
        query: {if (date != null) 'date': date},
      );

  // ── Correcting it ───────────────────────────────────────────

  /// Records a day by hand — a missed check-in, a terminal that was down, a
  /// day that needs marking as leave after the fact.
  Future<AttendanceRecord> createManual(
    ManualAttendanceRequest request,
  ) async {
    final json =
        await _api.post<Map<String, dynamic>>('$_base/manual', request.toJson());
    return AttendanceRecord.fromJson(json);
  }

  /// Signs a record off. Empty response, so the caller re-reads.
  Future<void> approveRecord(int id) =>
      _api.patch<dynamic>('$_base/$id/approve');

  /// Fills in the ABSENT days the nightly marker missed.
  ///
  /// Company owner only. Both dates are **query parameters** and both are
  /// required. The backend caps the span at 366 days, never processes a future
  /// date, and is idempotent — running it twice over the same range is safe.
  /// A start after the end is refused with a message rather than a 500.
  Future<int> backfillAbsentees(String startDate, String endDate) async {
    final json = await _api.post<Map<String, dynamic>>(
      '$_base/backfill-absentees?startDate=$startDate&endDate=$endDate',
    );
    // The key is not documented and has changed shape before; both spellings
    // are read and a missing one means nothing was created.
    return (json['created'] as num?)?.toInt() ??
        (json['count'] as num?)?.toInt() ??
        0;
  }

  // ── Reports ─────────────────────────────────────────────────

  /// One day across the company. Without a date the backend uses today.
  Future<DailyAttendanceReport> dailyReport({String? date}) async {
    final json = await _api.get<Map<String, dynamic>>(
      '$_reports/daily',
      query: {if (date != null) 'date': date},
    );
    return DailyAttendanceReport.fromJson(json);
  }

  /// One month. Both parameters are required here.
  Future<MonthlyAttendanceReport> monthlyReport(int month, int year) async {
    final json = await _api.get<Map<String, dynamic>>(
      '$_reports/monthly',
      query: {'month': month, 'year': year},
    );
    return MonthlyAttendanceReport.fromJson(json);
  }

  /// One person over a period. Both dates are required.
  Future<EmployeeAttendanceSummary> employeeSummary(
    int employeeId,
    String startDate,
    String endDate,
  ) async {
    final json = await _api.get<Map<String, dynamic>>(
      '$_reports/employee/$employeeId',
      query: {'startDate': startDate, 'endDate': endDate},
    );
    return EmployeeAttendanceSummary.fromJson(json);
  }

  /// Who was late and who did not turn up.
  Future<({int lateCount, int absentCount})> lateAndAbsent({
    String? date,
  }) async {
    final json = await _api.get<Map<String, dynamic>>(
      '$_reports/late-absent',
      query: {if (date != null) 'date': date},
    );
    return (
      lateCount: (json['lateCount'] as num?)?.toInt() ?? 0,
      absentCount: (json['absentCount'] as num?)?.toInt() ?? 0,
    );
  }

  // ── Shift assignments ───────────────────────────────────────

  /// Everybody on one shift.
  Future<PagedResponse<ShiftAssignment>> assignmentsForShift(
    int shiftId, {
    int page = 0,
    int size = 30,
  }) =>
      _api.getPaged(
        '$_assignments/shift/$shiftId',
        ShiftAssignment.fromJson,
        page: page,
        size: size,
      );

  /// Changes an assignment — a different shift, or different dates.
  Future<ShiftAssignment> updateAssignment(
    int id,
    ShiftAssignmentRequest request,
  ) async {
    final json = await _api.put<Map<String, dynamic>>(
      '$_assignments/$id',
      request.toJson(),
    );
    return ShiftAssignment.fromJson(json);
  }

  /// Ends it as of now rather than deleting the record that it happened. A
  /// `PUT` with no body, and an empty response.
  Future<void> endAssignment(int id) =>
      _api.put<dynamic>('$_assignments/$id/end');

  Future<void> deleteAssignment(int id) =>
      _api.delete<dynamic>('$_assignments/$id');

  // ── Timesheets ──────────────────────────────────────────────

  /// One person's timesheets.
  Future<PagedResponse<Timesheet>> timesheetsFor(
    int employeeId, {
    int page = 0,
    int size = 31,
  }) =>
      _api.getPaged(
        '$_timesheets/employee/$employeeId',
        Timesheet.fromJson,
        page: page,
        size: size,
      );

  /// One person's timesheets over a range. A bare list.
  Future<List<Timesheet>> timesheetRange(
    int employeeId,
    String from,
    String to,
  ) async {
    final list = await _api.get<List<dynamic>>(
      '$_timesheets/employee/$employeeId/range',
      query: {'from': from, 'to': to},
    );
    return list
        .whereType<Map<String, dynamic>>()
        .map(Timesheet.fromJson)
        .toList(growable: false);
  }

  Future<Timesheet> approveTimesheet(int id) async {
    final json =
        await _api.patch<Map<String, dynamic>>('$_timesheets/$id/approve');
    return Timesheet.fromJson(json);
  }
}

final attendanceAdminRepositoryProvider = Provider<AttendanceAdminRepository>(
  (ref) => AttendanceAdminRepository(ref.watch(apiClientProvider)),
);

/// Which day the team view is looking at.
class AttendanceDayController extends Notifier<DateTime> {
  @override
  DateTime build() => DateTime.now();

  void set(DateTime day) {
    state = DateTime(day.year, day.month, day.day);
  }

  /// Steps a day at a time, and refuses to run past today — attendance for a
  /// day that has not happened is not a thing.
  void shift(int days) {
    final moved = state.add(Duration(days: days));
    final today = DateTime.now();
    if (moved.isAfter(DateTime(today.year, today.month, today.day))) return;
    state = moved;
  }
}

final attendanceDayProvider =
    NotifierProvider<AttendanceDayController, DateTime>(
  AttendanceDayController.new,
);

/// Everybody's records for the day in view.
class TeamAttendanceController extends AsyncNotifier<List<AttendanceRecord>> {
  @override
  Future<List<AttendanceRecord>> build() {
    ref.watch(currentUserProvider);
    ref.watch(attendanceDayProvider);
    return _load();
  }

  Future<List<AttendanceRecord>> _load() async {
    final day = ref.read(attendanceDayProvider);
    final page = await ref
        .read(attendanceAdminRepositoryProvider)
        .records(date: _iso(day));
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  void apply(AttendanceRecord updated) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current) if (row.id == updated.id) updated else row,
    ]);
  }
}

final teamAttendanceProvider =
    AsyncNotifierProvider<TeamAttendanceController, List<AttendanceRecord>>(
  TeamAttendanceController.new,
);

/// The day's headline figures, for whichever day is in view.
final dailyReportProvider =
    FutureProvider.autoDispose<DailyAttendanceReport>((ref) {
  final day = ref.watch(attendanceDayProvider);
  return ref
      .read(attendanceAdminRepositoryProvider)
      .dailyReport(date: _iso(day));
});

/// The month containing the day in view.
final monthlyReportProvider =
    FutureProvider.autoDispose<MonthlyAttendanceReport>((ref) {
  final day = ref.watch(attendanceDayProvider);
  return ref
      .read(attendanceAdminRepositoryProvider)
      .monthlyReport(day.month, day.year);
});

/// Who was late and who did not turn up on the day in view.
final lateAndAbsentProvider =
    FutureProvider.autoDispose<({int lateCount, int absentCount})>((ref) {
  final day = ref.watch(attendanceDayProvider);
  return ref
      .read(attendanceAdminRepositoryProvider)
      .lateAndAbsent(date: _iso(day));
});

/// `yyyy-MM-dd`, which is what `@DateTimeFormat(ISO.DATE)` expects.
String _iso(DateTime day) => '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';
