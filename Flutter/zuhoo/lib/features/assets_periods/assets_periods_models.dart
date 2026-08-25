/// Two things the books need doing to them periodically: writing down what the
/// company owns, and shutting a month so nothing more can be posted into it.
abstract final class ClosingPermissions {
  static const periodView = 'ACCOUNTING_PERIOD_VIEW';

  /// One code covers closing a period, reopening it, and closing the year.
  static const periodClose = 'ACCOUNTING_PERIOD_CLOSE';

  static const assetView = 'FIXED_ASSET_VIEW';

  /// Creating, disposing and running depreciation are all the same code.
  static const assetManage = 'FIXED_ASSET_MANAGE';
}

/// Mirrors `PeriodStatus`.
abstract final class PeriodStatus {
  static const open = 'OPEN';
  static const closed = 'CLOSED';
}

/// Mirrors `FixedAssetStatus`.
abstract final class AssetStatus {
  static const active = 'ACTIVE';
  static const fullyDepreciated = 'FULLY_DEPRECIATED';
  static const disposed = 'DISPOSED';
}

/// One accounting period — in practice one month.
class AccountingPeriod {
  const AccountingPeriod({
    required this.id,
    required this.fiscalYear,
    required this.periodNumber,
    required this.status,
    this.label,
    this.startDate,
    this.endDate,
    this.closedBy,
    this.closedAt,
    this.reopenedBy,
    this.reopenedAt,
  });

  final int id;
  final int fiscalYear;
  final int periodNumber;
  final String status;

  /// The calendar month this period covers — "Jan 2026". The backend builds
  /// it, so the app shows it rather than deriving its own.
  final String? label;

  final String? startDate;
  final String? endDate;
  final String? closedBy;
  final String? closedAt;
  final String? reopenedBy;
  final String? reopenedAt;

  bool get isOpen => status == PeriodStatus.open;

  /// A period that has been closed and opened again. Worth surfacing: it means
  /// figures somebody may have already reported on have since moved.
  bool get wasReopened => reopenedAt != null;

  String get title => label ?? 'Period $periodNumber';

