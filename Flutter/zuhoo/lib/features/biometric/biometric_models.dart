/// Attendance terminals, and who is enrolled on them.
///
/// **Enrolling and verifying are deliberately absent.** `POST /enroll` takes a
/// base64 biometric template and `POST /{id}/verify` takes another as a query
/// parameter — both produced by the terminal's own SDK, not by a phone. A form
/// asking somebody to type a fingerprint template would be theatre. The app
/// manages the devices and can read and revoke enrollments; enrolling happens
/// at the terminal.
abstract final class BiometricPermissions {
  static const view = 'BIOMETRIC_VIEW';
  static const manage = 'BIOMETRIC_MANAGE';
}

/// Mirrors `BiometricDeviceType`.
const biometricDeviceTypes = <String>[
  'FINGERPRINT_TERMINAL',
  'FACIAL_RECOGNITION',
  'RFID_READER',
  'IRIS_SCANNER',
  'HYBRID',
  'GPS_TRACKING',
  'NFC_READER',
  'QR_SCANNER',
];

/// Mirrors `BiometricDeviceStatus`. Distinct from online/offline, which is
/// whether the thing is reachable right now rather than whether it is in use.
const biometricDeviceStatuses = <String>[
  'ACTIVE',
  'INACTIVE',
  'MAINTENANCE',
  'OFFLINE',
];

class BiometricDevice {
  const BiometricDevice({
    required this.id,
    required this.deviceName,
    required this.deviceId,
    required this.status,
    required this.isOnline,
    required this.portNumber,
    required this.matchThreshold,
    required this.enabledForCheckIn,
    required this.enabledForCheckOut,
    required this.totalEnrollments,
    this.deviceType,
    this.ipAddress,
    this.location,
    this.department,
    this.notes,
    this.manufacturer,
    this.model,
    this.firmwareVersion,
    this.lastSyncTime,
    this.maxEnrollments,
  });

  final int id;
  final String deviceName;

  /// The manufacturer's own identifier, unique per company. Not the row id.
  final String deviceId;

  final String status;
  final bool isOnline;
  final int portNumber;
  final int matchThreshold;
  final bool enabledForCheckIn;
  final bool enabledForCheckOut;
  final int totalEnrollments;
  final String? deviceType;
  final String? ipAddress;
  final String? location;
  final String? department;
  final String? notes;
  final String? manufacturer;
  final String? model;
  final String? firmwareVersion;
  final String? lastSyncTime;
  final int? maxEnrollments;

  /// Where to find it, and how to reach it.
  String get whereAndHow {
    final address = ipAddress == null
        ? null
        : (portNumber > 0 ? '$ipAddress:$portNumber' : ipAddress!);
    return [
      if (location != null) location!,
      if (address != null) address,
    ].join(' · ');
  }

  /// What it is used for. A device enabled for neither records nothing, which
  /// is worth saying out loud.
  String get usage {
    if (enabledForCheckIn && enabledForCheckOut) return 'In and out';
    if (enabledForCheckIn) return 'In only';
    if (enabledForCheckOut) return 'Out only';
    return 'Records nothing';
  }

  /// How full it is, or null when the capacity is not known — an empty bar
  /// would read as "no enrollments" rather than "no limit".
  double? get capacityUsed {
    final max = maxEnrollments;
    if (max == null || max <= 0) return null;
    return (totalEnrollments / max).clamp(0.0, 1.0);
  }

  factory BiometricDevice.fromJson(Map<String, dynamic> json) =>
      BiometricDevice(
        id: (json['id'] as num?)?.toInt() ?? 0,
        deviceName: json['deviceName'] as String? ?? '',
        deviceId: json['deviceId'] as String? ?? '',
        status: json['status'] as String? ?? 'INACTIVE',
        // The backend names it `isOnline`, which Jackson serialises as
        // `online` for a boolean getter — both are read rather than guessing.
        isOnline: json['isOnline'] as bool? ?? json['online'] as bool? ?? false,
        portNumber: (json['portNumber'] as num?)?.toInt() ?? 0,
        matchThreshold: (json['matchThreshold'] as num?)?.toInt() ?? 0,
        enabledForCheckIn: json['enabledForCheckIn'] as bool? ?? false,
        enabledForCheckOut: json['enabledForCheckOut'] as bool? ?? false,
        totalEnrollments: (json['totalEnrollments'] as num?)?.toInt() ?? 0,
        deviceType: json['deviceType'] as String?,
        ipAddress: json['ipAddress'] as String?,
        location: json['location'] as String?,
        department: json['department'] as String?,
        notes: json['notes'] as String?,
        manufacturer: json['manufacturer'] as String?,
        model: json['model'] as String?,
        firmwareVersion: json['firmwareVersion'] as String?,
        lastSyncTime: json['lastSyncTime'] as String?,
        maxEnrollments: (json['maxEnrollments'] as num?)?.toInt(),
      );
}

