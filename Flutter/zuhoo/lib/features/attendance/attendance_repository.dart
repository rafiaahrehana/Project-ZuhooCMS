import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import '../../shared/util/formatters.dart';
import 'attendance_models.dart';

class AttendanceRepository {
  AttendanceRepository(this._api);

  final ApiClient _api;

  static const _base = '/company/attendance';

  /// Today's record, or null when the day has not been opened yet.
  ///
  /// "Nothing yet" is the normal morning state for every employee who has not
  /// punched in, and the backend expresses it as `ResponseEntity.ok(null)` —
  /// a **200 with an empty body**, not a 404. Depending on the transformer
  /// that reaches Dio as either a null or an empty string, so both are read as
  /// "no record" rather than being allowed to fail a cast and surface as a
  /// mystery error on the check-in screen every morning.
  ///
  /// The status codes are still caught underneath, because the same endpoint
  /// 403s for a user with no employee record — also not an error worth showing.
  /// A genuine network failure still propagates: that is a different thing and
  /// the user should see it.
  Future<AttendanceRecord?> myToday() async {
    try {
      final data = await _api.get<dynamic>('$_base/my/today');
      if (data is! Map<String, dynamic> || data.isEmpty) return null;
      return AttendanceRecord.fromJson(data);
    } on ApiException catch (e) {
      if (e.isNotFound || e.isForbidden || e.statusCode == 204) return null;
      rethrow;
    }
  }

  Future<PagedResponse<AttendanceRecord>> myRecords({
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        '$_base/my',
        AttendanceRecord.fromJson,
        page: page,
        size: size,
      );

  Future<MonthlySummary> myMonthlySummary({int? year, int? month}) async {
    final json = await _api.get<Map<String, dynamic>>(
      '$_base/my/monthly-summary',
      query: {'year': year, 'month': month},
    );
    return MonthlySummary.fromJson(json);
  }

  /// Opens today.
  ///
  /// `checkInTime` is the **local wall clock**, formatted `HH:mm:ss` — not an
  /// ISO instant and not UTC. The backend compares it against the assigned
  /// shift's start time, which is itself a local wall clock, so sending an
  /// instant would make everyone in a non-UTC timezone permanently late.
  Future<AttendanceRecord> checkIn({String? notes, String? location}) async {
    final json = await _api.post<Map<String, dynamic>>('$_base/check-in', {
      'checkInTime': Fmt.wallClockNow(),
      'method': 'MANUAL',
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (location != null && location.trim().isNotEmpty)
        'location': location.trim(),
    });
    return AttendanceRecord.fromJson(json);
  }

  Future<AttendanceRecord> checkOut(int id, {String? location}) async {
    final json = await _api.post<Map<String, dynamic>>('$_base/$id/check-out', {
      'checkOutTime': Fmt.wallClockNow(),
      'method': 'MANUAL',
      if (location != null && location.trim().isNotEmpty)
        'location': location.trim(),
    });
    return AttendanceRecord.fromJson(json);
  }

  // ── Timesheets ──────────────────────────────────────────────
  // Self-service only. Approving someone else's is left to the web: unlike
  // leave, there is no "pending review" listing across the team — only
  // per-employee lookups — so acting on it from a phone would mean picking an
  // employee blind rather than working from an inbox.

  static const _timesheets = '/hr/timesheets';

  Future<PagedResponse<Timesheet>> myTimesheets({int page = 0, int size = 31}) =>
      _api.getPaged(
        '$_timesheets/my',
        Timesheet.fromJson,
        page: page,
        size: size,
      );

  Future<Timesheet> logTimesheet({
    required DateTime workDate,
    required double hoursWorked,
    double? billableHours,
    String? projectName,
    String? description,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(_timesheets, {
      'workDate': Fmt.isoDate(workDate),
      'hoursWorked': hoursWorked,
      'billableHours': ?billableHours,
      if (projectName != null && projectName.trim().isNotEmpty)
        'projectName': projectName.trim(),
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
    });
    return Timesheet.fromJson(json);
  }

  /// Corrects an entry that has not been sent for review yet.
  ///
  /// The backend refuses once it is submitted or approved — `Timesheet.isEditable`
  /// is the same rule, which is what the UI gates on.
  ///
  /// `workDate` and `hoursWorked` are `@NotNull` on a `@Valid` body, so both go
  /// every time. The rest is a sparse patch: an emptied project or description
  /// is *not* cleared, because the service only assigns non-null values. The
  /// form says so rather than appearing to allow it.
  Future<Timesheet> updateTimesheet(
    int id, {
    required DateTime workDate,
    required double hoursWorked,
    double? billableHours,
    String? projectName,
    String? description,
  }) async {
    final json = await _api.patch<Map<String, dynamic>>('$_timesheets/$id', {
      'workDate': Fmt.isoDate(workDate),
      'hoursWorked': hoursWorked,
      'billableHours': ?billableHours,
      if (projectName != null && projectName.trim().isNotEmpty)
        'projectName': projectName.trim(),
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
    });
    return Timesheet.fromJson(json);
  }

  Future<void> deleteTimesheet(int id) =>
      _api.deleteText('$_timesheets/$id');

  /// Submits every not-yet-submitted, not-yet-approved entry at once — the
  /// backend has no per-entry submit, only this batch. Returns how many moved.
  Future<int> submitTimesheetsForReview() async {
    final json =
        await _api.post<Map<String, dynamic>>('$_timesheets/submit', const {});
    return (json['submitted'] as num?)?.toInt() ?? 0;
  }

  // ── Shift assignment ────────────────────────────────────────
  // Read-only: assigning, ending or reassigning a shift is HR administration
  // and stays on the web.

  static const _shiftAssignments = '/hrm/attendance/shift-assignments';

  /// The shifts the company runs, for the assignment picker.
  ///
  /// `/hr/shifts/active` rather than the paginated list: putting somebody on a
  /// retired shift is not a thing anyone means to do, and the active list comes
  /// back whole rather than a page at a time.
  Future<List<Shift>> activeShifts() async {
    final list = await _api.get<List<dynamic>>('/hr/shifts/active');
    return list
        .whereType<Map<String, dynamic>>()
        .map(Shift.fromJson)
        .toList(growable: false);
  }

  /// Puts somebody on a shift.
  Future<ShiftAssignment> assignShift(ShiftAssignmentRequest request) async {
    final json = await _api.post<Map<String, dynamic>>(
      _shiftAssignments,
      request.toJson(),
    );
    return ShiftAssignment.fromJson(json);
  }

  /// The employee's current assignment, or null when they have none — a
  /// perfectly normal state for anyone HR has not put on a shift yet.
  Future<ShiftAssignment?> shiftAssignmentFor(int employeeId) async {
    try {
      final json = await _api
          .get<Map<String, dynamic>>('$_shiftAssignments/employee/$employeeId');
      return ShiftAssignment.fromJson(json);
    } on ApiException catch (e) {
      if (e.isNotFound) return null;
      rethrow;
    }
  }
}

final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => AttendanceRepository(ref.watch(apiClientProvider)),
);
