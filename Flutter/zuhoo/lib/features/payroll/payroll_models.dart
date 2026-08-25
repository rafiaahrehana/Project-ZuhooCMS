/// Running payroll: the monthly run, what it totals, and the rules it follows.
///
/// The employee-facing side of payroll — a person's own payslips — already
/// lives in the payslips module. This is the administrator's side: the run that
/// produces those payslips, and the settings that decide how the figures are
/// worked out.

/// Where a payroll run stands. Mirrors `PayrollRun.RunStatus`.
///
/// The order here is the order it moves through, which is what the screen uses
/// to draw progress.
abstract final class RunStatus {
  static const draft = 'DRAFT';
  static const calculated = 'CALCULATED';
  static const pendingApproval = 'PENDING_APPROVAL';
  static const approved = 'APPROVED';
  static const paid = 'PAID';
  static const rejected = 'REJECTED';
  static const cancelled = 'CANCELLED';

  /// Nothing more happens to a run in one of these.
  static const settled = {paid, cancelled};

  /// Which statuses each action is allowed from. Copied exactly from
  /// `PayrollRunService.requireStatus` — the backend refuses anything else with
  /// "Cannot <action> a <status> payroll run", so the screen offers only what
  /// will work rather than letting somebody find out.
  static const recalculateFrom = {draft, calculated, pendingApproval, rejected};
  static const submitFrom = {draft, calculated, rejected};
  static const approveFrom = {pendingApproval, calculated};
  static const rejectFrom = {pendingApproval};
  static const cancelFrom = {draft, calculated, pendingApproval, rejected};
  static const payFrom = {approved};
}

/// How a day's pay is derived from a monthly salary. Mirrors `PerDayBasis`.
///
/// There is no universally right answer — it is company policy — so each is
/// labelled with what it actually does rather than left as an enum name.
const perDayBases = <({String value, String label, String hint})>[
  (
    value: 'CALENDAR_DAYS',
    label: 'Calendar days',
    hint: 'Divide by the days in that month, so absence costs more in February',
  ),
  (
    value: 'FIXED_30',
    label: 'Fixed 30 days',
    hint: 'Identical every month',
  ),
  (
    value: 'FIXED_26',
    label: 'Fixed 26 days',
    hint: 'A manufacturing convention — deductions bite harder',
  ),
  (
    value: 'ACTUAL_WORKING_DAYS',
    label: 'Actual working days',
    hint: 'Excludes weekly offs and holidays; the divisor moves each month',
  ),
];

/// What a percentage or deduction is calculated on. Mirrors `SalaryBase`.
const salaryBases = <String>['BASIC', 'GROSS'];

/// One month's payroll run for the whole company.
class PayrollRun {
  const PayrollRun({
    required this.id,
    required this.runNumber,
    required this.payMonth,
    required this.payYear,
    required this.status,
    required this.totalEmployees,
    required this.totalGross,
    required this.totalDeduction,
    required this.totalNet,
    this.payPeriodStart,
    this.payPeriodEnd,
    this.paymentDate,
    this.remarks,
    this.rejectionReason,
    this.approvedAt,
  });

  final int id;
  final String runNumber;
  final int payMonth;
  final int payYear;
  final String status;
  final int totalEmployees;
  final double totalGross;
  final double totalDeduction;
  final double totalNet;
  final String? payPeriodStart;
  final String? payPeriodEnd;
  final String? paymentDate;
  final String? remarks;
  final String? rejectionReason;
  final String? approvedAt;

  bool get isSettled => RunStatus.settled.contains(status);

  /// A run with no lines cannot be submitted — the backend says so with "Run
  /// has no payroll lines - recalculate first", so the screen says it first.
  bool get hasLines => totalEmployees > 0;

  bool can(Set<String> from) => from.contains(status);

