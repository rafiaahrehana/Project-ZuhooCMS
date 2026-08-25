import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import 'assets_periods_models.dart';

/// Closing the books, and writing down what the company owns.
class ClosingRepository {
  ClosingRepository(this._api);

  final ApiClient _api;

  static const _periods = '/company/finance/accounting-periods';
  static const _assets = '/company/finance/fixed-assets';

  // ── Periods ─────────────────────────────────────────────────

  /// Every fiscal year the company has, with how far through closing each is.
  /// A bare list.
  Future<List<FiscalYear>> fiscalYears() async {
    final list = await _api.get<List<dynamic>>('$_periods/fiscal-years');
    return list
        .whereType<Map<String, dynamic>>()
        .map(FiscalYear.fromJson)
        .toList(growable: false);
  }

  /// The periods in one year. `fiscalYear` is **required** — there is no
  /// "all periods" call.
  Future<List<AccountingPeriod>> periods(int fiscalYear) async {
    final list = await _api.get<List<dynamic>>(
      _periods,
      query: {'fiscalYear': fiscalYear},
    );
    return list
        .whereType<Map<String, dynamic>>()
        .map(AccountingPeriod.fromJson)
        .toList(growable: false);
  }

  /// Shuts a period so nothing more can be posted into it.
  Future<AccountingPeriod> closePeriod(int id) async {
    final json = await _api.post<Map<String, dynamic>>('$_periods/$id/close');
    return AccountingPeriod.fromJson(json);
  }

  Future<AccountingPeriod> reopenPeriod(int id) async {
    final json = await _api.post<Map<String, dynamic>>('$_periods/$id/reopen');
    return AccountingPeriod.fromJson(json);
  }

  /// Rolls net income into retained earnings and shuts the year.
  ///
  /// The fiscal year is a **query parameter**, and the response is empty. This
  /// is the step whose absence makes a balance sheet not balance — the backend
  /// says as much in its own comment on `BalanceSheetReport`.
  Future<void> closeFiscalYear(int fiscalYear) =>
      _api.post<dynamic>('$_periods/close-fiscal-year?fiscalYear=$fiscalYear');

  // ── Fixed assets ────────────────────────────────────────────

  Future<PagedResponse<FixedAsset>> assets({int page = 0, int size = 30}) =>
      _api.getPaged(_assets, FixedAsset.fromJson, page: page, size: size);

  Future<FixedAsset> createAsset(FixedAssetRequest request) async {
    final json =
        await _api.post<Map<String, dynamic>>(_assets, request.toJson());
    return FixedAsset.fromJson(json);
  }

  /// Writes it off the books. There is no undisposing.
  Future<FixedAsset> disposeAsset(int id) async {
    final json = await _api.post<Map<String, dynamic>>('$_assets/$id/dispose');
    return FixedAsset.fromJson(json);
  }

  /// Depreciates every asset for one month at once. Both parameters are
  /// **query parameters**, and both are required.
  Future<DepreciationRun> runDepreciation(int year, int month) async {
    final json = await _api.post<Map<String, dynamic>>(
      '$_assets/run-depreciation?year=$year&month=$month',
    );
    return DepreciationRun.fromJson(json);
  }

  /// Every month that has been run. A bare list.
  Future<List<DepreciationRun>> depreciationRuns() async {
    final list = await _api.get<List<dynamic>>('$_assets/depreciation-runs');
    return list
        .whereType<Map<String, dynamic>>()
        .map(DepreciationRun.fromJson)
        .toList(growable: false);
  }
}

final closingRepositoryProvider = Provider<ClosingRepository>(
  (ref) => ClosingRepository(ref.watch(apiClientProvider)),
);

final fiscalYearsProvider = FutureProvider<List<FiscalYear>>((ref) {
  ref.watch(currentUserProvider);
  return ref.read(closingRepositoryProvider).fiscalYears();
});

/// Which year's periods are showing. Defaults to whatever year it is now,
/// which is right far more often than not.
class FiscalYearController extends Notifier<int> {
  @override
  int build() => DateTime.now().year;

  void set(int year) {
    if (state == year) return;
    state = year;
  }
}

final selectedFiscalYearProvider =
    NotifierProvider<FiscalYearController, int>(FiscalYearController.new);

class PeriodsController extends AsyncNotifier<List<AccountingPeriod>> {
  @override
  Future<List<AccountingPeriod>> build() {
    ref.watch(currentUserProvider);
    ref.watch(selectedFiscalYearProvider);
    return _load();
  }

  Future<List<AccountingPeriod>> _load() => ref
      .read(closingRepositoryProvider)
      .periods(ref.read(selectedFiscalYearProvider));

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  void apply(AccountingPeriod updated) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current) if (row.id == updated.id) updated else row,
    ]);
  }
}

final periodsProvider =
    AsyncNotifierProvider<PeriodsController, List<AccountingPeriod>>(
  PeriodsController.new,
);

class FixedAssetsController extends AsyncNotifier<List<FixedAsset>> {
  @override
  Future<List<FixedAsset>> build() {
    ref.watch(currentUserProvider);
    return _load();
  }

  Future<List<FixedAsset>> _load() async {
    final page = await ref.read(closingRepositoryProvider).assets();
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  void apply(FixedAsset updated) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current) if (row.id == updated.id) updated else row,
    ]);
  }
}

final fixedAssetsProvider =
    AsyncNotifierProvider<FixedAssetsController, List<FixedAsset>>(
  FixedAssetsController.new,
);

final depreciationRunsProvider =
    FutureProvider.autoDispose<List<DepreciationRun>>(
  (ref) => ref.read(closingRepositoryProvider).depreciationRuns(),
);
