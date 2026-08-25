/// What somebody is paid, and what they owe back.
///
/// A **salary structure** is the standing agreement — gross, basic, and the
/// allowances and deductions that make up the difference. Payroll reads it
/// every month, which is why an employee without one is silently skipped by the
/// monthly run.
///
/// A **loan or advance** is money paid out early and recovered from payroll in
/// instalments.
abstract final class SalaryPermissions {
  static const view = 'SALARY_STRUCTURE_VIEW';

  /// One code covers creating and editing, both structures and the component
  /// catalogue.
  static const create = 'SALARY_STRUCTURE_CREATE';

  static const delete = 'SALARY_STRUCTURE_DELETE';
}

/// One employee's standing pay agreement.
class SalaryStructure {
  const SalaryStructure({
    required this.id,
    required this.employeeId,
    required this.grossSalary,
    required this.basicSalary,
    this.employeeName,
    this.effectiveFrom,
    this.effectiveTo,
    this.houseRent,
    this.medicalAllowance,
    this.transportAllowance,
    this.foodAllowance,
    this.specialAllowance,
    this.providentFund,
    this.taxDeduction,
    this.netSalary,
    this.notes,
    this.approvedByName,
  });

  final int id;
  final int employeeId;
  final double grossSalary;
  final double basicSalary;
  final String? employeeName;
  final String? effectiveFrom;

  /// Set once a newer structure supersedes this one. Its presence is what makes
  /// a structure historical — and historical structures cannot be edited.
  final String? effectiveTo;

  final double? houseRent;
  final double? medicalAllowance;
  final double? transportAllowance;
  final double? foodAllowance;
  final double? specialAllowance;
  final double? providentFund;
  final double? taxDeduction;
  final double? netSalary;
  final String? notes;
  final String? approvedByName;

  /// The one in force. Only this one can be edited — the backend refuses the
  /// rest with "Only the current salary structure can be edited", so the screen
  /// offers editing only here.
  bool get isCurrent => effectiveTo == null;

  double get allowances =>
      (houseRent ?? 0) +
      (medicalAllowance ?? 0) +
      (transportAllowance ?? 0) +
      (foodAllowance ?? 0) +
      (specialAllowance ?? 0);

  double get deductions => (providentFund ?? 0) + (taxDeduction ?? 0);

  /// Basic plus allowances should come to gross. When it does not, the figures
  /// were entered by hand and disagree — worth showing rather than hiding,
  /// because payroll will use them as they are.
  double get unallocated => grossSalary - basicSalary - allowances;

  bool get addsUp => unallocated.abs() < 0.01;

  factory SalaryStructure.fromJson(Map<String, dynamic> json) => SalaryStructure(
        id: (json['id'] as num?)?.toInt() ?? 0,
        employeeId: (json['employeeId'] as num?)?.toInt() ?? 0,
        grossSalary: (json['grossSalary'] as num?)?.toDouble() ?? 0,
        basicSalary: (json['basicSalary'] as num?)?.toDouble() ?? 0,
        employeeName: json['employeeName'] as String?,
        effectiveFrom: json['effectiveFrom'] as String?,
        effectiveTo: json['effectiveTo'] as String?,
        houseRent: (json['houseRent'] as num?)?.toDouble(),
        medicalAllowance: (json['medicalAllowance'] as num?)?.toDouble(),
        transportAllowance: (json['transportAllowance'] as num?)?.toDouble(),
        foodAllowance: (json['foodAllowance'] as num?)?.toDouble(),
        specialAllowance: (json['specialAllowance'] as num?)?.toDouble(),
        providentFund: (json['providentFund'] as num?)?.toDouble(),
        taxDeduction: (json['taxDeduction'] as num?)?.toDouble(),
        netSalary: (json['netSalary'] as num?)?.toDouble(),
        notes: json['notes'] as String?,
        approvedByName: json['approvedByName'] as String?,
      );
}

/// POST and PUT /hr/salary-structures
///
/// **Every optional figure is coerced to zero when absent.** The update runs
/// each allowance and deduction through `orZero(...)` and assigns it
/// unconditionally, so leaving one out does not preserve it — it wipes it. The
/// form therefore seeds all seven from the structure and sends all seven back.
///
/// Four fields are `@NotNull`: the employee, the effective date, gross and
/// basic. Gross and basic are also `@DecimalMin("0.01")`, so neither can be
/// zero — a structure with no pay in it is refused.
///
/// Creating a second structure for an employee supersedes the first rather
/// than replacing it: the old one gets an `effectiveTo` and is locked.
class SalaryStructureRequest {
  const SalaryStructureRequest({
    required this.employeeId,
    required this.effectiveFrom,
    required this.grossSalary,
    required this.basicSalary,
    this.houseRent = 0,
    this.medicalAllowance = 0,
    this.transportAllowance = 0,
    this.foodAllowance = 0,
    this.specialAllowance = 0,
    this.providentFund = 0,
    this.taxDeduction = 0,
    this.notes,
  });

