/// Statuses the backend can put on a day. Kept as plain strings rather than a
/// Dart enum because the source of truth is the Java enum — a value that
/// arrives here and is not in this list must still render, not crash.
abstract final class AttendanceStatus {
  static const present = 'PRESENT';
  static const late = 'LATE';
  static const absent = 'ABSENT';
  static const onLeave = 'ON_LEAVE';
  static const halfDay = 'HALF_DAY';
  static const workFromHome = 'WORK_FROM_HOME';
  static const weekend = 'WEEKEND';
  static const holiday = 'HOLIDAY';
  static const partialDay = 'PARTIAL_DAY';
  static const unmarked = 'UNMARKED';

  /// The ones somebody would record by hand. WEEKEND, HOLIDAY, PARTIAL_DAY and
  /// UNMARKED are all set by the system rather than chosen, so offering them
  /// in a form would invite a record that contradicts the calendar.
  static const manuallySettable = [
    present,
    late,
    absent,
    onLeave,
    halfDay,
    workFromHome,
  ];
}

class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.attendanceDate,
    required this.status,
    this.checkInTime,
    this.checkOutTime,
    this.checkInLocation,
    this.checkOutLocation,
    this.shiftType,
    this.isLate = false,
    this.lateMinutes = 0,
    this.isOvertime = false,
    this.overtimeHours,
    this.leftEarly = false,
    this.earlyMinutes,
    this.totalWorkingHours,
    this.approved = false,
    this.notes,
  });

  final int id;
  final int employeeId;
  final String employeeName;
  final String attendanceDate;
  final String status;

  /// `HH:mm:ss` wall clock, not an instant.
  final String? checkInTime;
  final String? checkOutTime;

  final String? checkInLocation;
  final String? checkOutLocation;
  final String? shiftType;
  final bool isLate;
  final int lateMinutes;
  final bool isOvertime;
  final double? overtimeHours;
  final bool leftEarly;
  final int? earlyMinutes;
  final double? totalWorkingHours;
  final bool approved;
  final String? notes;

  bool get isCheckedIn => checkInTime != null && checkInTime!.isNotEmpty;
  bool get isCheckedOut => checkOutTime != null && checkOutTime!.isNotEmpty;

  /// True once the day is finished — both stamps present, nothing left to do.
  bool get isComplete => isCheckedIn && isCheckedOut;

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) =>
      AttendanceRecord(
        id: (json['id'] as num?)?.toInt() ?? 0,
        employeeId: (json['employeeId'] as num?)?.toInt() ?? 0,
        employeeName: json['employeeName'] as String? ?? '',
        attendanceDate: json['attendanceDate'] as String? ?? '',
        status: json['status'] as String? ?? AttendanceStatus.unmarked,
        checkInTime: json['checkInTime'] as String?,
        checkOutTime: json['checkOutTime'] as String?,
        checkInLocation: json['checkInLocation'] as String?,
        checkOutLocation: json['checkOutLocation'] as String?,
        shiftType: json['shiftType'] as String?,
        isLate: json['isLate'] as bool? ?? false,
        lateMinutes: (json['lateMinutes'] as num?)?.toInt() ?? 0,
        isOvertime: json['isOvertime'] as bool? ?? false,
        overtimeHours: (json['overtimeHours'] as num?)?.toDouble(),
        leftEarly: json['leftEarly'] as bool? ?? false,
        earlyMinutes: (json['earlyMinutes'] as num?)?.toInt(),
        totalWorkingHours: (json['totalWorkingHours'] as num?)?.toDouble(),
        approved: json['approved'] as bool? ?? false,
        notes: json['notes'] as String?,
      );

  AttendanceRecord mergedWith(AttendanceRecord other) => AttendanceRecord(
        id: id,
        employeeId: employeeId,
        employeeName: employeeName,
        attendanceDate: attendanceDate,
        // An ABSENT row that also has a real punch is the scheduler's
        // placeholder being superseded, so the real status wins.
        status: status == AttendanceStatus.absent &&
                other.status != AttendanceStatus.absent
            ? other.status
            : status,
        checkInTime: checkInTime ?? other.checkInTime,
        checkOutTime: checkOutTime ?? other.checkOutTime,
        checkInLocation: checkInLocation ?? other.checkInLocation,
        checkOutLocation: checkOutLocation ?? other.checkOutLocation,
        shiftType: shiftType ?? other.shiftType,
        isLate: isLate || other.isLate,
        lateMinutes: other.isLate ? other.lateMinutes : lateMinutes,
        isOvertime: isOvertime || other.isOvertime,
        overtimeHours: overtimeHours ?? other.overtimeHours,
        leftEarly: leftEarly || other.leftEarly,
        earlyMinutes: earlyMinutes ?? other.earlyMinutes,
        totalWorkingHours: totalWorkingHours ?? other.totalWorkingHours,
        approved: approved || other.approved,
        notes: notes ?? other.notes,
      );
}

