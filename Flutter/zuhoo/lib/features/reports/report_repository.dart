import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../shared/util/formatters.dart';
import 'report_models.dart';

/// The six financial reports.
///
/// Each is a single GET with date parameters and no state of its own, so there
/// is no controller here — just a request keyed on what was asked for.
class ReportRepository {
  ReportRepository(this._api);

  final ApiClient _api;

  static const _base = '/company/finance/reports';

  Future<ProfitLoss> profitLoss(String startDate, String endDate) async {
    final json = await _api.get<Map<String, dynamic>>(
      '$_base/profit-loss',
      query: {'startDate': startDate, 'endDate': endDate},
    );
    return ProfitLoss.fromJson(json);
  }

  Future<BalanceSheet> balanceSheet(String asOfDate) async {
    final json = await _api.get<Map<String, dynamic>>(
      '$_base/balance-sheet',
      query: {'asOfDate': asOfDate},
    );
    return BalanceSheet.fromJson(json);
  }

  Future<TrialBalance> trialBalance(String asOfDate) async {
    final json = await _api.get<Map<String, dynamic>>(
      '$_base/trial-balance',
      query: {'asOfDate': asOfDate},
    );
    return TrialBalance.fromJson(json);
  }

  Future<CashFlow> cashFlow(String startDate, String endDate) async {
    final json = await _api.get<Map<String, dynamic>>(
      '$_base/cash-flow',
      query: {'startDate': startDate, 'endDate': endDate},
    );
    return CashFlow.fromJson(json);
  }

  Future<Ageing> ageing(String asOfDate) async {
    final json = await _api.get<Map<String, dynamic>>(
      '$_base/ageing',
      query: {'asOfDate': asOfDate},
    );
    return Ageing.fromJson(json);
  }

  Future<AccountLedgerReport> accountLedger(
    int accountId,
    String startDate,
    String endDate,
  ) async {
    final json = await _api.get<Map<String, dynamic>>(
      '$_base/ledger',
      query: {
        'accountId': accountId,
        'startDate': startDate,
        'endDate': endDate,
      },
    );
    return AccountLedgerReport.fromJson(json);
  }
}

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => ReportRepository(ref.watch(apiClientProvider)),
);

/// What a report was asked for: which one, over what dates, and for which
/// account where that applies.
///
/// A value type so the provider can be keyed on it — changing any part of it
/// is a different report, and asking again for the same thing reuses the
/// answer rather than re-running it.
class ReportQuery {
  const ReportQuery({
    required this.report,
    required this.start,
    required this.end,
    this.accountId,
  });

  final FinancialReport report;

  /// For an as-at report, [end] is the date and [start] is ignored. Keeping
  /// both on one class avoids two nearly-identical query types.
  final String start;
  final String end;

  final int? accountId;

  /// The date an as-at report is taken on.
  String get asAt => end;

  @override
  bool operator ==(Object other) =>
      other is ReportQuery &&
      other.report == report &&
      other.start == start &&
      other.end == end &&
      other.accountId == accountId;

  @override
  int get hashCode => Object.hash(report, start, end, accountId);
}

/// Runs one report.
///
/// Returns the report object untyped — each report has its own shape and the
/// screen switches on which one was asked for. Typing this any harder would
/// mean six providers that differ only in the line that calls the endpoint.
final reportProvider =
    FutureProvider.autoDispose.family<Object, ReportQuery>((ref, query) {
  final repo = ref.read(reportRepositoryProvider);
  return switch (query.report) {
    FinancialReport.profitLoss => repo.profitLoss(query.start, query.end),
    FinancialReport.balanceSheet => repo.balanceSheet(query.asAt),
    FinancialReport.trialBalance => repo.trialBalance(query.asAt),
    FinancialReport.cashFlow => repo.cashFlow(query.start, query.end),
    FinancialReport.ageing => repo.ageing(query.asAt),
    FinancialReport.accountLedger => repo.accountLedger(
        query.accountId ?? 0,
        query.start,
        query.end,
      ),
  };
});

/// A sensible starting period: this month so far, or today for an as-at.
ReportQuery defaultQuery(FinancialReport report, {DateTime? now}) {
  final today = now ?? DateTime.now();
  return ReportQuery(
    report: report,
    start: Fmt.isoDate(DateTime(today.year, today.month)),
    end: Fmt.isoDate(today),
  );
}
