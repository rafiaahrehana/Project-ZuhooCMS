import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/features/directory/education_section.dart';
import 'package:zuhoo/features/performance/performance_models.dart';
import 'package:zuhoo/features/salary/template_models.dart';

void main() {
  group('SalaryTemplateRequest', () {
    final template = SalaryTemplate.fromJson(const {
      'id': 2,
      'structureName': 'Engineer Grade A',
      'defaultGross': 100000,
      'basicPercentage': 50,
      'hraPercentage': 40,
      'medicalAmount': 2000,
      'transportAmount': 1500,
      'internetAmount': 500,
      'mobileAmount': 300,
      'mealAmount': 1200,
      'active': true,
    });

    test('an edit carries every figure, because nz() zeroes what is missing',
        () {
      final json = SalaryTemplateRequest.from(template).toJson();

      // Every allowance must be present. Any one left out arrives as null and
      // is written back as zero.
      for (final key in const [
        'basicPercentage',
        'hraPercentage',
        'medicalAmount',
        'transportAmount',
        'internetAmount',
        'mobileAmount',
        'mealAmount',
      ]) {
        expect(json.containsKey(key), isTrue, reason: '$key must be sent');
      }
      expect(json['internetAmount'], 500);
      expect(json['mealAmount'], 1200);
    });

    test('active is the one field that may be omitted', () {
      const request = SalaryTemplateRequest(
        structureName: 'Grade B',
        basicPercentage: 50,
        hraPercentage: 40,
        medicalAmount: 0,
        transportAmount: 0,
        internetAmount: 0,
        mobileAmount: 0,
        mealAmount: 0,
      );
      expect(request.toJson().containsKey('active'), isFalse);
    });
  });

  group('SalaryBreakdown', () {
    test('spots the parts adding up to more than the gross', () {
      // Internet and mobile are returned but never subtracted from gross when
      // the backend works out the special allowance, so they sit on top.
      final breakdown = SalaryBreakdown.fromJson(const {
        'grossSalary': 100000.0,
        'basicSalary': 50000.0,
        'houseRent': 20000.0,
        'medicalAllowance': 2000.0,
        'transportAllowance': 1500.0,
        'internetAllowance': 500.0,
        'mobileAllowance': 300.0,
        'foodAllowance': 1200.0,
        'specialAllowance': 25300.0,
      });

      expect(breakdown.gross, 100000);
      expect(breakdown.overrun, closeTo(800, 0.001));
    });

    test('a breakdown that adds up reports no overrun', () {
      final breakdown = SalaryBreakdown.fromJson(const {
        'grossSalary': 1000.0,
        'basicSalary': 500.0,
        'specialAllowance': 500.0,
      });
      expect(breakdown.overrun, 0);
    });

    test('non-numeric values are dropped rather than crashing', () {
      final breakdown = SalaryBreakdown.fromJson(const {
        'grossSalary': 100.0,
        'note': 'something',
      });
      expect(breakdown.lines.containsKey('note'), isFalse);
    });
  });

  group('StructureExtraLine', () {
    test('a round trip keeps the component and its figure', () {
      final extra = StructureExtra.fromJson(const {
        'id': 8,
        'componentId': 3,
        'componentName': 'Night shift',
        'type': 'EARNING',
        'amount': 450.0,
      });

      // The id of the extra itself is not sent back — setExtras deletes and
      // rewrites, so only the component and the amount matter.
      expect(StructureExtraLine.from(extra).toJson(), {
        'componentId': 3,
        'amount': 450.0,
      });
    });
  });

  group('PerformanceKpis', () {
    test('null is not zero', () {
      final kpis = PerformanceKpis.fromJson(const {
        'daysPresent': 18,
        'workingDaysRecorded': 20,
        'attendancePercent': 90.0,
      });

      expect(kpis.attendancePercent, 90);
      // Nobody rated their work. That is unknown, not nought out of five.
      expect(kpis.customerSatisfaction, isNull);
      expect(kpis.hasAnything, isTrue);
    });

    test('a period with nothing recorded says so', () {
      final kpis = PerformanceKpis.fromJson(const {});
      expect(kpis.hasAnything, isFalse);
      expect(kpis.attendancePercent, isNull);
      expect(kpis.daysPresent, 0);
    });
  });

  group('QualificationRequest', () {
    test('sends every key so an omission cannot clear a field by accident',
        () {
      const request = QualificationRequest(employeeId: 4, degree: 'BSc');

      expect(request.toJson().keys.toSet(), {
        'employeeId',
        'degree',
        'institution',
        'fieldOfStudy',
        'passingYear',
        'result',
        'notes',
      });
      expect(request.toJson()['institution'], isNull);
    });
  });
}