  factory PayrollRun.fromJson(Map<String, dynamic> json) => PayrollRun(
        id: (json['id'] as num?)?.toInt() ?? 0,
        runNumber: json['runNumber'] as String? ?? '',
        payMonth: (json['payMonth'] as num?)?.toInt() ?? 1,
        payYear: (json['payYear'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? RunStatus.draft,
        totalEmployees: (json['totalEmployees'] as num?)?.toInt() ?? 0,
        totalGross: (json['totalGross'] as num?)?.toDouble() ?? 0,
        totalDeduction: (json['totalDeduction'] as num?)?.toDouble() ?? 0,
        totalNet: (json['totalNet'] as num?)?.toDouble() ?? 0,
        payPeriodStart: json['payPeriodStart'] as String?,
        payPeriodEnd: json['payPeriodEnd'] as String?,
        paymentDate: json['paymentDate'] as String?,
        remarks: json['remarks'] as String?,
        rejectionReason: json['rejectionReason'] as String?,
        approvedAt: json['approvedAt'] as String?,
      );
}

/// GET /hr/payroll-dashboard
///
/// One month at a glance, plus a short trend. Every figure can legitimately be
/// zero — a month before payroll is run has no lines at all — so nothing here
/// treats zero as missing.
class PayrollDashboard {
  const PayrollDashboard({
    required this.month,
    required this.year,
    required this.totalEmployees,
    required this.payrollCount,
    required this.employeesPaid,
    required this.pendingCount,
    required this.totalGross,
    required this.totalNet,
    required this.totalDeductions,
    this.runStatus,
    this.runNumber,
    this.nextPayDate,
    this.trend = const [],
  });

  final int month;
  final int year;
  final int totalEmployees;
  final int payrollCount;
  final int employeesPaid;
  final int pendingCount;
  final double totalGross;
  final double totalNet;
  final double totalDeductions;
  final String? runStatus;
  final String? runNumber;
  final String? nextPayDate;
  final List<PayrollTrendPoint> trend;

  /// How far through the month's payroll is, or null when there is nothing to
  /// pay — an empty bar would read as "none paid" rather than "nothing due".
  double? get paidShare {
    if (payrollCount <= 0) return null;
    return (employeesPaid / payrollCount).clamp(0.0, 1.0);
  }

  /// People with no payroll line this month at all. Distinct from pending,
  /// which is a line that exists and has not been paid.
  int get missing =>
      totalEmployees > payrollCount ? totalEmployees - payrollCount : 0;

  factory PayrollDashboard.fromJson(Map<String, dynamic> json) =>
      PayrollDashboard(
        month: (json['month'] as num?)?.toInt() ?? 1,
        year: (json['year'] as num?)?.toInt() ?? 0,
        totalEmployees: (json['totalEmployees'] as num?)?.toInt() ?? 0,
        payrollCount: (json['payrollCount'] as num?)?.toInt() ?? 0,
        employeesPaid: (json['employeesPaid'] as num?)?.toInt() ?? 0,
        pendingCount: (json['pendingCount'] as num?)?.toInt() ?? 0,
        totalGross: (json['totalGross'] as num?)?.toDouble() ?? 0,
        totalNet: (json['totalNet'] as num?)?.toDouble() ?? 0,
        totalDeductions: (json['totalDeductions'] as num?)?.toDouble() ?? 0,
        runStatus: json['runStatus'] as String?,
        runNumber: json['runNumber'] as String?,
        nextPayDate: json['nextPayDate'] as String?,
        trend: [
          for (final point in (json['trend'] as List? ?? const []))
            if (point is Map<String, dynamic>) PayrollTrendPoint.fromJson(point),
        ],
      );
}

class PayrollTrendPoint {
  const PayrollTrendPoint({
    required this.month,
    required this.year,
    required this.netPaid,
  });

  final int month;
  final int year;
  final double netPaid;

  factory PayrollTrendPoint.fromJson(Map<String, dynamic> json) =>
      PayrollTrendPoint(
        month: (json['month'] as num?)?.toInt() ?? 1,
        year: (json['year'] as num?)?.toInt() ?? 0,
        netPaid: (json['netPaid'] as num?)?.toDouble() ?? 0,
      );
}

/// The rules payroll follows when it works the figures out.
class PayrollSettings {
  const PayrollSettings({
    required this.perDayBasis,
    required this.absenceDeductionBase,
    required this.overtimeEnabled,
    required this.overtimeMultiplier,
    required this.overtimeBase,
    required this.standardHoursPerDay,
    required this.houseRentPercent,
    required this.medicalPercent,
    required this.transportPercent,
    required this.foodPercent,
    required this.providentFundPercent,
    required this.taxPercent,
  });

  final String perDayBasis;
  final String absenceDeductionBase;
  final bool overtimeEnabled;
  final double overtimeMultiplier;
  final String overtimeBase;
  final double standardHoursPerDay;
  final double houseRentPercent;
  final double medicalPercent;
  final double transportPercent;
  final double foodPercent;
  final double providentFundPercent;
  final double taxPercent;

  /// The allowances are shares of the basic salary and are meant to sit under
  /// a hundred between them. The backend does not check the total, so the form
  /// warns rather than refuses.
  double get allowanceTotal =>
      houseRentPercent + medicalPercent + transportPercent + foodPercent;

  factory PayrollSettings.fromJson(Map<String, dynamic> json) {
    double num_(String key, double fallback) =>
        (json[key] as num?)?.toDouble() ?? fallback;
    return PayrollSettings(
      perDayBasis: json['perDayBasis'] as String? ?? 'CALENDAR_DAYS',
      absenceDeductionBase: json['absenceDeductionBase'] as String? ?? 'GROSS',
      overtimeEnabled: json['overtimeEnabled'] as bool? ?? false,
      overtimeMultiplier: num_('overtimeMultiplier', 2),
      overtimeBase: json['overtimeBase'] as String? ?? 'BASIC',
      standardHoursPerDay: num_('standardHoursPerDay', 8),
      houseRentPercent: num_('houseRentPercent', 40),
      medicalPercent: num_('medicalPercent', 10),
      transportPercent: num_('transportPercent', 10),
      foodPercent: num_('foodPercent', 0),
      providentFundPercent: num_('providentFundPercent', 10),
      taxPercent: num_('taxPercent', 5),
    );
  }
}

/// PUT /hr/payroll-settings
///
/// The rare update in this codebase that is **fully null-guarded** — every
/// field is checked before it is assigned, so an omitted key genuinely means
/// "leave it alone". The form still sends everything, because it shows
/// everything and a form that displays a value should mean it.
///
/// Ranges are enforced server-side with readable messages: the overtime
/// multiplier is 1–5, standard hours 1–24, and every percentage 0–100.
class PayrollSettingsRequest {
  const PayrollSettingsRequest({
    required this.perDayBasis,
    required this.absenceDeductionBase,
    required this.overtimeEnabled,
    required this.overtimeMultiplier,
    required this.overtimeBase,
    required this.standardHoursPerDay,
    required this.houseRentPercent,
    required this.medicalPercent,
    required this.transportPercent,
    required this.foodPercent,
    required this.providentFundPercent,
    required this.taxPercent,
  });

  final String perDayBasis;
  final String absenceDeductionBase;
  final bool overtimeEnabled;
  final double overtimeMultiplier;
  final String overtimeBase;
  final double standardHoursPerDay;
  final double houseRentPercent;
  final double medicalPercent;
  final double transportPercent;
  final double foodPercent;
  final double providentFundPercent;
  final double taxPercent;

  Map<String, dynamic> toJson() => {
        'perDayBasis': perDayBasis,
        'absenceDeductionBase': absenceDeductionBase,
        'overtimeEnabled': overtimeEnabled,
        'overtimeMultiplier': overtimeMultiplier,
        'overtimeBase': overtimeBase,
        'standardHoursPerDay': standardHoursPerDay,
        'houseRentPercent': houseRentPercent,
        'medicalPercent': medicalPercent,
        'transportPercent': transportPercent,
        'foodPercent': foodPercent,
        'providentFundPercent': providentFundPercent,
        'taxPercent': taxPercent,
      };
}

/// What a bulk generate produced. `POST /hr/payroll/generate`.
///
/// Three lists of names, not counts — and the distinction between the two
/// skipped lists is the whole point. Somebody skipped because a record already
/// exists is fine. Somebody skipped for want of a salary structure is a person
/// who will not be paid this month, and that is what the screen leads with.
class BulkPayrollResult {
  const BulkPayrollResult({
    this.created = const [],
    this.alreadyExisted = const [],
    this.noSalaryStructure = const [],
  });

  final List<String> created;
  final List<String> alreadyExisted;
  final List<String> noSalaryStructure;

  /// The one that needs somebody to do something about it.
  bool get hasProblems => noSalaryStructure.isNotEmpty;

  String get summary {
    if (created.isEmpty && alreadyExisted.isEmpty && noSalaryStructure.isEmpty) {
      return 'Nothing to generate — no employees matched.';
    }
    final parts = <String>[
      created.length == 1
          ? '1 record created'
          : '${created.length} records created',
      if (alreadyExisted.isNotEmpty) '${alreadyExisted.length} already existed',
      if (noSalaryStructure.isNotEmpty)
        '${noSalaryStructure.length} without a salary structure',
    ];
    return '${parts.join(', ')}.';
  }

  factory BulkPayrollResult.fromJson(Map<String, dynamic> json) {
    List<String> names(String key) => [
          for (final name in (json[key] as List? ?? const [])) name.toString(),
        ];
    return BulkPayrollResult(
      created: names('created'),
      alreadyExisted: names('skippedAlreadyExists'),
      noSalaryStructure: names('skippedNoSalaryStructure'),
    );
  }
}
