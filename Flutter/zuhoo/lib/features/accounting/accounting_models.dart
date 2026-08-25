/// Double-entry bookkeeping: the accounts, the entries posted against them, and
/// the ledger those entries land in.
///
/// This is the one part of the app where a mistake is not undone but corrected
/// — a posted entry is reversed with an opposite entry, never edited away — so
/// the screens are deliberate about which actions are still open at each stage.
abstract final class AccountingPermissions {
  static const accountView = 'CHART_OF_ACCOUNT_VIEW';
  static const accountCreate = 'CHART_OF_ACCOUNT_CREATE';
  static const accountUpdate = 'CHART_OF_ACCOUNT_UPDATE';
  static const accountDelete = 'CHART_OF_ACCOUNT_DELETE';

  static const entryView = 'JOURNAL_ENTRY_VIEW';
  static const entryCreate = 'JOURNAL_ENTRY_CREATE';
  static const entryApprove = 'JOURNAL_ENTRY_APPROVE';
  static const entryPost = 'JOURNAL_ENTRY_POST';
  static const entryDelete = 'JOURNAL_ENTRY_DELETE';

  static const ledgerView = 'GENERAL_LEDGER_VIEW';
  static const ledgerReconcile = 'GENERAL_LEDGER_RECONCILE';
}

/// Mirrors `AccountType`.
///
/// Ordered as a balance sheet then an income statement reads, rather than
/// alphabetically, because that is the order an accountant expects them in.
const accountTypes = <String>[
  'ASSET',
  'CONTRA_ASSET',
  'LIABILITY',
  'CONTRA_LIABILITY',
  'EQUITY',
  'REVENUE',
  'CONTRA_REVENUE',
  'EXPENSE',
];

/// Which side of the books a type belongs to, for grouping the list.
String accountGroup(String type) => switch (type) {
      'ASSET' || 'CONTRA_ASSET' => 'Assets',
      'LIABILITY' || 'CONTRA_LIABILITY' => 'Liabilities',
      'EQUITY' => 'Equity',
      'REVENUE' || 'CONTRA_REVENUE' => 'Revenue',
      'EXPENSE' => 'Expenses',
      _ => 'Other',
    };

/// One account in the chart.
class Account {
  const Account({
    required this.id,
    required this.accountCode,
    required this.accountName,
    required this.type,
    required this.isHeaderAccount,
    required this.isBankAccount,
    required this.allowDirectPosting,
    required this.active,
    this.balance,
    this.description,
    this.notes,
  });

  final int id;
  final String accountCode;
  final String accountName;
  final String type;

  /// A rollup that exists to total its children. Nothing can be posted to it —
  /// the backend refuses with a message naming the account and saying to post
  /// to a child instead.
  final bool isHeaderAccount;

  final bool isBankAccount;
  final bool allowDirectPosting;
  final bool active;
  final double? balance;
  final String? description;
  final String? notes;

  /// Whether a journal entry line may name this account.
  bool get canPostTo => !isHeaderAccount && allowDirectPosting && active;

  String get group => accountGroup(type);

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        id: (json['id'] as num?)?.toInt() ?? 0,
        accountCode: json['accountCode'] as String? ?? '',
        accountName: json['accountName'] as String? ?? '',
        type: json['type'] as String? ?? 'ASSET',
        // The backend forces these two JSON keys with an explicit
        // @JsonProperty, because Jackson would otherwise strip the "is" from
        // Lombok's getter and send "headerAccount". Both spellings are read
        // here so a future change to that annotation cannot break the flag
        // silently.
        isHeaderAccount: json['isHeaderAccount'] as bool? ??
            json['headerAccount'] as bool? ??
            false,
        isBankAccount: json['isBankAccount'] as bool? ??
            json['bankAccount'] as bool? ??
            false,
        allowDirectPosting: json['allowDirectPosting'] as bool? ?? true,
        active: json['active'] as bool? ?? true,
        balance: (json['balance'] as num?)?.toDouble(),
        description: json['description'] as String?,
        notes: json['notes'] as String?,
      );
}

