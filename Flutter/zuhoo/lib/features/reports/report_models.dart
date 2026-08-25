/// The six financial reports.
///
/// All read-only, all derived from the ledger, and all shaped by two questions:
/// **as at** a date (balance sheet, trial balance, ageing) or **between** two
/// dates (profit and loss, cash flow, account ledger). That split decides what
/// the screen asks for before it can run one.
enum ReportPeriodKind {
  /// A snapshot on one date.
  asAt,

  /// A range between two dates.
  between,
}

enum FinancialReport {
  profitLoss(
    'Profit and loss',
    'profit-loss',
    ReportPeriodKind.between,
    'What was earned and spent over a period, and what was left.',
  ),
  balanceSheet(
    'Balance sheet',
    'balance-sheet',
    ReportPeriodKind.asAt,
    'What the company owns and owes on one day.',
  ),
  trialBalance(
    'Trial balance',
    'trial-balance',
    ReportPeriodKind.asAt,
    'Every account and its balance, with the two sides totalled.',
  ),
  cashFlow(
    'Cash flow',
    'cash-flow',
    ReportPeriodKind.between,
    'Money in and money out, and how the balance moved.',
  ),
  ageing(
    'Ageing',
    'ageing',
    ReportPeriodKind.asAt,
    'Which invoices are outstanding, and how late.',
  ),
  accountLedger(
    'Account ledger',
    'ledger',
    ReportPeriodKind.between,
    'Every posting against one account, with opening and closing balances.',
  );

  const FinancialReport(this.label, this.path, this.periodKind, this.blurb);

  final String label;

  /// The path segment under `/company/finance/reports`.
  final String path;

  final ReportPeriodKind periodKind;
  final String blurb;

  /// The account ledger is the one report that also needs an account.
  bool get needsAccount => this == FinancialReport.accountLedger;
}

/// Revenue less expense over a period. Totals only — the web breaks it down by
/// account, which is a table too wide to mean anything on a phone.
class ProfitLoss {
  const ProfitLoss({
    required this.totalRevenue,
    required this.totalExpense,
    required this.netProfit,
    this.periodStart,
    this.periodEnd,
  });

  final double totalRevenue;
  final double totalExpense;
  final double netProfit;
  final String? periodStart;
  final String? periodEnd;

  bool get isProfit => netProfit >= 0;

  /// Profit as a share of revenue, or null when nothing was earned — a margin
  /// on zero revenue is not zero, it is undefined.
  double? get margin {
    if (totalRevenue <= 0) return null;
    return netProfit / totalRevenue;
  }

  factory ProfitLoss.fromJson(Map<String, dynamic> json) => ProfitLoss(
        totalRevenue: (json['totalRevenue'] as num?)?.toDouble() ?? 0,
        totalExpense: (json['totalExpense'] as num?)?.toDouble() ?? 0,
        netProfit: (json['netProfit'] as num?)?.toDouble() ?? 0,
        periodStart: json['periodStart'] as String?,
        periodEnd: json['periodEnd'] as String?,
      );
}

/// What is owned and owed on one date.
class BalanceSheet {
  const BalanceSheet({
    required this.totalAssets,
    required this.totalLiabilities,
    required this.totalEquity,
    required this.balanced,
    required this.outOfBalanceAmount,
    this.asOfDate,
  });

  final double totalAssets;
  final double totalLiabilities;
  final double totalEquity;

  /// Assets should equal liabilities plus equity. When they do not, the
  /// backend's own comment names the two usual causes: an unbalanced entry
  /// posted somewhere, or a fiscal year not yet closed so net income has not
  /// rolled into retained earnings. The screen says both, because knowing
  /// which it is decides what to do about it.
  final bool balanced;

  final double outOfBalanceAmount;
  final String? asOfDate;

  factory BalanceSheet.fromJson(Map<String, dynamic> json) => BalanceSheet(
        totalAssets: (json['totalAssets'] as num?)?.toDouble() ?? 0,
        totalLiabilities: (json['totalLiabilities'] as num?)?.toDouble() ?? 0,
        totalEquity: (json['totalEquity'] as num?)?.toDouble() ?? 0,
        balanced: json['balanced'] as bool? ?? true,
        outOfBalanceAmount:
            (json['outOfBalanceAmount'] as num?)?.toDouble() ?? 0,
        asOfDate: json['asOfDate'] as String?,
      );
}

