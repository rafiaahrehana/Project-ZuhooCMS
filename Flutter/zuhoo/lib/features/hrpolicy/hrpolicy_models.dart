/// The standing HR rules: which days are off, what leave people get, what
/// hours they work, and the letters that record all of it.
abstract final class HrPolicyPermissions {
  static const holidayView = 'HOLIDAY_VIEW';
  static const holidayCreate = 'HOLIDAY_CREATE';
  static const holidayUpdate = 'HOLIDAY_UPDATE';
  static const holidayDelete = 'HOLIDAY_DELETE';

  static const policyView = 'LEAVE_POLICY_VIEW';
  static const policyCreate = 'LEAVE_POLICY_CREATE';
  static const policyUpdate = 'LEAVE_POLICY_UPDATE';
  static const policyDelete = 'LEAVE_POLICY_DELETE';

  static const shiftView = 'SHIFT_VIEW';
  static const shiftCreate = 'SHIFT_CREATE';
  static const shiftUpdate = 'SHIFT_UPDATE';
  static const shiftDelete = 'SHIFT_DELETE';

  static const letterView = 'LETTER_VIEW';
  static const letterCreate = 'LETTER_CREATE';

  /// Issuing a letter is an update, not its own code.
  static const letterUpdate = 'LETTER_UPDATE';

  static const letterDelete = 'LETTER_DELETE';
}

/// Mirrors `HolidayType`.
const holidayTypes = <String>['NATIONAL', 'RELIGIOUS', 'OPTIONAL', 'COMPANY'];

/// Mirrors `ShiftType`.
const shiftTypes = <String>[
  'MORNING',
  'AFTERNOON',
  'EVENING',
  'NIGHT',
  'FULL_DAY',
  'FLEXIBLE',
];

/// Mirrors `LetterType`. Ordered roughly by when in someone's time at the
/// company each is written, which is how somebody looking for one thinks.
const letterTypes = <String>[
  'OFFER',
  'APPOINTMENT',
  'CONFIRMATION',
  'PROMOTION',
  'TRANSFER',
  'SALARY_CERTIFICATE',
  'NOC',
  'APPRECIATION',
  'WARNING',
  'EXPERIENCE',
  'RESIGNATION_ACCEPTANCE',
  'TERMINATION',
];

/// A day the company is closed.
class Holiday {
  const Holiday({
    required this.id,
    required this.name,
    required this.holidayType,
    this.holidayDate,
    this.description,
  });

  final int id;
  final String name;
  final String holidayType;
  final String? holidayDate;
  final String? description;

  /// Optional holidays are the ones people may or may not take, so they are
  /// worth distinguishing from a day the office is simply shut.
  bool get isOptional => holidayType == 'OPTIONAL';

  factory Holiday.fromJson(Map<String, dynamic> json) => Holiday(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        holidayType: json['holidayType'] as String? ?? 'COMPANY',
        holidayDate: json['holidayDate'] as String?,
        description: json['description'] as String?,
      );
}

/// POST and PUT /hr/holidays
///
/// Name, date and type are all required — the name is capped at 150. The
/// update assigns all three unconditionally and null-guards only the
/// description, so everything but the description goes every time.
class HolidayRequest {
  const HolidayRequest({
    required this.name,
    required this.holidayDate,
    required this.holidayType,
    this.description,
  });

  final String name;

  /// `yyyy-MM-dd`.
  final String holidayDate;

  final String holidayType;
  final String? description;

  Map<String, dynamic> toJson() {
    final trimmed = description?.trim();
    return {
      'name': name.trim(),
      'holidayDate': holidayDate,
      'holidayType': holidayType,
      if (trimmed != null && trimmed.isNotEmpty) 'description': trimmed,
    };
  }
}

/// What one kind of leave is worth, for one kind of employee.
class LeavePolicy {
  const LeavePolicy({
    required this.id,
    required this.leaveType,
    required this.annualEntitlement,
    required this.maxCarryForward,
    required this.requiresApproval,
    required this.canCarryForward,
    required this.paid,
    required this.applicableFromMonths,
    required this.active,
    this.employmentType,
    this.maxConsecutiveDays,
  });

  final int id;
  final String leaveType;
  final int annualEntitlement;
  final int maxCarryForward;
  final bool requiresApproval;
  final bool canCarryForward;
  final bool paid;

  /// How long somebody must have been employed before it applies. Zero means
  /// from day one.
  final int applicableFromMonths;

  final bool active;

  /// Null when the policy applies to everybody regardless of contract.
  final String? employmentType;

  final int? maxConsecutiveDays;

  /// Reads as a sentence for the row's subtitle.
  String get terms {
    final parts = <String>[
      '$annualEntitlement days a year',
      if (!paid) 'unpaid',
      if (canCarryForward && maxCarryForward > 0)
        'carry $maxCarryForward over'
      else
        'no carry-over',
      if (maxConsecutiveDays != null) 'max $maxConsecutiveDays at a time',
      if (applicableFromMonths > 0) 'after $applicableFromMonths months',
    ];
    return parts.join(' · ');
  }