/// POST and PATCH /company/finance/chart-of-accounts
///
/// The update assigns name, type, description, all four flags and notes
/// **unconditionally**, so every one goes on every request.
///
/// The four flags are primitive booleans with field initialisers, which makes
/// omitting one worse than sending false: `allowDirectPosting` and `active`
/// default to **true** when absent, so a request that left them out would
/// quietly re-enable an account somebody had switched off.
///
/// `accountCode` is `@NotBlank` and `@Size(3, 10)`; changing it to one already
/// in use is refused with a message naming the code.
class AccountRequest {
  const AccountRequest({
    required this.accountCode,
    required this.accountName,
    required this.type,
    required this.isHeaderAccount,
    required this.isBankAccount,
    required this.allowDirectPosting,
    required this.active,
    this.description,
    this.notes,
    this.openingBalance,
    this.openingBalanceDate,
  });

  final String accountCode;
  final String accountName;
  final String type;
  final bool isHeaderAccount;
  final bool isBankAccount;
  final bool allowDirectPosting;
  final bool active;
  final String? description;
  final String? notes;

  /// Only meaningful on create, and only when migrating from another system.
  /// The backend posts a balanced entry against Opening Balance Equity rather
  /// than setting the balance directly, so the ledger backs the figure up.
  final double? openingBalance;

  /// `yyyy-MM-dd`.
  final String? openingBalanceDate;

  factory AccountRequest.from(Account account) => AccountRequest(
        accountCode: account.accountCode,
        accountName: account.accountName,
        type: account.type,
        isHeaderAccount: account.isHeaderAccount,
        isBankAccount: account.isBankAccount,
        allowDirectPosting: account.allowDirectPosting,
        active: account.active,
        description: account.description,
        notes: account.notes,
      );

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'accountCode': accountCode.trim(),
      'accountName': accountName.trim(),
      'type': type,
      // The two keys the backend pins with @JsonProperty.
      'isHeaderAccount': isHeaderAccount,
      'isBankAccount': isBankAccount,
      'allowDirectPosting': allowDirectPosting,
      'active': active,
      'description': clean(description),
      'notes': clean(notes),
      if (openingBalance != null) 'openingBalance': openingBalance,
      if (openingBalanceDate != null) 'openingBalanceDate': openingBalanceDate,
    };
  }
}

/// One journal entry and the lines that make it up.
class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.journalEntryNumber,
    required this.approved,
    required this.posted,
    required this.reversed,
    required this.amount,
    this.entryDate,
    this.description,
    this.notes,
    this.createdBy,
    this.approvedBy,
    this.postedDate,
    this.reversalEntryId,
    this.reversedFromEntryId,
    this.lines = const [],
  });

  final int id;
  final String journalEntryNumber;
  final bool approved;
  final bool posted;
  final bool reversed;

  /// The total of the debit side. Debits and credits are equal by definition —
  /// the backend refuses an entry that does not balance — so one figure says
  /// how big the entry is.
  final double amount;

  final String? entryDate;
  final String? description;
  final String? notes;
  final String? createdBy;
  final String? approvedBy;
  final String? postedDate;

  /// The entry that reverses this one, once it has been reversed.
  final int? reversalEntryId;

  /// Set when this entry *is* a reversal of another.
  final int? reversedFromEntryId;

  final List<JournalLine> lines;

  bool get isReversal => reversedFromEntryId != null;

  /// Where it is in the chain, as one word for the status chip.
  String get status {
    if (reversed) return 'REVERSED';
    if (posted) return 'POSTED';
    if (approved) return 'APPROVED';
    return 'DRAFT';
  }

  /// What can still be done to it, matching the service's own guards exactly.
  bool get canApprove => !approved;
  bool get canPost => approved && !posted;
  bool get canReverse => posted && !reversed;

  /// Deleting is refused once posted — at that point the ledger has moved and
  /// only a reversal can undo it.
  bool get canDelete => !posted;

  double get totalDebits {
    var total = 0.0;
    for (final line in lines) {
      total += line.debitAmount;
    }
    return total;
  }

  double get totalCredits {
    var total = 0.0;
    for (final line in lines) {
      total += line.creditAmount;
    }
    return total;
  }

  factory JournalEntry.fromJson(Map<String, dynamic> json) => JournalEntry(
        id: (json['id'] as num?)?.toInt() ?? 0,
        journalEntryNumber: json['journalEntryNumber'] as String? ?? '',
        approved: json['approved'] as bool? ?? false,
        posted: json['posted'] as bool? ?? false,
        reversed: json['reversed'] as bool? ?? false,
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        entryDate: json['entryDate'] as String?,
        description: json['description'] as String?,
        notes: json['notes'] as String?,
        createdBy: json['createdBy'] as String?,
        approvedBy: json['approvedBy'] as String?,
        postedDate: json['postedDate'] as String?,
        reversalEntryId: (json['reversalEntryId'] as num?)?.toInt(),
        reversedFromEntryId: (json['reversedFromEntryId'] as num?)?.toInt(),
        lines: [
          for (final line in (json['lines'] as List? ?? const []))
            if (line is Map<String, dynamic>) JournalLine.fromJson(line),
        ],
      );
}

