/// IT asset management permissions, transcribed from the service layer rather
/// than from the Angular routes — the two differ, and the services are what
/// actually answer.
abstract final class ItamPermissions {
  /// Listing assets is `checkAnyPermission(HARDWARE_VIEW, ASSET_VIEW)` — either
  /// will do, which is why both are named here.
  static const hardwareView = 'HARDWARE_VIEW';
  static const assetView = 'ASSET_VIEW';

  /// Assigning, returning, flagging maintenance and editing the record itself
  /// are all one permission.
  static const hardwareUpdate = 'HARDWARE_UPDATE';

  static const hardwareCreate = 'HARDWARE_CREATE';
  static const hardwareDelete = 'HARDWARE_DELETE';

  static const softwareView = 'SOFTWARE_LICENSE_VIEW';
  static const softwareCreate = 'SOFTWARE_LICENSE_CREATE';

  /// Seats specifically — distinct from editing the licence itself.
  static const softwareAssign = 'SOFTWARE_LICENSE_ASSIGN';

  static const offboardingView = 'OFFBOARDING_VIEW';
  static const offboardingCreate = 'OFFBOARDING_CREATE';

  /// Ticking any step off. Not the same as creating or deleting a checklist,
  /// which are OFFBOARDING_CREATE and OFFBOARDING_DELETE and stay on the web.
  static const offboardingManage = 'OFFBOARDING_MANAGE';

  /// Reading the assignment trail: `checkAnyPermission(ASSET_ASSIGNMENT_VIEW,
  /// ASSET_VIEW)`.
  static const assignmentView = 'ASSET_ASSIGNMENT_VIEW';
}

abstract final class AssetStatus {
  static const available = 'AVAILABLE';
  static const assigned = 'ASSIGNED';
  static const underMaintenance = 'UNDER_MAINTENANCE';
  static const disposed = 'DISPOSED';

  /// The order the filter offers them in — what you are most likely looking
  /// for first. Disposed is last because it is an archive, not a working set.
  static const all = [available, assigned, underMaintenance, disposed];
}

/// A piece of company hardware.
class Asset {
  const Asset({
    required this.id,
    required this.name,
    required this.status,
    this.category,
    this.assetTag,
    this.serialNumber,
    this.brand,
    this.model,
    this.assignedToId,
    this.assignedToName,
    this.assignedAt,
    this.returnDate,
    this.purchaseDate,
    this.warrantyExpiry,
    this.operatingSystem,
    this.processorModel,
    this.ramSize,
    this.storageSize,
    this.ipAddress,
    this.macAddress,
    this.notes,
  });

  final int id;
  final String name;
  final String status;
  final String? category;
  final String? assetTag;
  final String? serialNumber;
  final String? brand;
  final String? model;
  final int? assignedToId;
  final String? assignedToName;
  final String? assignedAt;
  final String? returnDate;
  final String? purchaseDate;
  final String? warrantyExpiry;
  final String? operatingSystem;
  final String? processorModel;
  final String? ramSize;
  final String? storageSize;
  final String? ipAddress;
  final String? macAddress;
  final String? notes;

  bool get isAssigned => status == AssetStatus.assigned;
  bool get isAvailable => status == AssetStatus.available;
  bool get isUnderMaintenance => status == AssetStatus.underMaintenance;
  bool get isDisposed => status == AssetStatus.disposed;

  /// A disposed asset is history: it cannot be assigned, returned or sent for
  /// maintenance, so the detail screen offers nothing rather than offering
  /// buttons that fail.
  bool get isActionable => !isDisposed;