  final int employeeId;

  /// `yyyy-MM-dd`.
  final String effectiveFrom;

  final double grossSalary;
  final double basicSalary;

  /// Non-nullable on purpose: the server treats absent as zero, so there is no
  /// such thing as "not set" here and pretending otherwise would mislead.
  final double houseRent;
  final double medicalAllowance;
  final double transportAllowance;
  final double foodAllowance;
  final double specialAllowance;
  final double providentFund;
  final double taxDeduction;

  final String? notes;

  factory SalaryStructureRequest.from(SalaryStructure structure) =>
      SalaryStructureRequest(
        employeeId: structure.employeeId,
        effectiveFrom: structure.effectiveFrom ?? '',
        grossSalary: structure.grossSalary,
        basicSalary: structure.basicSalary,
        houseRent: structure.houseRent ?? 0,
        medicalAllowance: structure.medicalAllowance ?? 0,
        transportAllowance: structure.transportAllowance ?? 0,
        foodAllowance: structure.foodAllowance ?? 0,
        specialAllowance: structure.specialAllowance ?? 0,
        providentFund: structure.providentFund ?? 0,
        taxDeduction: structure.taxDeduction ?? 0,
        notes: structure.notes,
      );

  Map<String, dynamic> toJson() {
    final trimmed = notes?.trim();
    return {
      'employeeId': employeeId,
      'effectiveFrom': effectiveFrom,
      'grossSalary': grossSalary,
      'basicSalary': basicSalary,
      // All seven, always: see the class comment.
      'houseRent': houseRent,
      'medicalAllowance': medicalAllowance,
      'transportAllowance': transportAllowance,
      'foodAllowance': foodAllowance,
      'specialAllowance': specialAllowance,
      'providentFund': providentFund,
      'taxDeduction': taxDeduction,
      if (trimmed != null && trimmed.isNotEmpty) 'notes': trimmed,
    };
  }
}

/// Money paid out early and recovered from payroll.
const loanTypes = <String>['LOAN', 'ADVANCE'];

abstract final class LoanStatus {
  static const active = 'ACTIVE';
  static const closed = 'CLOSED';
  static const cancelled = 'CANCELLED';
}

class LoanAdvance {
  const LoanAdvance({
    required this.id,
    required this.employeeId,
    required this.type,
    required this.principalAmount,
    required this.monthlyInstallment,
    required this.remainingBalance,
    required this.status,
    this.employeeName,
    this.disbursedDate,
    this.reason,
    this.notes,
  });

  final int id;
  final int employeeId;
  final String type;
  final double principalAmount;
  final double monthlyInstallment;
  final double remainingBalance;
  final String status;
  final String? employeeName;
  final String? disbursedDate;
  final String? reason;
  final String? notes;

  bool get isActive => status == LoanStatus.active;

  double get repaid => principalAmount - remainingBalance;

  /// How much has come back, between nothing and all of it. Null when the
  /// principal is zero, which should not happen but would divide badly.
  double? get repaidShare {
    if (principalAmount <= 0) return null;
    return (repaid / principalAmount).clamp(0.0, 1.0);
  }

  /// Whole months left at the current instalment, rounded up — the last one is
  /// usually short, and rounding down would promise an early finish.
  int? get monthsRemaining {
    if (!isActive || monthlyInstallment <= 0) return null;
    return (remainingBalance / monthlyInstallment).ceil();
  }

  factory LoanAdvance.fromJson(Map<String, dynamic> json) => LoanAdvance(
        id: (json['id'] as num?)?.toInt() ?? 0,
        employeeId: (json['employeeId'] as num?)?.toInt() ?? 0,
        type: json['type'] as String? ?? 'LOAN',
        principalAmount: (json['principalAmount'] as num?)?.toDouble() ?? 0,
        monthlyInstallment:
            (json['monthlyInstallment'] as num?)?.toDouble() ?? 0,
        remainingBalance: (json['remainingBalance'] as num?)?.toDouble() ?? 0,
        status: json['status'] as String? ?? LoanStatus.active,
        employeeName: json['employeeName'] as String?,
        disbursedDate: json['disbursedDate'] as String?,
        reason: json['reason'] as String?,
        notes: json['notes'] as String?,
      );
}