class JournalLine {
  const JournalLine({
    required this.accountId,
    required this.debitAmount,
    required this.creditAmount,
    this.id,
    this.accountName,
    this.accountCode,
    this.lineDescription,
  });

  final int accountId;
  final double debitAmount;
  final double creditAmount;
  final int? id;
  final String? accountName;
  final String? accountCode;
  final String? lineDescription;

  bool get isDebit => debitAmount > 0;

  factory JournalLine.fromJson(Map<String, dynamic> json) => JournalLine(
        accountId: (json['accountId'] as num?)?.toInt() ?? 0,
        debitAmount: (json['debitAmount'] as num?)?.toDouble() ?? 0,
        creditAmount: (json['creditAmount'] as num?)?.toDouble() ?? 0,
        id: (json['id'] as num?)?.toInt(),
        accountName: json['accountName'] as String?,
        accountCode: json['accountCode'] as String?,
        lineDescription: json['lineDescription'] as String?,
      );
}

/// POST /company/finance/journal-entries
///
/// Always sent as a **lines list**. The DTO also accepts a legacy
/// `debitAccountId`/`creditAccountId`/`amount` triple, which the backend
/// expands into two lines — but that form cannot express an entry with three
/// legs, and mixing the two would be one shape too many.
///
/// The rules the backend enforces, each with its own message:
///
/// * at least two lines;
/// * every line has a debit or a credit, and never both;
/// * no negative amounts;
/// * debits equal credits;
/// * every account allows direct posting — a header account is refused by name.
///
/// [balances] and [problem] check the same things locally, so the form can say
/// what is wrong before it asks.
class JournalEntryRequest {
  const JournalEntryRequest({
    required this.entryDate,
    required this.lines,
    this.description,
    this.notes,
  });

  /// `yyyy-MM-dd`. `@NotNull`, though the service falls back to today.
  final String entryDate;

  final List<JournalLineRequest> lines;
  final String? description;
  final String? notes;

  double get totalDebits {
    var total = 0.0;
    for (final line in lines) {
      total += line.debitAmount;
    }
    return total;
  }

  double get totalCredits {
    var total = 0.0;
    for (final line in lines) {
      total += line.creditAmount;
    }
    return total;
  }

  /// Compared to the paisa rather than exactly: these are decimals typed by
  /// hand, and floating point makes an exact comparison a lie.
  bool get balances => (totalDebits - totalCredits).abs() < 0.005;