  /// `Dell · Latitude 5540`, or whichever half exists.
  String? get makeModel {
    final parts = [brand?.trim(), model?.trim()]
        .where((p) => p != null && p.isNotEmpty)
        .cast<String>();
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// The tag stencilled on the case, falling back to the serial. What someone
  /// holding the machine can actually read off it.
  String? get identifier {
    final tag = assetTag?.trim();
    if (tag != null && tag.isNotEmpty) return tag;
    final serial = serialNumber?.trim();
    return serial == null || serial.isEmpty ? null : serial;
  }

  /// Out of warranty, or within a month of it. Worth surfacing next to a
  /// machine somebody is about to be handed.
  bool get warrantyExpiringSoon {
    final expiry = DateTime.tryParse(warrantyExpiry ?? '');
    if (expiry == null) return false;
    final days = expiry.difference(DateTime.now()).inDays;
    return days <= 30;
  }

  factory Asset.fromJson(Map<String, dynamic> json) => Asset(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? 'Untitled asset',
        status: json['status'] as String? ?? AssetStatus.available,
        category: json['category'] as String?,
        assetTag: json['assetTag'] as String?,
        serialNumber: json['serialNumber'] as String?,
        brand: json['brand'] as String?,
        model: json['model'] as String?,
        assignedToId: (json['assignedToId'] as num?)?.toInt(),
        assignedToName: json['assignedToName'] as String?,
        assignedAt: json['assignedAt'] as String?,
        returnDate: json['returnDate'] as String?,
        purchaseDate: json['purchaseDate'] as String?,
        warrantyExpiry: json['warrantyExpiry'] as String?,
        operatingSystem: json['operatingSystem'] as String?,
        processorModel: json['processorModel'] as String?,
        ramSize: json['ramSize'] as String?,
        storageSize: json['storageSize'] as String?,
        ipAddress: json['ipAddress'] as String?,
        macAddress: json['macAddress'] as String?,
        notes: json['notes'] as String?,
      );
}

/// A software licence and how many of its seats are gone.
class SoftwareLicense {
  const SoftwareLicense({
    required this.id,
    required this.softwareName,
    required this.totalSeatsLicensed,
    required this.seatsUsed,
    required this.seatsAvailable,
    required this.expiringSoon,
    required this.expired,
    this.licenseStatus,
    this.licenseType,
    this.publisher,
    this.version,
    this.vendor,
    this.licenseExpiryDate,
    this.daysUntilExpiry,
    this.autoRenew = false,
    this.notes,
  });

  final int id;
  final String softwareName;
  final int totalSeatsLicensed;
  final int seatsUsed;
  final int seatsAvailable;

  /// Both computed server-side. Trusted over re-deriving from the date here,
  /// because "soon" is the backend's definition and the two must agree.
  final bool expiringSoon;
  final bool expired;

  final String? licenseStatus;
  final String? licenseType;
  final String? publisher;
  final String? version;
  final String? vendor;
  final String? licenseExpiryDate;
  final int? daysUntilExpiry;
  final bool autoRenew;
  final String? notes;

  bool get hasSeatsFree => seatsAvailable > 0;

  /// Every seat taken. Distinct from over-allocated, which the backend permits
  /// and which a compliance conversation cares about.
  bool get isFull => totalSeatsLicensed > 0 && seatsUsed >= totalSeatsLicensed;

  /// More seats in use than were bought.
  bool get isOverAllocated =>
      totalSeatsLicensed > 0 && seatsUsed > totalSeatsLicensed;

  /// 0 to 1, for the seat bar. Clamped so an over-allocated licence fills the
  /// bar rather than overflowing it — the number beside it tells the real story.
  double get seatFraction {
    if (totalSeatsLicensed <= 0) return 0;
    return (seatsUsed / totalSeatsLicensed).clamp(0, 1).toDouble();
  }

  String get seatsLabel => '$seatsUsed of $totalSeatsLicensed seats';

  factory SoftwareLicense.fromJson(Map<String, dynamic> json) =>
      SoftwareLicense(
        id: (json['id'] as num?)?.toInt() ?? 0,
        softwareName: json['softwareName'] as String? ?? 'Untitled licence',
        totalSeatsLicensed: (json['totalSeatsLicensed'] as num?)?.toInt() ?? 0,
        seatsUsed: (json['seatsUsed'] as num?)?.toInt() ?? 0,
        seatsAvailable: (json['seatsAvailable'] as num?)?.toInt() ?? 0,
        expiringSoon: json['expiringSoon'] as bool? ?? false,
        expired: json['expired'] as bool? ?? false,
        licenseStatus: json['licenseStatus'] as String?,
        licenseType: json['licenseType'] as String?,
        publisher: json['publisher'] as String?,
        version: json['version'] as String?,
        vendor: json['vendor'] as String?,
        licenseExpiryDate: json['licenseExpiryDate'] as String?,
        daysUntilExpiry: (json['daysUntilExpiry'] as num?)?.toInt(),
        autoRenew: json['autoRenew'] as bool? ?? false,
        notes: json['notes'] as String?,
      );
}

/// One step of an offboarding checklist, as the detail screen draws it.
///
/// The backend models the five steps as five boolean columns with their own
/// dates, notes and PATCH endpoints rather than as a list. This turns that
/// back into a list so the screen can render one row per step instead of five
/// near-identical blocks.
class OffboardingStep {
  const OffboardingStep({
    required this.key,
    required this.label,
    required this.done,
    required this.path,
    this.date,
    this.notes,
    this.by,
  });