  factory LeavePolicy.fromJson(Map<String, dynamic> json) => LeavePolicy(
        id: (json['id'] as num?)?.toInt() ?? 0,
        leaveType: json['leaveType'] as String? ?? '',
        annualEntitlement: (json['annualEntitlement'] as num?)?.toInt() ?? 0,
        maxCarryForward: (json['maxCarryForward'] as num?)?.toInt() ?? 0,
        requiresApproval: json['requiresApproval'] as bool? ?? true,
        canCarryForward: json['canCarryForward'] as bool? ?? false,
        paid: json['paid'] as bool? ?? true,
        applicableFromMonths:
            (json['applicableFromMonths'] as num?)?.toInt() ?? 0,
        active: json['active'] as bool? ?? true,
        employmentType: json['employmentType'] as String?,
        maxConsecutiveDays: (json['maxConsecutiveDays'] as num?)?.toInt(),
      );
}

/// POST and PUT /hr/leave-policies
///
/// The three flags — `requiresApproval`, `canCarryForward` and `paid` — are
/// primitive booleans assigned **unconditionally**, so an omitted one arrives
/// as false. Leaving out `paid` would silently make a leave type unpaid, which
/// is why all three go every time.
///
/// `leaveType` and `annualEntitlement` are `@NotNull`, and the entitlement is
/// `@Min(0)` — zero days is allowed, and means the type exists but grants
/// nothing.
class LeavePolicyRequest {
  const LeavePolicyRequest({
    required this.leaveType,
    required this.annualEntitlement,
    required this.requiresApproval,
    required this.canCarryForward,
    required this.paid,
    this.employmentType,
    this.maxCarryForward,
    this.maxConsecutiveDays,
    this.applicableFromMonths,
  });

  final String leaveType;
  final int annualEntitlement;
  final bool requiresApproval;
  final bool canCarryForward;
  final bool paid;
  final String? employmentType;
  final int? maxCarryForward;
  final int? maxConsecutiveDays;
  final int? applicableFromMonths;

  factory LeavePolicyRequest.from(LeavePolicy policy) => LeavePolicyRequest(
        leaveType: policy.leaveType,
        annualEntitlement: policy.annualEntitlement,
        requiresApproval: policy.requiresApproval,
        canCarryForward: policy.canCarryForward,
        paid: policy.paid,
        employmentType: policy.employmentType,
        maxCarryForward: policy.maxCarryForward,
        maxConsecutiveDays: policy.maxConsecutiveDays,
        applicableFromMonths: policy.applicableFromMonths,
      );

  Map<String, dynamic> toJson() => {
        'leaveType': leaveType,
        'annualEntitlement': annualEntitlement,
        // All three, always: see the class comment.
        'requiresApproval': requiresApproval,
        'canCarryForward': canCarryForward,
        'paid': paid,
        if (employmentType != null) 'employmentType': employmentType,
        if (maxCarryForward != null) 'maxCarryForward': maxCarryForward,
        if (maxConsecutiveDays != null)
          'maxConsecutiveDays': maxConsecutiveDays,
        if (applicableFromMonths != null)
          'applicableFromMonths': applicableFromMonths,
      };
}

/// A working pattern people are assigned to.
class Shift {
  const Shift({
    required this.id,
    required this.name,
    required this.shiftType,
    required this.gracePeriodMinutes,
    required this.flexible,
    required this.nightShift,
    required this.active,
    required this.workingMinutes,
    this.startTime,
    this.endTime,
    this.weeklyOffDays,
    this.description,
    this.notes,
  });

  final int id;
  final String name;
  final String shiftType;
  final int gracePeriodMinutes;
  final bool flexible;
  final bool nightShift;
  final bool active;

  /// Worked out server-side from the start and end times. A night shift that
  /// crosses midnight comes back negative, which the display accounts for.
  final int workingMinutes;

  /// `HH:mm:ss` as the backend sends it.
  final String? startTime;
  final String? endTime;

  /// A comma-separated list of day names, as stored.
  final String? weeklyOffDays;

  final String? description;
  final String? notes;

  /// The hours, allowing for a shift that runs past midnight — the backend
  /// subtracts the times directly, so an overnight shift arrives negative.
  double get hours {
    final minutes =
        workingMinutes < 0 ? workingMinutes + (24 * 60) : workingMinutes;
    return minutes / 60;
  }

  /// "09:00 — 17:30", from whatever precision the backend sent.
  String get window {
    String short(String? time) {
      if (time == null || time.length < 5) return '';
      return time.substring(0, 5);
    }

    final from = short(startTime);
    final to = short(endTime);
    if (from.isEmpty || to.isEmpty) return 'No hours set';
    return '$from — $to';
  }

  factory Shift.fromJson(Map<String, dynamic> json) => Shift(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        shiftType: json['shiftType'] as String? ?? 'FULL_DAY',
        gracePeriodMinutes: (json['gracePeriodMinutes'] as num?)?.toInt() ?? 0,
        flexible: json['flexible'] as bool? ?? false,
        nightShift: json['nightShift'] as bool? ?? false,
        active: json['active'] as bool? ?? true,
        workingMinutes: (json['workingMinutes'] as num?)?.toInt() ?? 0,
        startTime: json['startTime'] as String?,
        endTime: json['endTime'] as String?,
        weeklyOffDays: json['weeklyOffDays'] as String?,
        description: json['description'] as String?,
        notes: json['notes'] as String?,
      );
}

