import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/features/salary/salary_models.dart';

/// The salary structure update is the most destructive unconditional assign in
/// the codebase: every optional figure goes through `orZero(...)`, so an
/// omitted allowance is not preserved — it is set to nothing. These tests pin
/// that all seven are always on the wire.
void main() {
  group('SalaryStructureRequest', () {
    const request = SalaryStructureRequest(
      employeeId: 4,
      effectiveFrom: '2026-09-01',
      grossSalary: 50000,
      basicSalary: 30000,
    );

    test('sends every allowance and deduction, even at zero', () {
      final json = request.toJson();
      for (final key in [
        'houseRent',
        'medicalAllowance',
        'transportAllowance',
        'foodAllowance',
        'specialAllowance',
        'providentFund',
        'taxDeduction',
      ]) {
        expect(
          json.containsKey(key),
          isTrue,
          reason: '$key is run through orZero() and assigned unconditionally — '
              'omitting it wipes it',
        );
        expect(json[key], 0);
      }
    });

    test('carries the whole structure over when editing', () {
      const existing = SalaryStructure(
        id: 9,
        employeeId: 4,
        grossSalary: 50000,
        basicSalary: 30000,
        effectiveFrom: '2026-01-01',
        houseRent: 12000,
        medicalAllowance: 3000,
        transportAllowance: 3000,
        providentFund: 3000,
        taxDeduction: 1500,
        notes: 'Reviewed in January.',
      );

      final json = SalaryStructureRequest.from(existing).toJson();
      expect(json['houseRent'], 12000);
      expect(json['medicalAllowance'], 3000);
      expect(json['transportAllowance'], 3000);
      // Absent on the source, and correctly sent as zero rather than dropped.
      expect(json['foodAllowance'], 0);
      expect(json['providentFund'], 3000);
      expect(json['notes'], 'Reviewed in January.');
    });

    test('omits only the notes, which the server does not coerce', () {
      expect(request.toJson().containsKey('notes'), isFalse);
    });
  });

  group('SalaryStructure', () {
    SalaryStructure structure({
      double gross = 50000,
      double basic = 30000,
      double? houseRent,
      String? effectiveTo,
    }) =>
        SalaryStructure(
          id: 1,
          employeeId: 1,
          grossSalary: gross,
          basicSalary: basic,
          houseRent: houseRent,
          effectiveTo: effectiveTo,
        );

    test('only the undated structure is the current one', () {
      expect(structure().isCurrent, isTrue);
      expect(structure(effectiveTo: '2026-08-31').isCurrent, isFalse);
    });

    test('notices when the figures do not add up to gross', () {
      // Payroll uses them exactly as entered, so a gap is worth surfacing.
      expect(structure(houseRent: 20000).addsUp, isTrue);
      expect(structure(houseRent: 12000).addsUp, isFalse);
      expect(structure(houseRent: 12000).unallocated, 8000);
      // Over-allocated reads as a negative remainder, not as zero.
      expect(structure(houseRent: 25000).unallocated, -5000);
    });
  });

  group('LoanAdvance', () {
    LoanAdvance loan({
      double principal = 12000,
      double remaining = 9000,
      double installment = 3000,
      String status = LoanStatus.active,
    }) =>
        LoanAdvance(
          id: 1,
          employeeId: 1,
          type: 'LOAN',
          principalAmount: principal,
          monthlyInstallment: installment,
          remainingBalance: remaining,
          status: status,
        );

    test('rounds the remaining months up, never down', () {
      // The last instalment is usually short; rounding down would promise an
      // early finish that does not happen.
      expect(loan(remaining: 9000).monthsRemaining, 3);
      expect(loan(remaining: 9500).monthsRemaining, 4);
      expect(loan(remaining: 1).monthsRemaining, 1);
    });

    test('a cancelled loan has no schedule left', () {
      expect(loan(status: LoanStatus.cancelled).monthsRemaining, isNull);
      expect(loan(status: LoanStatus.closed).monthsRemaining, isNull);
    });

    test('reports how much has come back', () {
      expect(loan(remaining: 9000).repaid, 3000);
      expect(loan(remaining: 9000).repaidShare, 0.25);
      expect(loan(remaining: 0).repaidShare, 1.0);
    });

    test('a zero principal has no share rather than dividing by nothing', () {
      expect(loan(principal: 0, remaining: 0).repaidShare, isNull);
    });
  });

  group('SalaryComponentRequest', () {
    test('sends all five unconditional fields', () {
      // The update assigns name, type, calculationType, taxable and active
      // straight from the request with no null check.
      final json = const SalaryComponentRequest(
        name: 'Night shift bonus',
        type: 'EARNING',
        calculationType: 'FIXED',
        taxable: false,
        active: true,
      ).toJson();

      expect(json['name'], 'Night shift bonus');
      expect(json['type'], 'EARNING');
      expect(json['calculationType'], 'FIXED');
      expect(json['taxable'], isFalse);
      expect(json['active'], isTrue);
      expect(json['sortOrder'], 0);
    });

    test('never sends an id or a company — the service sets both', () {
      final json = const SalaryComponentRequest(
        name: 'x',
        type: 'DEDUCTION',
        calculationType: 'PERCENTAGE',
        taxable: true,
        active: true,
      ).toJson();
      expect(json.containsKey('id'), isFalse);
      expect(json.containsKey('company'), isFalse);
    });
  });
}