  final String key;
  final String label;
  final bool done;

  /// The path segment its PATCH lives at.
  final String path;

  final String? date;
  final String? notes;
  final String? by;
}

/// Everything that has to happen when somebody leaves.
class OffboardingChecklist {
  const OffboardingChecklist({
    required this.id,
    required this.employeeId,
    required this.completed,
    required this.completionPercentage,
    required this.hardwareCollected,
    required this.licensesRevoked,
    required this.accessRevoked,
    required this.dataHandedOver,
    required this.exitInterviewCompleted,
    this.employeeName,
    this.offboardingDate,
    this.targetCompletionDate,
    this.completionDate,
    this.completedBy,
    this.hardwareCollectedDate,
    this.hardwareCollectedBy,
    this.hardwareNotes,
    this.licensesRevokedDate,
    this.licensesNotes,
    this.accessRevokedDate,
    this.accessNotes,
    this.dataHandoverDate,
    this.dataHandoverNotes,
    this.exitInterviewDate,
    this.exitInterviewNotes,
    this.overallNotes,
  });

  final int id;
  final int employeeId;
  final bool completed;
  final int completionPercentage;
  final bool hardwareCollected;
  final bool licensesRevoked;
  final bool accessRevoked;
  final bool dataHandedOver;
  final bool exitInterviewCompleted;
  final String? employeeName;
  final String? offboardingDate;
  final String? targetCompletionDate;
  final String? completionDate;
  final String? completedBy;
  final String? hardwareCollectedDate;
  final String? hardwareCollectedBy;
  final String? hardwareNotes;
  final String? licensesRevokedDate;
  final String? licensesNotes;
  final String? accessRevokedDate;
  final String? accessNotes;
  final String? dataHandoverDate;
  final String? dataHandoverNotes;
  final String? exitInterviewDate;
  final String? exitInterviewNotes;
  final String? overallNotes;

  String get personLabel => employeeName?.trim().isNotEmpty == true
      ? employeeName!.trim()
      : 'Employee #$employeeId';

  /// The five steps in the order they usually happen.
  List<OffboardingStep> get steps => [
        OffboardingStep(
          key: 'hardware',
          label: 'Hardware collected',
          done: hardwareCollected,
          path: 'hardware-collected',
          date: hardwareCollectedDate,
          notes: hardwareNotes,
          by: hardwareCollectedBy,
        ),
        OffboardingStep(
          key: 'licenses',
          label: 'Licences revoked',
          done: licensesRevoked,
          path: 'licenses-revoked',
          date: licensesRevokedDate,
          notes: licensesNotes,
        ),
        OffboardingStep(
          key: 'access',
          label: 'Access revoked',
          done: accessRevoked,
          path: 'access-revoked',
          date: accessRevokedDate,
          notes: accessNotes,
        ),
        OffboardingStep(
          key: 'data',
          label: 'Data handed over',
          done: dataHandedOver,
          path: 'data-handed-over',
          date: dataHandoverDate,
          notes: dataHandoverNotes,
        ),
        OffboardingStep(
          key: 'interview',
          label: 'Exit interview done',
          done: exitInterviewCompleted,
          path: 'exit-interview',
          date: exitInterviewDate,
          notes: exitInterviewNotes,
        ),
      ];

  int get stepsDone => steps.where((s) => s.done).length;

  /// Past its target date with work outstanding. The completion percentage
  /// alone does not say whether anyone is late.
  bool get isOverdue {
    if (completed) return false;
    final target = DateTime.tryParse(targetCompletionDate ?? '');
    if (target == null) return false;
    return DateTime.now().isAfter(target);
  }