class MonthlySummary {
  const MonthlySummary({
    required this.year,
    required this.month,
    this.presentDays = 0,
    this.absentDays = 0,
    this.halfDays = 0,
    this.onLeaveDays = 0,
    this.holidayDays = 0,
    this.weekOffDays = 0,
    this.workedHours = 0,
  });

  final int year;
  final int month;
  final int presentDays;
  final int absentDays;
  final int halfDays;
  final int onLeaveDays;
  final int holidayDays;
  final int weekOffDays;
  final double workedHours;

  /// Share of recorded working days attended, or null when the month has no
  /// recorded working days yet.
  ///
  /// Null rather than 0 on purpose: a fresh month with nothing in it is not
  /// 0% attendance, and showing that figure to someone would be a small lie
  /// about their record. The UI renders a dash instead.
  double? get attendancePercent {
    final attended = presentDays + halfDays;
    final working = attended + absentDays + onLeaveDays;
    if (working == 0) return null;
    return (attended / working * 1000).round() / 10;
  }

  factory MonthlySummary.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return MonthlySummary(
      year: (json['year'] as num?)?.toInt() ?? now.year,
      month: (json['month'] as num?)?.toInt() ?? now.month,
      presentDays: (json['presentDays'] as num?)?.toInt() ?? 0,
      absentDays: (json['absentDays'] as num?)?.toInt() ?? 0,
      halfDays: (json['halfDays'] as num?)?.toInt() ?? 0,
      onLeaveDays: (json['onLeaveDays'] as num?)?.toInt() ?? 0,
      holidayDays: (json['holidayDays'] as num?)?.toInt() ?? 0,
      weekOffDays: (json['weekOffDays'] as num?)?.toInt() ?? 0,
      workedHours: (json['workedHours'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Derived server-side from `submitted`/`approved` — see
/// `TimesheetMapper.toTimesheetResponse` — so the app never has to re-derive
/// the same combination itself.
abstract final class TimesheetStatus {
  static const notSubmitted = 'NOT_SUBMITTED';
  static const submitted = 'SUBMITTED';
  static const approved = 'APPROVED';
}

class Timesheet {
  const Timesheet({
    required this.id,
    required this.workDate,
    required this.status,
    this.hoursWorked = 0,
    this.billableHours = 0,
    this.projectName,
    this.description,
    this.approvedByName,
  });

  final int id;
  final String workDate;
  final String status;
  final double hoursWorked;
  final double billableHours;
  final String? projectName;
  final String? description;
  final String? approvedByName;

  /// Only a draft can still be changed or withdrawn — once submitted it is
  /// waiting on a decision, and once approved it is the record of what was
  /// paid.
  bool get isEditable => status == TimesheetStatus.notSubmitted;

  factory Timesheet.fromJson(Map<String, dynamic> json) => Timesheet(
        id: (json['id'] as num?)?.toInt() ?? 0,
        workDate: json['workDate'] as String? ?? '',
        status: json['status'] as String? ?? TimesheetStatus.notSubmitted,
        hoursWorked: (json['hoursWorked'] as num?)?.toDouble() ?? 0,
        billableHours: (json['billableHours'] as num?)?.toDouble() ?? 0,
        projectName: json['projectName'] as String?,
        description: json['description'] as String?,
        approvedByName: json['approvedByName'] as String?,
      );
}

/// The shift an employee is currently assigned to. Assigning, ending or
/// reassigning one is HR administration and stays on the web; this is the
/// read-only "what shift am I on" view a phone actually needs.
class ShiftAssignment {
  const ShiftAssignment({
    required this.shiftName,
    this.assignmentStartDate,
    this.assignmentEndDate,
    this.notes,
  });

  final String shiftName;
  final String? assignmentStartDate;
  final String? assignmentEndDate;
  final String? notes;

  factory ShiftAssignment.fromJson(Map<String, dynamic> json) =>
      ShiftAssignment(
        shiftName: json['shiftName'] as String? ?? 'Unnamed shift',
        assignmentStartDate: json['assignmentStartDate'] as String?,
        assignmentEndDate: json['assignmentEndDate'] as String?,
        notes: json['notes'] as String?,
      );
}

abstract final class AttendancePermissions {
  /// Putting somebody on a shift. Distinct from SHIFT_CREATE, which is about
  /// defining the shift itself — that stays on the web.
  static const shiftAssignmentCreate = 'SHIFT_ASSIGNMENT_CREATE';

  /// Reading the shift catalogue, which the assignment form needs to offer a
  /// choice at all.
  static const shiftView = 'SHIFT_VIEW';
}

/// A shift the company runs, as the assignment picker needs it.
///
/// Deliberately thin: the full `ShiftResponse` carries grace periods, weekly
/// off days and night-shift flags, none of which matter when the only question
/// is which shift to put somebody on.
class Shift {
  const Shift({
    required this.id,
    required this.name,
    this.startTime,
    this.endTime,
  });

  final int id;
  final String name;
  final String? startTime;
  final String? endTime;

  /// "09:00 – 17:30", or just the name when the times are missing.
  String get hoursLabel {
    if (startTime == null || endTime == null) return name;
    return '${_hhmm(startTime!)} – ${_hhmm(endTime!)}';
  }

  /// `LocalTime` serialises as `HH:mm:ss`; the seconds are never interesting.
  static String _hhmm(String time) =>
      time.length >= 5 ? time.substring(0, 5) : time;

  factory Shift.fromJson(Map<String, dynamic> json) => Shift(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? 'Unnamed shift',
        startTime: json['startTime'] as String?,
        endTime: json['endTime'] as String?,
      );
}

/// POST /hrm/attendance/shift-assignments
///
/// Employee and shift are `@NotNull` on a `@Valid` body; the dates and the
/// reason are optional. Leaving the end date empty is how an open-ended
/// assignment is expressed.
class ShiftAssignmentRequest {
  const ShiftAssignmentRequest({
    required this.employeeId,
    required this.shiftId,
    this.assignmentStartDate,
    this.assignmentEndDate,
    this.reason,
    this.notes,
  });

  final int employeeId;
  final int shiftId;
  final String? assignmentStartDate;
  final String? assignmentEndDate;
  final String? reason;
  final String? notes;

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'employeeId': employeeId,
      'shiftId': shiftId,
      if (assignmentStartDate != null)
        'assignmentStartDate': assignmentStartDate,
      if (assignmentEndDate != null) 'assignmentEndDate': assignmentEndDate,
      if (clean(reason) != null) 'reason': clean(reason),
      if (clean(notes) != null) 'notes': clean(notes),
    };
  }
}

/// Reading and correcting other people's attendance, not just your own.
abstract final class AttendanceAdminPermissions {
  static const view = 'ATTENDANCE_VIEW';

  /// Creating a record by hand. Not `ATTENDANCE_MANAGE` — the enum spells it
  /// as marking.
  static const mark = 'ATTENDANCE_MARK';

  static const update = 'ATTENDANCE_UPDATE';
  static const approve = 'ATTENDANCE_APPROVE';

  /// There is no separate report code; the reports read the same records.
  static const timesheetView = 'TIMESHEET_VIEW';
  static const timesheetApprove = 'TIMESHEET_APPROVE';
}

/// One day across the whole company.
class DailyAttendanceReport {
  const DailyAttendanceReport({
    required this.totalEmployees,
    required this.presentCount,
    required this.lateCount,
    required this.absentCount,
    required this.onLeaveCount,
    required this.attendancePercentage,
    this.reportDate,
  });

  final int totalEmployees;
  final int presentCount;
  final int lateCount;
  final int absentCount;
  final int onLeaveCount;

  /// The backend sends this as a whole number of percent, not a fraction.
  final double attendancePercentage;

  final String? reportDate;

  /// Everybody the day has not accounted for. A non-zero figure usually means
  /// the nightly absentee marker has not run yet, which is what the backfill
  /// is for.
  int get unaccounted {
    final counted = presentCount + lateCount + absentCount + onLeaveCount;
    return totalEmployees > counted ? totalEmployees - counted : 0;
  }

  factory DailyAttendanceReport.fromJson(Map<String, dynamic> json) =>
      DailyAttendanceReport(
        totalEmployees: (json['totalEmployees'] as num?)?.toInt() ?? 0,
        presentCount: (json['presentCount'] as num?)?.toInt() ?? 0,
        lateCount: (json['lateCount'] as num?)?.toInt() ?? 0,
        absentCount: (json['absentCount'] as num?)?.toInt() ?? 0,
        onLeaveCount: (json['onLeaveCount'] as num?)?.toInt() ?? 0,
        attendancePercentage:
            (json['attendancePercentage'] as num?)?.toDouble() ?? 0,
        reportDate: json['reportDate'] as String?,
      );
}

/// One month across the whole company.
class MonthlyAttendanceReport {
  const MonthlyAttendanceReport({
    required this.month,
    required this.year,
    required this.totalWorkingDays,
    required this.presentCount,
    required this.lateCount,
    required this.absentCount,
    required this.attendancePercentage,
  });

  final int month;
  final int year;
  final int totalWorkingDays;
  final int presentCount;
  final int lateCount;
  final int absentCount;
  final double attendancePercentage;

  factory MonthlyAttendanceReport.fromJson(Map<String, dynamic> json) =>
      MonthlyAttendanceReport(
        month: (json['month'] as num?)?.toInt() ?? 1,
        year: (json['year'] as num?)?.toInt() ?? 0,
        totalWorkingDays: (json['totalWorkingDays'] as num?)?.toInt() ?? 0,
        presentCount: (json['presentCount'] as num?)?.toInt() ?? 0,
        lateCount: (json['lateCount'] as num?)?.toInt() ?? 0,
        absentCount: (json['absentCount'] as num?)?.toInt() ?? 0,
        attendancePercentage:
            (json['attendancePercentage'] as num?)?.toDouble() ?? 0,
      );
}

/// One person over a period.
class EmployeeAttendanceSummary {
  const EmployeeAttendanceSummary({
    required this.presentDays,
    required this.lateDays,
    required this.absentDays,
    required this.attendancePercentage,
    this.employeeId,
    this.periodStart,
    this.periodEnd,
  });

  final int presentDays;
  final int lateDays;
  final int absentDays;
  final double attendancePercentage;
  final int? employeeId;
  final String? periodStart;
  final String? periodEnd;

  factory EmployeeAttendanceSummary.fromJson(Map<String, dynamic> json) =>
      EmployeeAttendanceSummary(
        presentDays: (json['presentDays'] as num?)?.toInt() ?? 0,
        lateDays: (json['lateDays'] as num?)?.toInt() ?? 0,
        absentDays: (json['absentDays'] as num?)?.toInt() ?? 0,
        attendancePercentage:
            (json['attendancePercentage'] as num?)?.toDouble() ?? 0,
        employeeId: (json['employeeId'] as num?)?.toInt(),
        periodStart: json['periodStart'] as String?,
        periodEnd: json['periodEnd'] as String?,
      );
}

/// POST /company/attendance/manual
///
/// An HR correction: somebody forgot to check in, the terminal was down, a day
/// needs marking as leave after the fact.
///
/// Employee, date and status are `@NotNull`. `isLate`, `lateMinutes` and
/// `isOvertime` are primitives on the DTO, so they always go — the form works
/// out lateness from the times rather than asking, because a human guessing at
/// "was this late" against a shift they cannot see is worse than a calculation.
class ManualAttendanceRequest {
  const ManualAttendanceRequest({
    required this.employeeId,
    required this.attendanceDate,
    required this.status,
    this.checkInTime,
    this.checkOutTime,
    this.checkInMethod = 'MANUAL',
    this.checkOutMethod = 'MANUAL',
    this.isLate = false,
    this.lateMinutes = 0,
    this.lateReason,
    this.isOvertime = false,
    this.notes,
  });

  final int employeeId;

  /// `yyyy-MM-dd`.
  final String attendanceDate;

  final String status;

  /// `HH:mm:ss` — `LocalTime` wants the seconds.
  final String? checkInTime;
  final String? checkOutTime;

  final String checkInMethod;
  final String checkOutMethod;
  final bool isLate;
  final int lateMinutes;
  final String? lateReason;
  final bool isOvertime;
  final String? notes;

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'employeeId': employeeId,
      'attendanceDate': attendanceDate,
      'status': status,
      // Primitives on the DTO: always present.
      'isLate': isLate,
      'lateMinutes': lateMinutes,
      'isOvertime': isOvertime,
      if (checkInTime != null) ...{
        'checkInTime': checkInTime,
        'checkInMethod': checkInMethod,
      },
      if (checkOutTime != null) ...{
        'checkOutTime': checkOutTime,
        'checkOutMethod': checkOutMethod,
      },
      if (clean(lateReason) != null) 'lateReason': clean(lateReason),
      if (clean(notes) != null) 'notes': clean(notes),
    };
  }
}
