import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/features/hrpolicy/hrpolicy_models.dart';

/// The leave policy and shift updates both assign primitive booleans without a
/// null check, so an omitted flag arrives as false. Leaving out `paid` would
/// silently make a leave type unpaid — that is what these pin.
void main() {
  group('LeavePolicyRequest', () {
    const policy = LeavePolicy(
      id: 1,
      leaveType: 'ANNUAL',
      annualEntitlement: 20,
      maxCarryForward: 5,
      requiresApproval: true,
      canCarryForward: true,
      paid: true,
      applicableFromMonths: 3,
      active: true,
      maxConsecutiveDays: 10,
    );

    test('always sends the three flags', () {
      final json = LeavePolicyRequest.from(policy).toJson();
      expect(json['requiresApproval'], isTrue);
      expect(json['canCarryForward'], isTrue);
      expect(json['paid'], isTrue);
    });

    test('sends false explicitly rather than dropping the key', () {
      final json = const LeavePolicyRequest(
        leaveType: 'UNPAID',
        annualEntitlement: 0,
        requiresApproval: false,
        canCarryForward: false,
        paid: false,
      ).toJson();
      for (final key in ['requiresApproval', 'canCarryForward', 'paid']) {
        expect(json.containsKey(key), isTrue);
        expect(json[key], isFalse);
      }
    });

    test('zero days is a real answer, not a missing one', () {
      // @Min(0) — the type exists but grants nothing.
      final json = const LeavePolicyRequest(
        leaveType: 'UNPAID',
        annualEntitlement: 0,
        requiresApproval: true,
        canCarryForward: false,
        paid: false,
      ).toJson();
      expect(json['annualEntitlement'], 0);
    });

    test('carries the whole policy over when editing', () {
      final json = LeavePolicyRequest.from(policy).toJson();
      expect(json['annualEntitlement'], 20);
      expect(json['maxCarryForward'], 5);
      expect(json['maxConsecutiveDays'], 10);
      expect(json['applicableFromMonths'], 3);
    });
  });

  group('LeavePolicy', () {
    test('reads its terms as a sentence', () {
      const paid = LeavePolicy(
        id: 1,
        leaveType: 'ANNUAL',
        annualEntitlement: 20,
        maxCarryForward: 5,
        requiresApproval: true,
        canCarryForward: true,
        paid: true,
        applicableFromMonths: 0,
        active: true,
      );
      expect(paid.terms, contains('20 days a year'));
      expect(paid.terms, contains('carry 5 over'));
      expect(paid.terms, isNot(contains('unpaid')));

      const unpaid = LeavePolicy(
        id: 2,
        leaveType: 'UNPAID',
        annualEntitlement: 0,
        maxCarryForward: 0,
        requiresApproval: true,
        canCarryForward: false,
        paid: false,
        applicableFromMonths: 6,
        active: true,
      );
      expect(unpaid.terms, contains('unpaid'));
      expect(unpaid.terms, contains('no carry-over'));
      expect(unpaid.terms, contains('after 6 months'));
    });
  });

  group('ShiftRequest', () {
    const shift = Shift(
      id: 1,
      name: 'Night',
      shiftType: 'NIGHT',
      gracePeriodMinutes: 10,
      flexible: false,
      nightShift: true,
      active: true,
      workingMinutes: -480,
      startTime: '22:00:00',
      endTime: '06:00:00',
    );

    test('always sends both flags and both free-text fields', () {
      final json = ShiftRequest.from(shift).toJson();
      expect(json['flexible'], isFalse);
      expect(json['nightShift'], isTrue);
      // Assigned unconditionally, so present even when null.
      expect(json.containsKey('description'), isTrue);
      expect(json.containsKey('notes'), isTrue);
    });

    test('sends times with seconds, which LocalTime wants', () {
      final json = ShiftRequest.from(shift).toJson();
      expect(json['startTime'], '22:00:00');
      expect(json['endTime'], '06:00:00');
    });
  });

  group('Shift', () {
    test('a shift crossing midnight is eight hours, not minus eight', () {
      // The backend subtracts the times directly, so an overnight shift comes
      // back negative.
      const night = Shift(
        id: 1,
        name: 'Night',
        shiftType: 'NIGHT',
        gracePeriodMinutes: 0,
        flexible: false,
        nightShift: true,
        active: true,
        workingMinutes: -480,
      );
      expect(night.hours, 16.0);

      const day = Shift(
        id: 2,
        name: 'Day',
        shiftType: 'FULL_DAY',
        gracePeriodMinutes: 0,
        flexible: false,
        nightShift: false,
        active: true,
        workingMinutes: 480,
      );
      expect(day.hours, 8.0);
    });

    test('shortens the times for display, and says when there are none', () {
      const shift = Shift(
        id: 1,
        name: 'x',
        shiftType: 'MORNING',
        gracePeriodMinutes: 0,
        flexible: false,
        nightShift: false,
        active: true,
        workingMinutes: 0,
        startTime: '09:00:00',
        endTime: '17:30:00',
      );
      expect(shift.window, '09:00 — 17:30');
      expect(
        Shift.fromJson(const {'id': 1, 'name': 'x'}).window,
        'No hours set',
      );
    });
  });

  group('HolidayRequest', () {
    test('sends the three required fields and drops an empty description', () {
      final json = const HolidayRequest(
        name: ' Eid ',
        holidayDate: '2026-03-20',
        holidayType: 'RELIGIOUS',
        description: '   ',
      ).toJson();
      expect(json['name'], 'Eid');
      expect(json['holidayDate'], '2026-03-20');
      expect(json['holidayType'], 'RELIGIOUS');
      expect(json.containsKey('description'), isFalse);
    });
  });

  group('HrLetter', () {
    test('names whoever it is about, employee or candidate', () {
      expect(
        HrLetter.fromJson(const {'id': 1, 'employeeName': 'Anwar'}).about,
        'Anwar',
      );
      // An offer letter goes to somebody not on the payroll yet.
      expect(
        HrLetter.fromJson(const {'id': 1, 'recipientName': 'Bilkis'}).about,
        'Bilkis',
      );
      expect(HrLetter.fromJson(const {'id': 1}).about, 'Unnamed');
    });

    test('a letter is a draft until it is issued', () {
      expect(HrLetter.fromJson(const {'id': 1}).issued, isFalse);
      expect(
        HrLetter.fromJson(const {'id': 1, 'issued': true}).issued,
        isTrue,
      );
    });
  });

  group('HrLetterRequest', () {
    test('sends either an employee or an application, never a blank one', () {
      final forEmployee = const HrLetterRequest(
        letterType: 'CONFIRMATION',
        issueDate: '2026-08-31',
        content: 'Body',
        employeeId: 4,
      ).toJson();
      expect(forEmployee['employeeId'], 4);
      expect(forEmployee.containsKey('jobApplicationId'), isFalse);

      final forCandidate = const HrLetterRequest(
        letterType: 'OFFER',
        issueDate: '2026-08-31',
        content: 'Body',
        jobApplicationId: 9,
      ).toJson();
      expect(forCandidate['jobApplicationId'], 9);
      expect(forCandidate.containsKey('employeeId'), isFalse);
    });
  });
}