  /// The first thing wrong with it, worded as the backend would, or null when
  /// it would be accepted.
  String? get problem {
    if (lines.length < 2) return 'A journal entry needs at least two lines.';
    for (final line in lines) {
      if (line.debitAmount < 0 || line.creditAmount < 0) {
        return 'Line amounts cannot be negative.';
      }
      if (line.debitAmount > 0 && line.creditAmount > 0) {
        return 'A line can be a debit or a credit, not both.';
      }
      if (line.debitAmount == 0 && line.creditAmount == 0) {
        return 'Every line needs a debit or a credit.';
      }
      if (line.accountId == null) return 'Every line needs an account.';
    }
    if (!balances) {
      return 'Debits and credits must match. They differ by '
          '${(totalDebits - totalCredits).abs().toStringAsFixed(2)}.';
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'entryDate': entryDate,
      'lines': [for (final line in lines) line.toJson()],
      if (clean(description) != null) 'description': clean(description),
      if (clean(notes) != null) 'notes': clean(notes),
    };
  }
}

/// One leg of an entry.
///
/// [accountId] is nullable here but `@NotNull` on the wire: the form holds a
/// half-built line while somebody is still choosing an account, and
/// [JournalEntryRequest.problem] catches it before anything is sent.
class JournalLineRequest {
  const JournalLineRequest({
    this.accountId,
    this.debitAmount = 0,
    this.creditAmount = 0,
    this.lineDescription,
  });

  final int? accountId;
  final double debitAmount;
  final double creditAmount;
  final String? lineDescription;

  JournalLineRequest copyWith({
    int? accountId,
    double? debitAmount,
    double? creditAmount,
    String? lineDescription,
  }) =>
      JournalLineRequest(
        accountId: accountId ?? this.accountId,
        debitAmount: debitAmount ?? this.debitAmount,
        creditAmount: creditAmount ?? this.creditAmount,
        lineDescription: lineDescription ?? this.lineDescription,
      );

  Map<String, dynamic> toJson() {
    final trimmed = lineDescription?.trim();
    return {
      'accountId': accountId,
      // Both always sent, one of them zero. The service reads them with a
      // null-coalescing helper, so an omitted side would work — but sending
      // both makes the debit-or-credit shape explicit on the wire.
      'debitAmount': debitAmount,
      'creditAmount': creditAmount,
      if (trimmed != null && trimmed.isNotEmpty) 'lineDescription': trimmed,
    };
  }
}

/// One posted line in the general ledger.
///
/// The ledger is append-only: nothing here can be edited, only marked as
/// reconciled against a bank statement.
class LedgerLine {
  const LedgerLine({
    required this.id,
    required this.debitAmount,
    required this.creditAmount,
    required this.isReconciled,
    required this.posted,
    this.transactionDate,
    this.accountId,
    this.accountName,
    this.accountCode,
    this.accountType,
    this.description,
    this.referenceType,
    this.referenceNumber,
    this.reconciliationNotes,
  });

  final int id;
  final double debitAmount;
  final double creditAmount;
  final bool isReconciled;
  final bool posted;
  final String? transactionDate;
  final int? accountId;
  final String? accountName;
  final String? accountCode;
  final String? accountType;
  final String? description;
  final String? referenceType;
  final String? referenceNumber;
  final String? reconciliationNotes;

  bool get isDebit => debitAmount > 0;

  /// The amount, whichever side it fell on.
  double get amount => isDebit ? debitAmount : creditAmount;

  factory LedgerLine.fromJson(Map<String, dynamic> json) => LedgerLine(
        id: (json['id'] as num?)?.toInt() ?? 0,
        debitAmount: (json['debitAmount'] as num?)?.toDouble() ?? 0,
        creditAmount: (json['creditAmount'] as num?)?.toDouble() ?? 0,
        // Same "is" prefix question as the chart of accounts, and this one has
        // no @JsonProperty pinning it — so both spellings are read.
        isReconciled: json['isReconciled'] as bool? ??
            json['reconciled'] as bool? ??
            false,
        posted: json['posted'] as bool? ?? false,
        transactionDate: json['transactionDate'] as String?,
        accountId: (json['accountId'] as num?)?.toInt(),
        accountName: json['accountName'] as String?,
        accountCode: json['accountCode'] as String?,
        accountType: json['accountType'] as String?,
        description: json['description'] as String?,
        referenceType: json['referenceType'] as String?,
        referenceNumber: json['referenceNumber'] as String?,
        reconciliationNotes: json['reconciliationNotes'] as String?,
      );
}