/// Every account and its balance, with both sides totalled.
class TrialBalance {
  const TrialBalance({
    required this.totalDebit,
    required this.totalCredit,
    this.asOfDate,
    this.accounts = const [],
  });

  final double totalDebit;
  final double totalCredit;
  final String? asOfDate;
  final List<TrialBalanceLine> accounts;

  /// To the paisa, not exactly — these are decimals from a database and an
  /// exact float comparison would report a false difference.
  bool get balances => (totalDebit - totalCredit).abs() < 0.005;

  double get difference => totalDebit - totalCredit;

  factory TrialBalance.fromJson(Map<String, dynamic> json) => TrialBalance(
        totalDebit: (json['totalDebit'] as num?)?.toDouble() ?? 0,
        totalCredit: (json['totalCredit'] as num?)?.toDouble() ?? 0,
        asOfDate: json['asOfDate'] as String?,
        accounts: [
          for (final line in (json['accounts'] as List? ?? const []))
            if (line is Map<String, dynamic>) TrialBalanceLine.fromJson(line),
        ],
      );
}

class TrialBalanceLine {
  const TrialBalanceLine({
    required this.debitBalance,
    required this.creditBalance,
    this.accountId,
    this.accountCode,
    this.accountName,
  });

  final double debitBalance;
  final double creditBalance;
  final int? accountId;
  final String? accountCode;
  final String? accountName;

  factory TrialBalanceLine.fromJson(Map<String, dynamic> json) =>
      TrialBalanceLine(
        debitBalance: (json['debitBalance'] as num?)?.toDouble() ?? 0,
        creditBalance: (json['creditBalance'] as num?)?.toDouble() ?? 0,
        accountId: (json['accountId'] as num?)?.toInt(),
        accountCode: json['accountCode'] as String?,
        accountName: json['accountName'] as String?,
      );
}

/// Money in and out over a period, by category.
class CashFlow {
  const CashFlow({
    required this.openingBalance,
    required this.closingBalance,
    required this.totalInflows,
    required this.totalOutflows,
    required this.netChange,
    this.periodStart,
    this.periodEnd,
    this.lines = const [],
  });

  final double openingBalance;
  final double closingBalance;
  final double totalInflows;
  final double totalOutflows;
  final double netChange;
  final String? periodStart;
  final String? periodEnd;
  final List<CashFlowLine> lines;

  factory CashFlow.fromJson(Map<String, dynamic> json) => CashFlow(
        openingBalance: (json['openingBalance'] as num?)?.toDouble() ?? 0,
        closingBalance: (json['closingBalance'] as num?)?.toDouble() ?? 0,
        totalInflows: (json['totalInflows'] as num?)?.toDouble() ?? 0,
        totalOutflows: (json['totalOutflows'] as num?)?.toDouble() ?? 0,
        netChange: (json['netChange'] as num?)?.toDouble() ?? 0,
        periodStart: json['periodStart'] as String?,
        periodEnd: json['periodEnd'] as String?,
        lines: [
          for (final line in (json['lines'] as List? ?? const []))
            if (line is Map<String, dynamic>) CashFlowLine.fromJson(line),
        ],
      );
}

class CashFlowLine {
  const CashFlowLine({
    required this.category,
    required this.inflow,
    required this.outflow,
  });

  final String category;
  final double inflow;
  final double outflow;

  double get net => inflow - outflow;

  factory CashFlowLine.fromJson(Map<String, dynamic> json) => CashFlowLine(
        category: json['category'] as String? ?? '',
        inflow: (json['inflow'] as num?)?.toDouble() ?? 0,
        outflow: (json['outflow'] as num?)?.toDouble() ?? 0,
      );
}

/// What is outstanding, and how late.
class Ageing {
  const Ageing({
    required this.current,
    required this.days1to30,
    required this.days31to60,
    required this.days61to90,
    required this.over90,
    required this.totalOutstanding,
    this.asOfDate,
    this.lines = const [],
  });

  /// Not yet due.
  final double current;

  final double days1to30;
  final double days31to60;
  final double days61to90;
  final double over90;
  final double totalOutstanding;
  final String? asOfDate;
  final List<AgeingLine> lines;