  factory OffboardingChecklist.fromJson(Map<String, dynamic> json) =>
      OffboardingChecklist(
        id: (json['id'] as num?)?.toInt() ?? 0,
        employeeId: (json['employeeId'] as num?)?.toInt() ?? 0,
        completed: json['completed'] as bool? ?? false,
        completionPercentage:
            (json['completionPercentage'] as num?)?.toInt() ?? 0,
        hardwareCollected: json['hardwareCollected'] as bool? ?? false,
        licensesRevoked: json['licensesRevoked'] as bool? ?? false,
        accessRevoked: json['accessRevoked'] as bool? ?? false,
        dataHandedOver: json['dataHandedOver'] as bool? ?? false,
        exitInterviewCompleted:
            json['exitInterviewCompleted'] as bool? ?? false,
        employeeName: json['employeeName'] as String?,
        offboardingDate: json['offboardingDate'] as String?,
        targetCompletionDate: json['targetCompletionDate'] as String?,
        completionDate: json['completionDate'] as String?,
        completedBy: json['completedBy'] as String?,
        hardwareCollectedDate: json['hardwareCollectedDate'] as String?,
        hardwareCollectedBy: json['hardwareCollectedBy'] as String?,
        hardwareNotes: json['hardwareNotes'] as String?,
        licensesRevokedDate: json['licensesRevokedDate'] as String?,
        licensesNotes: json['licensesNotes'] as String?,
        accessRevokedDate: json['accessRevokedDate'] as String?,
        accessNotes: json['accessNotes'] as String?,
        dataHandoverDate: json['dataHandoverDate'] as String?,
        dataHandoverNotes: json['dataHandoverNotes'] as String?,
        exitInterviewDate: json['exitInterviewDate'] as String?,
        exitInterviewNotes: json['exitInterviewNotes'] as String?,
        overallNotes: json['overallNotes'] as String?,
      );
}

/// POST /hr/assets and PUT /hr/assets/{id}
///
/// One class for both, because the backend uses one DTO for both.
///
/// Despite the `PUT`, updating is a **sparse patch** — `AssetServiceImpl.update`
/// assigns only the fields that arrive non-null — but the DTO is still checked
/// with `@Valid`, so `name` is always sent or the request fails `@NotBlank`
/// before the service runs. Same shape as the lead endpoint.
///
/// **`description` is deliberately never sent.** The service writes *both*
/// `description` and `notes` into the same `asset.notes` column, one after the
/// other, so a request carrying both silently discards whichever loses the
/// race. Sending only `notes` keeps the field meaning one thing.
class AssetRequest {
  const AssetRequest({
    required this.name,
    this.category,
    this.assetTag,
    this.serialNumber,
    this.brand,
    this.model,
    this.purchaseDate,
    this.warrantyExpiry,
    this.operatingSystem,
    this.processorModel,
    this.ramSize,
    this.storageSize,
    this.ipAddress,
    this.macAddress,
    this.notes,
  });

  final String name;
  final String? category;
  final String? assetTag;
  final String? serialNumber;
  final String? brand;
  final String? model;
  final String? purchaseDate;
  final String? warrantyExpiry;
  final String? operatingSystem;
  final String? processorModel;
  final String? ramSize;
  final String? storageSize;
  final String? ipAddress;
  final String? macAddress;
  final String? notes;