  factory AccountingPeriod.fromJson(Map<String, dynamic> json) =>
      AccountingPeriod(
        id: (json['id'] as num?)?.toInt() ?? 0,
        fiscalYear: (json['fiscalYear'] as num?)?.toInt() ?? 0,
        periodNumber: (json['periodNumber'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? PeriodStatus.open,
        label: json['label'] as String?,
        startDate: json['startDate'] as String?,
        endDate: json['endDate'] as String?,
        closedBy: json['closedBy'] as String?,
        closedAt: json['closedAt'] as String?,
        reopenedBy: json['reopenedBy'] as String?,
        reopenedAt: json['reopenedAt'] as String?,
      );
}

/// A fiscal year and how far through closing it the company is.
class FiscalYear {
  const FiscalYear({
    required this.fiscalYear,
    required this.totalPeriods,
    required this.openPeriods,
    required this.closedPeriods,
    this.name,
    this.startDate,
    this.endDate,
  });

  final int fiscalYear;
  final int totalPeriods;
  final int openPeriods;
  final int closedPeriods;
  final String? name;
  final String? startDate;
  final String? endDate;

  /// Every period shut. Only then does closing the year make sense — until it
  /// is done, net income has not rolled into retained earnings, which is one
  /// of the two things that makes a balance sheet not balance.
  bool get fullyClosed => totalPeriods > 0 && openPeriods == 0;

  /// How far through, or null when there are no periods to close.
  double? get progress {
    if (totalPeriods <= 0) return null;
    return (closedPeriods / totalPeriods).clamp(0.0, 1.0);
  }

  String get title => name ?? 'FY $fiscalYear';

  factory FiscalYear.fromJson(Map<String, dynamic> json) => FiscalYear(
        fiscalYear: (json['fiscalYear'] as num?)?.toInt() ?? 0,
        totalPeriods: (json['totalPeriods'] as num?)?.toInt() ?? 0,
        openPeriods: (json['openPeriods'] as num?)?.toInt() ?? 0,
        closedPeriods: (json['closedPeriods'] as num?)?.toInt() ?? 0,
        name: json['name'] as String?,
        startDate: json['startDate'] as String?,
        endDate: json['endDate'] as String?,
      );
}

/// Something the company owns that loses value over time.
class FixedAsset {
  const FixedAsset({
    required this.id,
    required this.name,
    required this.cost,
    required this.usefulLifeMonths,
    required this.status,
    this.assetTag,
    this.category,
    this.salvageValue,
    this.acquisitionDate,
    this.accumulatedDepreciation,
    this.bookValue,
    this.monthlyDepreciation,
    this.notes,
  });

  final int id;
  final String name;
  final double cost;
  final int usefulLifeMonths;
  final String status;
  final String? assetTag;
  final String? category;
  final double? salvageValue;
  final String? acquisitionDate;
  final double? accumulatedDepreciation;

  /// What it is worth now: cost less what has been written off.
  final double? bookValue;

  final double? monthlyDepreciation;
  final String? notes;

  bool get isDisposed => status == AssetStatus.disposed;

  /// Disposing is only meaningful on something still held.
  bool get canDispose => !isDisposed;

  /// How much of its life has been written off, between nothing and all of it.
  double? get depreciated {
    if (cost <= 0) return null;
    return ((accumulatedDepreciation ?? 0) / cost).clamp(0.0, 1.0);
  }

  /// Whole months left at the current rate, or null when it is finished or the
  /// rate is unknown.
  int? get monthsRemaining {
    final monthly = monthlyDepreciation;
    final book = bookValue;
    if (isDisposed || monthly == null || monthly <= 0 || book == null) {
      return null;
    }
    final depreciable = book - (salvageValue ?? 0);
    if (depreciable <= 0) return 0;
    return (depreciable / monthly).ceil();
  }

  factory FixedAsset.fromJson(Map<String, dynamic> json) => FixedAsset(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        cost: (json['cost'] as num?)?.toDouble() ?? 0,
        usefulLifeMonths: (json['usefulLifeMonths'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? AssetStatus.active,
        assetTag: json['assetTag'] as String?,
        category: json['category'] as String?,
        salvageValue: (json['salvageValue'] as num?)?.toDouble(),
        acquisitionDate: json['acquisitionDate'] as String?,
        accumulatedDepreciation:
            (json['accumulatedDepreciation'] as num?)?.toDouble(),
        bookValue: (json['bookValue'] as num?)?.toDouble(),
        monthlyDepreciation:
            (json['monthlyDepreciation'] as num?)?.toDouble(),
        notes: json['notes'] as String?,
      );
}

/// POST /company/finance/fixed-assets
///
/// Three `@NotNull` fields — cost, useful life and the acquisition date — and
/// the cost is `@DecimalMin("0.01")`.
///
/// `postPurchaseToLedger` decides whether buying it writes a journal entry.
/// It is a `Boolean` rather than a primitive, so leaving it out genuinely means
/// "unset" and the backend picks — the form asks rather than guessing, because
/// the answer changes what appears in the books.
class FixedAssetRequest {
  const FixedAssetRequest({
    required this.name,
    required this.cost,
    required this.usefulLifeMonths,
    required this.acquisitionDate,
    this.assetTag,
    this.category,
    this.salvageValue,
    this.notes,
    this.postPurchaseToLedger,
  });

  final String name;
  final double cost;
  final int usefulLifeMonths;

  /// `yyyy-MM-dd`.
  final String acquisitionDate;

  final String? assetTag;
  final String? category;
  final double? salvageValue;
  final String? notes;
  final bool? postPurchaseToLedger;

  /// What it will be written off by each month, straight-line. Shown while
  /// filling the form in, because a useful life in months is hard to picture
  /// and a monthly figure is not.
  double get monthlyDepreciation {
    if (usefulLifeMonths <= 0) return 0;
    return (cost - (salvageValue ?? 0)) / usefulLifeMonths;
  }

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'name': name.trim(),
      'cost': cost,
      'usefulLifeMonths': usefulLifeMonths,
      'acquisitionDate': acquisitionDate,
      if (clean(assetTag) != null) 'assetTag': clean(assetTag),
      if (clean(category) != null) 'category': clean(category),
      if (salvageValue != null) 'salvageValue': salvageValue,
      if (clean(notes) != null) 'notes': clean(notes),
      if (postPurchaseToLedger != null)
        'postPurchaseToLedger': postPurchaseToLedger,
    };
  }
}

/// One month's depreciation, run across every asset at once.
class DepreciationRun {
  const DepreciationRun({
    required this.id,
    required this.year,
    required this.month,
    required this.totalAmount,
    required this.assetsDepreciated,
    this.runBy,
    this.runAt,
  });

  final int id;
  final int year;
  final int month;
  final double totalAmount;
  final int assetsDepreciated;
  final String? runBy;
  final String? runAt;

  factory DepreciationRun.fromJson(Map<String, dynamic> json) =>
      DepreciationRun(
        id: (json['id'] as num?)?.toInt() ?? 0,
        year: (json['year'] as num?)?.toInt() ?? 0,
        month: (json['month'] as num?)?.toInt() ?? 1,
        totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0,
        assetsDepreciated: (json['assetsDepreciated'] as num?)?.toInt() ?? 0,
        runBy: json['runBy'] as String?,
        runAt: json['runAt'] as String?,
      );
}
