import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import 'location_models.dart';

/// The global country/division/district reference hierarchy every address
/// field in the app picks from. Reading it needs no permission at all — the
/// backend leaves every GET here open — but changing it is platform staff
/// only ([platformUserRoles], same as everywhere else in this console).
class LocationRepository {
  LocationRepository(this._api);

  final ApiClient _api;

  static const _base = '/locations';

  Future<List<GeoNode>> countries() async {
    final list = await _api.get<List<dynamic>>('$_base/countries');
    return list.whereType<Map<String, dynamic>>().map(GeoNode.fromJson).toList();
  }

  /// A country's LEVEL1 divisions. Country ids and location ids are separate
  /// sequences that can collide, so this — never [children] — is how a
  /// country's own top level is fetched.
  Future<List<GeoNode>> divisionsForCountry(int countryId) async {
    final list = await _api
        .get<List<dynamic>>('$_base/countries/$countryId/divisions');
    return list.whereType<Map<String, dynamic>>().map(GeoNode.fromJson).toList();
  }

  /// LEVEL2-4 children of a LEVEL1-3 parent. Never pass a country id here.
  Future<List<GeoNode>> children(int parentId) async {
    final list = await _api.get<List<dynamic>>('$_base/children/$parentId');
    return list.whereType<Map<String, dynamic>>().map(GeoNode.fromJson).toList();
  }

  Future<GeoNode> create(LocationCreateRequest request) async {
    final json = await _api.post<Map<String, dynamic>>(_base, request.toJson());
    return GeoNode.fromJson(json);
  }

  Future<GeoNode> update(int id, LocationUpdateRequest request) async {
    final json =
        await _api.put<Map<String, dynamic>>('$_base/$id', request.toJson());
    return GeoNode.fromJson(json);
  }

  Future<void> delete(int id) => _api.delete<dynamic>('$_base/$id');
}

final locationRepositoryProvider = Provider<LocationRepository>(
  (ref) => LocationRepository(ref.watch(apiClientProvider)),
);

final countriesProvider = FutureProvider<List<GeoNode>>(
  (ref) => ref.read(locationRepositoryProvider).countries(),
);

/// Children of one node. A country's own top level goes through
/// [LocationRepository.divisionsForCountry] rather than [LocationRepository.
/// children] — [parentIsCountry] is what picks between them. Family, not a
/// single global list, so drilling into one branch never invalidates a
/// sibling already loaded.
final locationChildrenProvider = FutureProvider.family
    .autoDispose<List<GeoNode>, ({int parentId, bool parentIsCountry})>(
        (ref, key) {
  final repo = ref.read(locationRepositoryProvider);
  return key.parentIsCountry
      ? repo.divisionsForCountry(key.parentId)
      : repo.children(key.parentId);
});