/// POST /hr/loans
///
/// Five `@NotNull` fields, and both money figures are `@DecimalMin("0.01")` —
/// neither the principal nor the instalment can be zero. There is no update
/// endpoint: a loan is cancelled and re-entered rather than edited, which is
/// the right behaviour for something payroll has already recovered against.
class CreateLoanRequest {
  const CreateLoanRequest({
    required this.employeeId,
    required this.type,
    required this.principalAmount,
    required this.disbursedDate,
    required this.monthlyInstallment,
    this.reason,
    this.notes,
  });

  final int employeeId;
  final String type;
  final double principalAmount;

  /// `yyyy-MM-dd`.
  final String disbursedDate;

  final double monthlyInstallment;
  final String? reason;
  final String? notes;

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'employeeId': employeeId,
      'type': type,
      'principalAmount': principalAmount,
      'disbursedDate': disbursedDate,
      'monthlyInstallment': monthlyInstallment,
      if (clean(reason) != null) 'reason': clean(reason),
      if (clean(notes) != null) 'notes': clean(notes),
    };
  }
}

/// One instalment recovered from one month's payroll.
class LoanRepayment {
  const LoanRepayment({
    required this.id,
    required this.amount,
    this.payMonth,
    this.payYear,
    this.paidDate,
    this.balanceAfter,
  });

  final int id;
  final double amount;
  final int? payMonth;
  final int? payYear;
  final String? paidDate;
  final double? balanceAfter;

  factory LoanRepayment.fromJson(Map<String, dynamic> json) => LoanRepayment(
        id: (json['id'] as num?)?.toInt() ?? 0,
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        payMonth: (json['payMonth'] as num?)?.toInt(),
        payYear: (json['payYear'] as num?)?.toInt(),
        paidDate: json['paidDate'] as String?,
        balanceAfter: (json['balanceAfter'] as num?)?.toDouble(),
      );
}

/// A line item that can be added to a salary structure — a bonus, a levy, an
/// employer contribution.
const componentTypes = <String>['EARNING', 'DEDUCTION', 'EMPLOYER_CONTRIBUTION'];
const calculationTypes = <String>['FIXED', 'PERCENTAGE'];

class SalaryComponent {
  const SalaryComponent({
    required this.id,
    required this.name,
    required this.type,
    required this.calculationType,
    required this.taxable,
    required this.active,
    this.sortOrder = 0,
  });

  final int id;
  final String name;
  final String type;
  final String calculationType;
  final bool taxable;
  final bool active;
  final int sortOrder;

  bool get isEarning => type == 'EARNING';

  factory SalaryComponent.fromJson(Map<String, dynamic> json) =>
      SalaryComponent(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        type: json['type'] as String? ?? 'EARNING',
        calculationType: json['calculationType'] as String? ?? 'FIXED',
        taxable: json['taxable'] as bool? ?? true,
        active: json['active'] as bool? ?? true,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      );
}

/// POST and PUT /hr/salary-components
///
/// Unusually, this endpoint takes the **entity** as its request body rather
/// than a DTO — `@RequestBody SalaryComponent`. The company and id are set by
/// the service, so neither is sent.
///
/// The update assigns name, type, calculation type, taxable and active
/// unconditionally, so all five go every time. Only `sortOrder` is
/// null-guarded, and it is sent anyway.
class SalaryComponentRequest {
  const SalaryComponentRequest({
    required this.name,
    required this.type,
    required this.calculationType,
    required this.taxable,
    required this.active,
    this.sortOrder = 0,
  });

  final String name;
  final String type;
  final String calculationType;
  final bool taxable;
  final bool active;
  final int sortOrder;

  factory SalaryComponentRequest.from(SalaryComponent component) =>
      SalaryComponentRequest(
        name: component.name,
        type: component.type,
        calculationType: component.calculationType,
        taxable: component.taxable,
        active: component.active,
        sortOrder: component.sortOrder,
      );

  Map<String, dynamic> toJson() => {
        'name': name.trim(),
        'type': type,
        'calculationType': calculationType,
        'taxable': taxable,
        'active': active,
        'sortOrder': sortOrder,
      };
}
