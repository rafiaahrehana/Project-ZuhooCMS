import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/features/payroll/payroll_models.dart';

/// Payroll is the one place where getting a state transition wrong costs real
/// money, so the transition table is pinned against the backend's own
/// `requireStatus` calls, and the dashboard's two "is this zero or is this
/// nothing" distinctions are pinned too.
void main() {
  PayrollRun run({String status = RunStatus.draft, int employees = 5}) =>
      PayrollRun(
        id: 1,
        runNumber: 'PR-2026-08',
        payMonth: 8,
        payYear: 2026,
        status: status,
        totalEmployees: employees,
        totalGross: 100000,
        totalDeduction: 12000,
        totalNet: 88000,
      );

  group('run transitions', () {
    test('a draft can be recalculated, submitted and cancelled', () {
      final draft = run();
      expect(draft.can(RunStatus.recalculateFrom), isTrue);
      expect(draft.can(RunStatus.submitFrom), isTrue);
      expect(draft.can(RunStatus.cancelFrom), isTrue);
      // But not approved or paid — those come later.
      expect(draft.can(RunStatus.approveFrom), isFalse);
      expect(draft.can(RunStatus.payFrom), isFalse);
    });

    test('only a pending run can be rejected', () {
      expect(
        run(status: RunStatus.pendingApproval).can(RunStatus.rejectFrom),
        isTrue,
      );
      expect(run(status: RunStatus.calculated).can(RunStatus.rejectFrom),
          isFalse);
      expect(run(status: RunStatus.approved).can(RunStatus.rejectFrom), isFalse);
    });

    test('only an approved run can be paid', () {
      expect(run(status: RunStatus.approved).can(RunStatus.payFrom), isTrue);
      expect(
        run(status: RunStatus.pendingApproval).can(RunStatus.payFrom),
        isFalse,
      );
    });

    test('a calculated run can be approved without being submitted', () {
      // Matches requireStatus(approve, PENDING_APPROVAL, CALCULATED) — the
      // backend allows the shortcut, so the screen must offer it.
      expect(
        run(status: RunStatus.calculated).can(RunStatus.approveFrom),
        isTrue,
      );
    });

    test('a rejected run goes back to being workable', () {
      final rejected = run(status: RunStatus.rejected);
      expect(rejected.can(RunStatus.recalculateFrom), isTrue);
      expect(rejected.can(RunStatus.submitFrom), isTrue);
      expect(rejected.can(RunStatus.cancelFrom), isTrue);
    });

    test('a paid or cancelled run is finished', () {
      for (final status in [RunStatus.paid, RunStatus.cancelled]) {
        final settled = run(status: status);
        expect(settled.isSettled, isTrue);
        expect(settled.can(RunStatus.recalculateFrom), isFalse);
        expect(settled.can(RunStatus.submitFrom), isFalse);
        expect(settled.can(RunStatus.approveFrom), isFalse);
        expect(settled.can(RunStatus.cancelFrom), isFalse);
        expect(settled.can(RunStatus.payFrom), isFalse);
      }
    });

    test('an empty run is not submittable', () {
      // The backend refuses with "Run has no payroll lines - recalculate
      // first"; the screen checks this before offering the button.
      expect(run(employees: 0).hasLines, isFalse);
      expect(run().hasLines, isTrue);
    });
  });

  group('PayrollDashboard', () {
    PayrollDashboard dashboard({
      int employees = 10,
      int lines = 10,
      int paid = 0,
    }) =>
        PayrollDashboard(
          month: 8,
          year: 2026,
          totalEmployees: employees,
          payrollCount: lines,
          employeesPaid: paid,
          pendingCount: lines - paid,
          totalGross: 0,
          totalNet: 0,
          totalDeductions: 0,
        );

    test('has no paid share when there is nothing to pay', () {
      // Distinct from nobody having been paid yet — an empty bar would say the
      // wrong thing about a month with no payroll at all.
      expect(dashboard(lines: 0).paidShare, isNull);
      expect(dashboard(paid: 0).paidShare, 0.0);
      expect(dashboard(paid: 5).paidShare, 0.5);
    });

    test('counts people the run missed entirely', () {
      // Someone with no line will not be paid, which is different from having
      // a line that is still pending.
      expect(dashboard(employees: 12, lines: 10).missing, 2);
      expect(dashboard(employees: 10, lines: 10).missing, 0);
      // More lines than employees is possible after someone leaves; it is not
      // a negative shortfall.
      expect(dashboard(employees: 8, lines: 10).missing, 0);
    });

    test('reads a month with nothing in it without inventing figures', () {
      final empty = PayrollDashboard.fromJson(const {'month': 8, 'year': 2026});
      expect(empty.totalEmployees, 0);
      expect(empty.payrollCount, 0);
      expect(empty.runStatus, isNull);
      expect(empty.trend, isEmpty);
      expect(empty.paidShare, isNull);
    });
  });

  group('BulkPayrollResult', () {
    test('separates the two reasons somebody was skipped', () {
      final result = BulkPayrollResult.fromJson(const {
        'created': ['Anwar', 'Bilkis'],
        'skippedAlreadyExists': ['Chowdhury'],
        'skippedNoSalaryStructure': ['Dilara', 'Emon'],
      });

      expect(result.created.length, 2);
      expect(result.alreadyExisted, ['Chowdhury']);
      expect(result.noSalaryStructure, ['Dilara', 'Emon']);
      // Only the missing-structure list needs somebody to act.
      expect(result.hasProblems, isTrue);
    });

    test('an already-existing record is not a problem', () {
      final result = BulkPayrollResult.fromJson(const {
        'created': <String>[],
        'skippedAlreadyExists': ['Chowdhury'],
      });
      expect(result.hasProblems, isFalse);
      expect(result.summary, '0 records created, 1 already existed.');
    });

    test('says so plainly when there was nothing to do', () {
      expect(
        BulkPayrollResult.fromJson(const {}).summary,
        'Nothing to generate — no employees matched.',
      );
    });
  });

  group('PayrollSettings', () {
    test('falls back to the backend defaults, not to zero', () {
      // A missing percentage is a field the server has not sent, not a company
      // that pays no house rent — the defaults here match the entity's own.
      final settings = PayrollSettings.fromJson(const {});
      expect(settings.houseRentPercent, 40);
      expect(settings.providentFundPercent, 10);
      expect(settings.overtimeMultiplier, 2);
      expect(settings.standardHoursPerDay, 8);
      expect(settings.foodPercent, 0);
    });

    test('totals the allowances for the form to warn on', () {
      expect(PayrollSettings.fromJson(const {}).allowanceTotal, 60);
    });

    test('sends every field, all of which the backend null-guards', () {
      const request = PayrollSettingsRequest(
        perDayBasis: 'FIXED_30',
        absenceDeductionBase: 'BASIC',
        overtimeEnabled: true,
        overtimeMultiplier: 1.5,
        overtimeBase: 'BASIC',
        standardHoursPerDay: 8,
        houseRentPercent: 40,
        medicalPercent: 10,
        transportPercent: 10,
        foodPercent: 0,
        providentFundPercent: 10,
        taxPercent: 5,
      );
      final json = request.toJson();
      expect(json.length, 12);
      expect(json['perDayBasis'], 'FIXED_30');
      expect(json['overtimeEnabled'], isTrue);
      // Zero is a real answer here and must survive the trip.
      expect(json.containsKey('foodPercent'), isTrue);
      expect(json['foodPercent'], 0);
    });
  });
}
