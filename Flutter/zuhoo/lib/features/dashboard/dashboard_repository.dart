import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import 'dashboard_models.dart';

/// The dashboard endpoints.
///
/// Two audiences behind one controller: `/summary`, `/recommendations` and
/// `/insights` answer for the signed-in company, while `/platform-summary` and
/// `/platform-metrics-history` are for the people who run the platform. A
/// tenant user calling the platform pair gets a 403, and vice versa.
class DashboardRepository {
  DashboardRepository(this._api);

  final ApiClient _api;

  static const _base = '/dashboard';

  /// Everything counted at once. Both dates are optional; without them the
  /// backend picks its own window.
  Future<DashboardSummary> summary({String? from, String? to}) async {
    final json = await _api.get<Map<String, dynamic>>(
      '$_base/summary',
      query: {'from': ?from, 'to': ?to},
    );
    return DashboardSummary.fromJson(json);
  }

  /// What the system thinks is worth acting on. A bare list.
  Future<List<Recommendation>> recommendations() async {
    final list = await _api.get<List<dynamic>>('$_base/recommendations');
    return list
        .whereType<Map<String, dynamic>>()
        .map(Recommendation.fromJson)
        .toList(growable: false);
  }

  /// The assistant's read on the figures. Costs a provider call, so it is
  /// asked for on demand rather than loaded with the rest of the screen.
  Future<DashboardInsights> insights() async {
    final json = await _api.get<Map<String, dynamic>>('$_base/insights');
    return DashboardInsights.fromJson(json);
  }

  Future<PlatformSummary> platformSummary() async {
    final json =
        await _api.get<Map<String, dynamic>>('$_base/platform-summary');
    return PlatformSummary.fromJson(json);
  }

  /// The last [days] days of platform figures, from the nightly snapshots.
  Future<List<PlatformMetricsPoint>> platformHistory({int days = 30}) async {
    final list = await _api.get<List<dynamic>>(
      '$_base/platform-metrics-history',
      query: {'days': days},
    );
    return list
        .whereType<Map<String, dynamic>>()
        .map(PlatformMetricsPoint.fromJson)
        .toList(growable: false);
  }
}

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(ref.watch(apiClientProvider)),
);

final dashboardSummaryProvider =
    FutureProvider.autoDispose<DashboardSummary>((ref) {
  ref.watch(currentUserProvider);
  return ref.read(dashboardRepositoryProvider).summary();
});

final recommendationsProvider =
    FutureProvider.autoDispose<List<Recommendation>>((ref) {
  ref.watch(currentUserProvider);
  return ref.read(dashboardRepositoryProvider).recommendations();
});

/// Not watched by the screen on load — it is asked for when somebody presses
/// for it, because every call spends a provider request.
final dashboardInsightsProvider =
    FutureProvider.autoDispose<DashboardInsights>((ref) {
  return ref.read(dashboardRepositoryProvider).insights();
});

final platformSummaryProvider =
    FutureProvider.autoDispose<PlatformSummary>((ref) {
  ref.watch(currentUserProvider);
  return ref.read(dashboardRepositoryProvider).platformSummary();
});

final platformHistoryProvider =
    FutureProvider.autoDispose<List<PlatformMetricsPoint>>((ref) {
  return ref.read(dashboardRepositoryProvider).platformHistory();
});
