/// Squaring the books against the bank.
///
/// A reconciliation is opened against one bank account with the balance the
/// statement says. The gap between that and the general ledger is closed by
/// ticking off which ledger entries have actually cleared, and it can only be
/// closed when the gap is nothing.
library;

abstract final class ReconciliationPermissions {
  static const view = 'BANK_RECONCILIATION_VIEW';
  static const create = 'BANK_RECONCILIATION_CREATE';

  /// Closing one. A separate code from creating it, so somebody may open a
  /// reconciliation and not be the one who signs it off.
  static const reconcile = 'BANK_RECONCILIATION_RECONCILE';
}

class BankReconciliation {
  const BankReconciliation({
    required this.id,
    required this.glBalance,
    required this.bankStatementBalance,
    required this.difference,
    required this.adjustedBankBalance,
    required this.reconciled,
    required this.outstandingDepositsTotal,
    required this.outstandingChecksTotal,
    this.bankAccountId,
    this.bankAccountName,
    this.reconciliationDate,
    this.reconciledDate,
    this.reconciledBy,
    this.discrepancyNotes,
    this.statementFileName,
    this.statementFileUrl,
    this.statementUploadedAt,
  });

  final int id;

  /// What the ledger says the account holds.
  final double glBalance;

  /// What the bank says.
  final double bankStatementBalance;

  final double difference;
  final double outstandingDepositsTotal;
  final double outstandingChecksTotal;

  /// The statement balance plus deposits not yet shown, less cheques not yet
  /// presented. The backend works it out so the two sides do not disagree
  /// about the arithmetic; it should equal [glBalance] before closing.
  final double adjustedBankBalance;

  final bool reconciled;
  final int? bankAccountId;
  final String? bankAccountName;
  final String? reconciliationDate;
  final String? reconciledDate;
  final String? reconciledBy;
  final String? discrepancyNotes;
  final String? statementFileName;
  final String? statementFileUrl;
  final String? statementUploadedAt;

  /// Whether it can be signed off. The backend refuses while anything is out,
  /// and rounding is not a reason to be out by a hundredth.
  bool get balances => difference.abs() < 0.005;

  factory BankReconciliation.fromJson(Map<String, dynamic> json) {
    double number(String key) => (json[key] as num?)?.toDouble() ?? 0;

    return BankReconciliation(
      id: (json['id'] as num?)?.toInt() ?? 0,
      glBalance: number('glBalance'),
      bankStatementBalance: number('bankStatementBalance'),
      difference: number('difference'),
      adjustedBankBalance: number('adjustedBankBalance'),
      outstandingDepositsTotal: number('outstandingDepositsTotal'),
      outstandingChecksTotal: number('outstandingChecksTotal'),
      reconciled: json['reconciled'] as bool? ?? false,
      bankAccountId: (json['bankAccountId'] as num?)?.toInt(),
      bankAccountName: json['bankAccountName'] as String?,
      reconciliationDate: json['reconciliationDate'] as String?,
      reconciledDate: json['reconciledDate'] as String?,
      reconciledBy: json['reconciledBy'] as String?,
      discrepancyNotes: json['discrepancyNotes'] as String?,
      statementFileName: json['statementFileName'] as String?,
      statementFileUrl: json['statementFileUrl'] as String?,
      statementUploadedAt: json['statementUploadedAt'] as String?,
    );
  }
}

/// Opening a reconciliation. The date is set to today server-side and the
/// ledger balance is read there too, so neither is sent.
class BankReconciliationRequest {
  const BankReconciliationRequest({
    required this.bankAccountId,
    required this.bankStatementBalance,
  });

  final int bankAccountId;
  final double bankStatementBalance;

  Map<String, dynamic> toJson() => {
        'bankAccountId': bankAccountId,
        'bankStatementBalance': bankStatementBalance,
      };
}

/// What came of importing a bank statement.
class StatementImportResult {
  const StatementImportResult({
    required this.totalLines,
    required this.matched,
    required this.unmatchedCount,
    required this.unmatchedLines,
    this.reconciliation,
  });

  final int totalLines;
  final int matched;
  final int unmatchedCount;
  final List<UnmatchedStatementLine> unmatchedLines;

  /// The reconciliation as it stands after the import, so the screen behind
  /// does not need a second call to catch up.
  final BankReconciliation? reconciliation;

  factory StatementImportResult.fromJson(Map<String, dynamic> json) =>
      StatementImportResult(
        totalLines: (json['totalLines'] as num?)?.toInt() ?? 0,
        matched: (json['matched'] as num?)?.toInt() ?? 0,
        unmatchedCount: (json['unmatchedCount'] as num?)?.toInt() ?? 0,
        unmatchedLines: (json['unmatchedLines'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(UnmatchedStatementLine.fromJson)
            .toList(growable: false),
        reconciliation: json['reconciliation'] is Map<String, dynamic>
            ? BankReconciliation.fromJson(
                json['reconciliation'] as Map<String, dynamic>,
              )
            : null,
      );
}

/// A line the import could not pair with anything in the ledger, and why.
class UnmatchedStatementLine {
  const UnmatchedStatementLine({
    required this.amount,
    this.date,
    this.description,
    this.reason,
  });

  final double amount;
  final String? date;
  final String? description;
  final String? reason;

  factory UnmatchedStatementLine.fromJson(Map<String, dynamic> json) =>
      UnmatchedStatementLine(
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        date: json['date'] as String?,
        description: json['description'] as String?,
        reason: json['reason'] as String?,
      );
}
