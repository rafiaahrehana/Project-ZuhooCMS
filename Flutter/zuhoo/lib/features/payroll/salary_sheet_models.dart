/// The whole company's pay for one month, worked out live.
///
/// Nothing here is stored. It is a view of what the month currently looks
/// like, so it moves as attendance is corrected — running payroll is the
/// separate act that freezes these figures.
library;

class SalarySheet {
  const SalarySheet({
    required this.payMonth,
    required this.payYear,
    required this.rows,
    required this.totals,
    this.perDayBasis,
    this.perDayDivisor = 0,
    this.overtimeEnabled = false,
    this.overtimeMultiplier,
  });

  final int payMonth;
  final int payYear;
  final List<SalarySheetRow> rows;

  /// The column totals, taken from the response rather than added up here.
  /// Recomputing them locally would let the footer disagree with the sheet
  /// the moment rounding differs.
  final SalarySheetTotals totals;

  /// How a day rate was reached — echoed so the sheet can explain itself
  /// rather than leaving somebody to reverse-engineer the arithmetic.
  final String? perDayBasis;
  final int perDayDivisor;

  final bool overtimeEnabled;
  final double? overtimeMultiplier;

  factory SalarySheet.fromJson(Map<String, dynamic> json) => SalarySheet(
        payMonth: (json['payMonth'] as num?)?.toInt() ?? 0,
        payYear: (json['payYear'] as num?)?.toInt() ?? 0,
        rows: (json['rows'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(SalarySheetRow.fromJson)
            .toList(growable: false),
        totals: SalarySheetTotals.fromJson(json),
        perDayBasis: json['perDayBasis'] as String?,
        perDayDivisor: (json['perDayDivisor'] as num?)?.toInt() ?? 0,
        overtimeEnabled: json['overtimeEnabled'] as bool? ?? false,
        overtimeMultiplier: (json['overtimeMultiplier'] as num?)?.toDouble(),
      );
}

/// The footer of the sheet. Read off the same response body as the rows —
/// the backend puts the totals alongside them rather than nesting them.
class SalarySheetTotals {
  const SalarySheetTotals({
    required this.grossEarnings,
    required this.deductions,
    required this.netPayable,
    required this.basic,
    required this.overtimePayment,
    required this.bonus,
    required this.tax,
    required this.providentFund,
    required this.absentDays,
    required this.absentDeduction,
  });

  final double grossEarnings;
  final double deductions;
  final double netPayable;
  final double basic;
  final double overtimePayment;
  final double bonus;
  final double tax;
  final double providentFund;
  final int absentDays;
  final double absentDeduction;

  factory SalarySheetTotals.fromJson(Map<String, dynamic> json) {
    double number(String key) => (json[key] as num?)?.toDouble() ?? 0;

    return SalarySheetTotals(
      grossEarnings: number('totalGrossEarnings'),
      deductions: number('totalDeductions'),
      netPayable: number('totalNetPayable'),
      basic: number('totalBasic'),
      overtimePayment: number('totalOvertimePayment'),
      bonus: number('totalBonus'),
      tax: number('totalTax'),
      providentFund: number('totalProvidentFund'),
      absentDays: (json['totalAbsentDays'] as num?)?.toInt() ?? 0,
      absentDeduction: number('totalAbsentDeduction'),
    );
  }
}

/// One person's line on the sheet.
class SalarySheetRow {
  const SalarySheetRow({
    required this.basic,
    required this.grossEarnings,
    required this.totalDeductions,
    required this.netPayable,
    required this.absentDays,
    this.employeeId,
    this.employeeNumber,
    this.employeeName,
    this.position,
    this.department,
    this.houseRent = 0,
    this.medical = 0,
    this.transport = 0,
    this.food = 0,
    this.special = 0,
    this.overtimeHours = 0,
    this.overtimePayment = 0,
    this.otherEarnings = 0,
    this.otherDeductions = 0,
    this.bonus = 0,
    this.absentDeduction = 0,
    this.tax = 0,
    this.providentFund = 0,
    this.note,
    this.payrollId,
    this.paymentStatus,
    this.paymentMethod,
    this.source,
  });

  final double basic;
  final double grossEarnings;
  final double totalDeductions;
  final double netPayable;
  final int absentDays;

  final int? employeeId;
  final String? employeeNumber;
  final String? employeeName;
  final String? position;
  final String? department;

  final double houseRent;
  final double medical;
  final double transport;
  final double food;
  final double special;
  final double overtimeHours;
  final double overtimePayment;

  /// Extras from the person's structure — a loan repayment, an internet
  /// allowance — frozen the same way payroll freezes them.
  final double otherEarnings;
  final double otherDeductions;

  final double bonus;
  final double absentDeduction;
  final double tax;
  final double providentFund;
  final String? note;

  /// Set once the month has actually been run for this person. Its presence
  /// is what separates a projection from a payment.
  final int? payrollId;

  final String? paymentStatus;
  final String? paymentMethod;

  /// Where the figures came from — a structure, a template, or nothing.
  final String? source;

  /// Whether the month has been run for this person yet.
  bool get isRun => payrollId != null;

  String get personLabel =>
      employeeName ?? employeeNumber ?? 'Employee #${employeeId ?? "?"}';

  factory SalarySheetRow.fromJson(Map<String, dynamic> json) {
    double number(String key) => (json[key] as num?)?.toDouble() ?? 0;

    return SalarySheetRow(
      basic: number('basic'),
      grossEarnings: number('grossEarnings'),
      totalDeductions: number('totalDeductions'),
      netPayable: number('netPayable'),
      absentDays: (json['absentDays'] as num?)?.toInt() ?? 0,
      employeeId: (json['employeeId'] as num?)?.toInt(),
      employeeNumber: json['employeeNumber'] as String?,
      employeeName: json['employeeName'] as String?,
      position: json['position'] as String?,
      department: json['department'] as String?,
      houseRent: number('houseRent'),
      medical: number('medical'),
      transport: number('transport'),
      food: number('food'),
      special: number('special'),
      overtimeHours: number('overtimeHours'),
      overtimePayment: number('overtimePayment'),
      otherEarnings: number('otherEarnings'),
      otherDeductions: number('otherDeductions'),
      bonus: number('bonus'),
      absentDeduction: number('absentDeduction'),
      tax: number('tax'),
      providentFund: number('providentFund'),
      note: json['note'] as String?,
      payrollId: (json['payrollId'] as num?)?.toInt(),
      paymentStatus: json['paymentStatus'] as String?,
      paymentMethod: json['paymentMethod'] as String?,
      source: json['source'] as String?,
    );
  }
}