/// POST and PUT /hr/shifts
///
/// Name, type and both times are required. The update assigns name, type,
/// times, both flags, the description and the notes **unconditionally**, and
/// null-guards only the grace period and the weekly off days — so everything
/// else goes on every save.
class ShiftRequest {
  const ShiftRequest({
    required this.name,
    required this.shiftType,
    required this.startTime,
    required this.endTime,
    required this.flexible,
    required this.nightShift,
    this.gracePeriodMinutes,
    this.weeklyOffDays,
    this.description,
    this.notes,
  });

  final String name;
  final String shiftType;

  /// `HH:mm:ss` — the backend parses a `LocalTime`, which wants seconds.
  final String startTime;
  final String endTime;

  final bool flexible;
  final bool nightShift;
  final int? gracePeriodMinutes;
  final String? weeklyOffDays;
  final String? description;
  final String? notes;

  factory ShiftRequest.from(Shift shift) => ShiftRequest(
        name: shift.name,
        shiftType: shift.shiftType,
        startTime: shift.startTime ?? '09:00:00',
        endTime: shift.endTime ?? '17:00:00',
        flexible: shift.flexible,
        nightShift: shift.nightShift,
        gracePeriodMinutes: shift.gracePeriodMinutes,
        weeklyOffDays: shift.weeklyOffDays,
        description: shift.description,
        notes: shift.notes,
      );

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'name': name.trim(),
      'shiftType': shiftType,
      'startTime': startTime,
      'endTime': endTime,
      // Primitives on the DTO, assigned without a guard.
      'flexible': flexible,
      'nightShift': nightShift,
      'description': clean(description),
      'notes': clean(notes),
      if (gracePeriodMinutes != null)
        'gracePeriodMinutes': gracePeriodMinutes,
      if (clean(weeklyOffDays) != null) 'weeklyOffDays': clean(weeklyOffDays),
    };
  }
}

/// A letter written about somebody — an offer, a confirmation, a warning.
class HrLetter {
  const HrLetter({
    required this.id,
    required this.letterType,
    required this.issued,
    this.referenceNumber,
    this.issueDate,
    this.content,
    this.signedBy,
    this.fileUrl,
    this.employeeId,
    this.employeeName,
    this.recipientName,
    this.createdByName,
  });

  final int id;
  final String letterType;

  /// A letter is drafted first and issued afterwards. Issuing is one way.
  final bool issued;

  final String? referenceNumber;
  final String? issueDate;
  final String? content;
  final String? signedBy;
  final String? fileUrl;
  final int? employeeId;
  final String? employeeName;
  final String? recipientName;
  final String? createdByName;

  /// Whoever it is about, whether they are on the payroll yet or not — an
  /// offer letter goes to a candidate, not an employee.
  String get about => employeeName ?? recipientName ?? 'Unnamed';

  factory HrLetter.fromJson(Map<String, dynamic> json) => HrLetter(
        id: (json['id'] as num?)?.toInt() ?? 0,
        letterType: json['letterType'] as String? ?? 'OFFER',
        issued: json['issued'] as bool? ?? false,
        referenceNumber: json['referenceNumber'] as String?,
        issueDate: json['issueDate'] as String?,
        content: json['content'] as String?,
        signedBy: json['signedBy'] as String?,
        fileUrl: json['fileUrl'] as String?,
        employeeId: (json['employeeId'] as num?)?.toInt(),
        employeeName: json['employeeName'] as String?,
        recipientName: json['recipientName'] as String?,
        createdByName: json['createdByName'] as String?,
      );
}

/// POST /hr/letters
///
/// The type, the issue date and the content are required; the content is
/// `@NotBlank`, so a letter with nothing in it is refused.
///
/// It is about **either** an employee or a job application — an offer letter
/// goes to somebody who is not on the payroll yet. Neither is individually
/// required, which is how one DTO serves both.
///
/// There is no update endpoint: a letter is a document, and correcting one
/// means writing another.
class HrLetterRequest {
  const HrLetterRequest({
    required this.letterType,
    required this.issueDate,
    required this.content,
    this.employeeId,
    this.jobApplicationId,
    this.referenceNumber,
    this.signedBy,
  });

  final String letterType;

  /// `yyyy-MM-dd`.
  final String issueDate;

  final String content;
  final int? employeeId;
  final int? jobApplicationId;
  final String? referenceNumber;
  final String? signedBy;

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'letterType': letterType,
      'issueDate': issueDate,
      'content': content.trim(),
      if (employeeId != null) 'employeeId': employeeId,
      if (jobApplicationId != null) 'jobApplicationId': jobApplicationId,
      if (clean(referenceNumber) != null)
        'referenceNumber': clean(referenceNumber),
      if (clean(signedBy) != null) 'signedBy': clean(signedBy),
    };
  }
}