  /// The buckets in order, for the bar. Named rather than positional because
  /// getting two of these the wrong way round would be invisible.
  List<({String label, double amount})> get buckets => [
        (label: 'Current', amount: current),
        (label: '1–30', amount: days1to30),
        (label: '31–60', amount: days31to60),
        (label: '61–90', amount: days61to90),
        (label: '90+', amount: over90),
      ];

  /// Everything past its due date. The figure that actually matters.
  double get overdue => days1to30 + days31to60 + days61to90 + over90;

  factory Ageing.fromJson(Map<String, dynamic> json) => Ageing(
        current: (json['current'] as num?)?.toDouble() ?? 0,
        days1to30: (json['days1to30'] as num?)?.toDouble() ?? 0,
        days31to60: (json['days31to60'] as num?)?.toDouble() ?? 0,
        days61to90: (json['days61to90'] as num?)?.toDouble() ?? 0,
        over90: (json['over90'] as num?)?.toDouble() ?? 0,
        totalOutstanding:
            (json['totalOutstanding'] as num?)?.toDouble() ?? 0,
        asOfDate: json['asOfDate'] as String?,
        lines: [
          for (final line in (json['lines'] as List? ?? const []))
            if (line is Map<String, dynamic>) AgeingLine.fromJson(line),
        ],
      );
}

/// One outstanding document on an ageing report.
///
/// Serves both directions. Receivables ageing sends `invoiceId`,
/// `invoiceNumber` and `clientName`; payables ageing sends `billId`,
/// `billNumber` and `vendorName` against an otherwise identical shape. Rather
/// than two near-identical classes, this one reads either — [documentId],
/// [reference] and [counterparty] are named for what they mean rather than for
/// which report they came from.
class AgeingLine {
  const AgeingLine({
    required this.balanceAmount,
    required this.daysOverdue,
    this.documentId,
    this.reference,
    this.counterparty,
    this.dueDate,
    this.bucket,
  });

  final double balanceAmount;

  /// Zero or negative when it is not yet due.
  final int daysOverdue;

  /// The invoice or the bill.
  final int? documentId;

  /// Its number.
  final String? reference;

  /// The client who owes it, or the vendor who is owed it.
  final String? counterparty;

  final String? dueDate;
  final String? bucket;

  bool get isOverdue => daysOverdue > 0;

  factory AgeingLine.fromJson(Map<String, dynamic> json) => AgeingLine(
        balanceAmount: (json['balanceAmount'] as num?)?.toDouble() ?? 0,
        daysOverdue: (json['daysOverdue'] as num?)?.toInt() ?? 0,
        documentId: (json['invoiceId'] as num?)?.toInt() ??
            (json['billId'] as num?)?.toInt(),
        reference: json['invoiceNumber'] as String? ??
            json['billNumber'] as String?,
        counterparty:
            json['clientName'] as String? ?? json['vendorName'] as String?,
        dueDate: json['dueDate'] as String?,
        bucket: json['bucket'] as String?,
      );
}

/// One account's postings over a period, with the balance either side.
class AccountLedgerReport {
  const AccountLedgerReport({
    required this.openingBalance,
    required this.closingBalance,
    this.accountId,
    this.accountCode,
    this.accountName,
    this.periodStart,
    this.periodEnd,
    this.entries = const [],
  });

  final double openingBalance;
  final double closingBalance;
  final int? accountId;
  final String? accountCode;
  final String? accountName;
  final String? periodStart;
  final String? periodEnd;

  /// The same shape the general ledger returns, so the module's own
  /// `LedgerLine` parses them.
  final List<Map<String, dynamic>> entries;

  double get movement => closingBalance - openingBalance;

  factory AccountLedgerReport.fromJson(Map<String, dynamic> json) =>
      AccountLedgerReport(
        openingBalance: (json['openingBalance'] as num?)?.toDouble() ?? 0,
        closingBalance: (json['closingBalance'] as num?)?.toDouble() ?? 0,
        accountId: (json['accountId'] as num?)?.toInt(),
        accountCode: json['accountCode'] as String?,
        accountName: json['accountName'] as String?,
        periodStart: json['periodStart'] as String?,
        periodEnd: json['periodEnd'] as String?,
        entries: [
          for (final entry in (json['entries'] as List? ?? const []))
            if (entry is Map<String, dynamic>) entry,
        ],
      );
}