/// POST and PATCH /company/biometric/devices
///
/// The update assigns name, type, IP, port, location, department and notes
/// **unconditionally**, so all seven go on every save. `portNumber` is the one
/// that bites: it is a primitive `int`, so an omitted key arrives as zero and
/// the device loses its port.
///
/// `deviceId` is `@NotBlank` and so must be sent even on an edit, where the
/// service ignores it — a device's manufacturer identifier cannot be changed.
///
/// `matchThreshold` and the two enabled flags are null-guarded, but they are
/// sent anyway: the form shows them, so it should mean them.
class BiometricDeviceRequest {
  const BiometricDeviceRequest({
    required this.deviceName,
    required this.deviceType,
    required this.deviceId,
    required this.portNumber,
    required this.enabledForCheckIn,
    required this.enabledForCheckOut,
    this.ipAddress,
    this.location,
    this.department,
    this.notes,
    this.matchThreshold,
  });

  final String deviceName;
  final String deviceType;
  final String deviceId;
  final int portNumber;
  final bool enabledForCheckIn;
  final bool enabledForCheckOut;
  final String? ipAddress;
  final String? location;
  final String? department;
  final String? notes;
  final int? matchThreshold;

  factory BiometricDeviceRequest.from(BiometricDevice device) =>
      BiometricDeviceRequest(
        deviceName: device.deviceName,
        deviceType: device.deviceType ?? biometricDeviceTypes.first,
        deviceId: device.deviceId,
        portNumber: device.portNumber,
        enabledForCheckIn: device.enabledForCheckIn,
        enabledForCheckOut: device.enabledForCheckOut,
        ipAddress: device.ipAddress,
        location: device.location,
        department: device.department,
        notes: device.notes,
        matchThreshold: device.matchThreshold,
      );

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'deviceName': deviceName.trim(),
      'deviceType': deviceType,
      'deviceId': deviceId.trim(),
      // Always present: a primitive int that defaults to zero when absent.
      'portNumber': portNumber,
      'enabledForCheckIn': enabledForCheckIn,
      'enabledForCheckOut': enabledForCheckOut,
      // Explicit nulls rather than omissions — these are assigned without a
      // guard, so omitting one clears it just the same, and being explicit
      // says so.
      'ipAddress': clean(ipAddress),
      'location': clean(location),
      'department': clean(department),
      'notes': clean(notes),
      if (matchThreshold != null) 'matchThreshold': matchThreshold,
    };
  }
}

/// One person's enrollment on one device.
///
/// The base64 template itself is not modelled: it is the biometric, it is
/// useless to the app, and it has no business sitting in a phone's memory.
class BiometricEnrollment {
  const BiometricEnrollment({
    required this.id,
    required this.enrolled,
    required this.active,
    required this.successfulMatches,
    required this.failedMatches,
    this.employeeId,
    this.employeeName,
    this.deviceId,
    this.deviceName,
    this.biometricType,
    this.enrollmentDate,
    this.enrolledBy,
    this.enrollmentQualityScore,
    this.lastVerifiedTime,
  });

  final int id;
  final bool enrolled;
  final bool active;
  final int successfulMatches;
  final int failedMatches;
  final int? employeeId;
  final String? employeeName;
  final int? deviceId;
  final String? deviceName;
  final String? biometricType;
  final String? enrollmentDate;
  final String? enrolledBy;
  final double? enrollmentQualityScore;
  final String? lastVerifiedTime;

  /// Whether it can actually be used to check in.
  bool get isUsable => enrolled && active;

  /// How often it is failing to recognise them, or null before it has been
  /// tried — a fresh enrollment is not a perfect one, it is an untested one.
  double? get failureRate {
    final total = successfulMatches + failedMatches;
    if (total == 0) return null;
    return failedMatches / total;
  }

  factory BiometricEnrollment.fromJson(Map<String, dynamic> json) =>
      BiometricEnrollment(
        id: (json['id'] as num?)?.toInt() ?? 0,
        enrolled: json['enrolled'] as bool? ?? false,
        active: json['active'] as bool? ?? false,
        successfulMatches: (json['successfulMatches'] as num?)?.toInt() ?? 0,
        failedMatches: (json['failedMatches'] as num?)?.toInt() ?? 0,
        employeeId: (json['employeeId'] as num?)?.toInt(),
        employeeName: json['employeeName'] as String?,
        deviceId: (json['deviceId'] as num?)?.toInt(),
        deviceName: json['deviceName'] as String?,
        biometricType: json['biometricType'] as String?,
        enrollmentDate: json['enrollmentDate'] as String?,
        enrolledBy: json['enrolledBy'] as String?,
        enrollmentQualityScore:
            (json['enrollmentQualityScore'] as num?)?.toDouble(),
        lastVerifiedTime: json['lastVerifiedTime'] as String?,
      );
}
