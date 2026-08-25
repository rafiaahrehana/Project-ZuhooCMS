import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/features/biometric/biometric_models.dart';
import 'package:zuhoo/features/workflow/workflow_models.dart';

/// Both of these update endpoints assign most of their fields with no null
/// check, and each has one primitive that defaults to something harmful when
/// the key is absent — a stage's flags, and a terminal's port.
void main() {
  group('WorkflowStageRequest', () {
    const stage = WorkflowStageRequest(
      name: 'Collect documents',
      stageOrder: 2,
      requiresApproval: false,
      requiresPayment: false,
    );

    test('sends every unconditional field, even as null', () {
      final json = stage.toJson();
      for (final key in [
        'stageOrder',
        'requiresApproval',
        'requiresPayment',
        'estimatedDays',
        'slaHours',
        'assigneeRole',
        'paymentPercent',
      ]) {
        expect(json.containsKey(key), isTrue, reason: '$key must be present');
      }
      expect(json['requiresApproval'], isFalse);
      expect(json['estimatedDays'], isNull);
    });

    test('omits an empty description, which the endpoint leaves alone', () {
      expect(stage.toJson().containsKey('description'), isFalse);
      expect(
        const WorkflowStageRequest(
          name: 'x',
          stageOrder: 1,
          requiresApproval: false,
          requiresPayment: false,
          description: '  ',
        ).toJson().containsKey('description'),
        isFalse,
      );
    });

    test('drops the payment share when no payment is required', () {
      // @Min(1) applies when it is sent, and a percent on a stage that takes
      // no money is meaningless anyway.
      expect(
        const WorkflowStageRequest(
          name: 'x',
          stageOrder: 1,
          requiresApproval: false,
          requiresPayment: false,
          paymentPercent: 50,
        ).toJson()['paymentPercent'],
        isNull,
      );
      expect(
        const WorkflowStageRequest(
          name: 'x',
          stageOrder: 1,
          requiresApproval: false,
          requiresPayment: true,
          paymentPercent: 50,
        ).toJson()['paymentPercent'],
        50,
      );
    });

    test('carries the whole stage over when editing', () {
      const existing = WorkflowStage(
        id: 3,
        name: 'Review',
        stageOrder: 4,
        requiresApproval: true,
        requiresPayment: true,
        estimatedDays: 2,
        slaHours: 8,
        assigneeRole: 'EMPLOYEE',
        paymentPercent: 40,
      );
      final json = WorkflowStageRequest.from(existing).toJson();
      expect(json['stageOrder'], 4);
      expect(json['requiresApproval'], isTrue);
      expect(json['estimatedDays'], 2);
      expect(json['slaHours'], 8);
      expect(json['assigneeRole'], 'EMPLOYEE');
      expect(json['paymentPercent'], 40);
    });
  });

  group('WorkflowTemplate', () {
    WorkflowTemplate parse(List<Map<String, dynamic>> stages) =>
        WorkflowTemplate.fromJson({
          'id': 1,
          'name': 'Company formation',
          'version': 3,
          'active': true,
          'stages': stages,
        });

    test('puts the stages in order, whatever order they arrive in', () {
      final template = parse([
        {'id': 2, 'name': 'Second', 'stageOrder': 2},
        {'id': 1, 'name': 'First', 'stageOrder': 1},
        {'id': 3, 'name': 'Third', 'stageOrder': 3},
      ]);
      expect(
        template.stages.map((s) => s.name).toList(),
        ['First', 'Second', 'Third'],
      );
    });

    test('totals the days only when every stage says', () {
      expect(
        parse([
          {'id': 1, 'name': 'a', 'stageOrder': 1, 'estimatedDays': 2},
          {'id': 2, 'name': 'b', 'stageOrder': 2, 'estimatedDays': 3},
        ]).totalDays,
        5,
      );
      // One stage without an estimate makes the total a guess, not a fact.
      expect(
        parse([
          {'id': 1, 'name': 'a', 'stageOrder': 1, 'estimatedDays': 2},
          {'id': 2, 'name': 'b', 'stageOrder': 2},
        ]).totalDays,
        isNull,
      );
      expect(parse([]).totalDays, isNull);
    });
  });

  group('BiometricDeviceRequest', () {
    const device = BiometricDevice(
      id: 1,
      deviceName: 'Main entrance',
      deviceId: 'ZK-4001',
      status: 'ACTIVE',
      isOnline: true,
      portNumber: 4370,
      matchThreshold: 90,
      enabledForCheckIn: true,
      enabledForCheckOut: false,
      totalEnrollments: 12,
      deviceType: 'FINGERPRINT_TERMINAL',
      ipAddress: '10.0.0.14',
      location: 'Reception',
    );

    test('always sends the port', () {
      // A primitive int on the DTO: an absent key arrives as zero and the
      // device loses the port it was reachable on.
      final json = BiometricDeviceRequest.from(device).toJson();
      expect(json['portNumber'], 4370);
    });

    test('sends the device identifier even though the update ignores it', () {
      // It is @NotBlank, so leaving it out fails validation before the service
      // gets a chance to ignore it.
      expect(BiometricDeviceRequest.from(device).toJson()['deviceId'], 'ZK-4001');
    });

    test('sends the unconditional strings as explicit nulls when empty', () {
      final json = const BiometricDeviceRequest(
        deviceName: 'Gate',
        deviceType: 'RFID_READER',
        deviceId: 'G-1',
        portNumber: 80,
        enabledForCheckIn: true,
        enabledForCheckOut: true,
      ).toJson();
      for (final key in ['ipAddress', 'location', 'department', 'notes']) {
        expect(json.containsKey(key), isTrue);
        expect(json[key], isNull);
      }
    });
  });

  group('BiometricDevice', () {
    BiometricDevice device({
      bool checkIn = true,
      bool checkOut = true,
      int enrolled = 0,
      int? max,
    }) =>
        BiometricDevice(
          id: 1,
          deviceName: 'x',
          deviceId: 'x',
          status: 'ACTIVE',
          isOnline: true,
          portNumber: 0,
          matchThreshold: 95,
          enabledForCheckIn: checkIn,
          enabledForCheckOut: checkOut,
          totalEnrollments: enrolled,
          maxEnrollments: max,
        );

    test('says plainly when a terminal records nothing', () {
      expect(device().usage, 'In and out');
      expect(device(checkOut: false).usage, 'In only');
      expect(device(checkIn: false).usage, 'Out only');
      expect(device(checkIn: false, checkOut: false).usage, 'Records nothing');
    });

    test('has no capacity figure when the limit is unknown', () {
      expect(device(enrolled: 5).capacityUsed, isNull);
      expect(device(enrolled: 5, max: 0).capacityUsed, isNull);
      expect(device(enrolled: 5, max: 10).capacityUsed, 0.5);
    });

    test('reads either spelling of the online flag', () {
      expect(
        BiometricDevice.fromJson(const {'id': 1, 'online': true}).isOnline,
        isTrue,
      );
      expect(
        BiometricDevice.fromJson(const {'id': 1, 'isOnline': true}).isOnline,
        isTrue,
      );
      expect(BiometricDevice.fromJson(const {'id': 1}).isOnline, isFalse);
    });
  });

  group('BiometricEnrollment', () {
    BiometricEnrollment enrollment({
      bool enrolled = true,
      bool active = true,
      int good = 0,
      int bad = 0,
    }) =>
        BiometricEnrollment(
          id: 1,
          enrolled: enrolled,
          active: active,
          successfulMatches: good,
          failedMatches: bad,
        );

    test('needs both flags to be usable', () {
      expect(enrollment().isUsable, isTrue);
      expect(enrollment(active: false).isUsable, isFalse);
      expect(enrollment(enrolled: false).isUsable, isFalse);
    });

    test('has no failure rate before it has been tried', () {
      // A fresh enrollment is untested, not perfect.
      expect(enrollment().failureRate, isNull);
      expect(enrollment(good: 3, bad: 1).failureRate, 0.25);
    });
  });
}