  factory AssetRequest.from(Asset asset) => AssetRequest(
        name: asset.name,
        category: asset.category,
        assetTag: asset.assetTag,
        serialNumber: asset.serialNumber,
        brand: asset.brand,
        model: asset.model,
        purchaseDate: asset.purchaseDate,
        warrantyExpiry: asset.warrantyExpiry,
        operatingSystem: asset.operatingSystem,
        processorModel: asset.processorModel,
        ramSize: asset.ramSize,
        storageSize: asset.storageSize,
        ipAddress: asset.ipAddress,
        macAddress: asset.macAddress,
        notes: asset.notes,
      );

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'name': name.trim(),
      if (clean(category) != null) 'category': clean(category),
      if (clean(assetTag) != null) 'assetTag': clean(assetTag),
      if (clean(serialNumber) != null) 'serialNumber': clean(serialNumber),
      if (clean(brand) != null) 'brand': clean(brand),
      if (clean(model) != null) 'model': clean(model),
      if (purchaseDate != null) 'purchaseDate': purchaseDate,
      if (warrantyExpiry != null) 'warrantyExpiry': warrantyExpiry,
      if (clean(operatingSystem) != null)
        'operatingSystem': clean(operatingSystem),
      if (clean(processorModel) != null)
        'processorModel': clean(processorModel),
      if (clean(ramSize) != null) 'ramSize': clean(ramSize),
      if (clean(storageSize) != null) 'storageSize': clean(storageSize),
      if (clean(ipAddress) != null) 'ipAddress': clean(ipAddress),
      if (clean(macAddress) != null) 'macAddress': clean(macAddress),
      if (clean(notes) != null) 'notes': clean(notes),
      // No 'description': see the class comment.
    };
  }
}

/// The kinds of licence the backend recognises, with the wording it uses.
const licenseTypes = <({String value, String label})>[
  (value: 'SUBSCRIPTION', label: 'Subscription — recurring billing'),
  (value: 'PERPETUAL', label: 'Perpetual — one-time purchase'),
  (value: 'TRIAL', label: 'Trial — limited time'),
  (value: 'OPEN_SOURCE', label: 'Open source — free'),
];

/// How a licence comes up for renewal.
const licenseRenewalTypes = <({String value, String label})>[
  (value: 'ANNUAL', label: 'Annual renewal'),
  (value: 'MONTHLY', label: 'Monthly billing'),
  (value: 'BIENNIAL', label: 'Every 2 years'),
  (value: 'PERPETUAL', label: 'No renewal needed'),
];

/// POST /v1/itam/software
///
/// Unusually demanding for this codebase: the DTO is `@Valid` and nine of its
/// fields are `@NotNull` or `@NotBlank`, so almost nothing here is optional.
/// A licence the backend will accept has a key, a name, a publisher, a type, a
/// seat count, what it cost, when it was bought, when it expires, and how it
/// renews.
class SoftwareLicenseRequest {
  const SoftwareLicenseRequest({
    required this.licenseKey,
    required this.softwareName,
    required this.publisher,
    required this.licenseType,
    required this.totalSeatsLicensed,
    required this.licensePurchaseDate,
    required this.licenseExpiryDate,
    required this.licenseCost,
    required this.renewalType,
    this.version,
    this.nextRenewalDate,
    this.renewalCost,
  });

  final String licenseKey;
  final String softwareName;
  final String publisher;
  final String licenseType;

  /// `@Min(1)` — a licence with no seats is not a licence.
  final int totalSeatsLicensed;

  final String licensePurchaseDate;
  final String licenseExpiryDate;
  final double licenseCost;
  final String renewalType;
  final String? version;
  final String? nextRenewalDate;
  final double? renewalCost;

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      // Not trimmed: a licence key is copied verbatim and whitespace in it is
      // the vendor's business, not ours to normalise.
      'licenseKey': licenseKey,
      'softwareName': softwareName.trim(),
      'publisher': publisher.trim(),
      'licenseType': licenseType,
      'totalSeatsLicensed': totalSeatsLicensed,
      'licensePurchaseDate': licensePurchaseDate,
      'licenseExpiryDate': licenseExpiryDate,
      'licenseCost': licenseCost,
      'renewalType': renewalType,
      if (clean(version) != null) 'version': clean(version),
      if (nextRenewalDate != null) 'nextRenewalDate': nextRenewalDate,
      if (renewalCost != null) 'renewalCost': renewalCost,
    };
  }
}

/// POST /v1/company/offboarding/checklist
///
/// Opens the leaver's checklist. Only the employee is required; the five steps
/// start unticked and are worked through afterwards.
class OffboardingChecklistRequest {
  const OffboardingChecklistRequest({
    required this.employeeId,
    this.notes,
  });

  final int employeeId;
  final String? notes;

  Map<String, dynamic> toJson() {
    final trimmed = notes?.trim();
    return {
      'employeeId': employeeId,
      if (trimmed != null && trimmed.isNotEmpty) 'notes': trimmed,
    };
  }
}
