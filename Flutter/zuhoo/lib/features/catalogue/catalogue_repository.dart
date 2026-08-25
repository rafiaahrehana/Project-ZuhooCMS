import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import '../requests/request_models.dart' show CreateServicePackageRequest;
import 'catalogue_models.dart';

/// What the company sells: services, the templates they are built from, the
/// packages that bundle them, and who is subscribed to what.
///
/// Everything here is soft-deleted rather than removed — `delete` on both
/// services and templates calls `softDelete()`, so a row that something already
/// points at keeps its history. Toggling is still the gentler option and the
/// screens offer it first.
class CatalogueRepository {
  CatalogueRepository(this._api);

  final ApiClient _api;

  // ── Services ────────────────────────────────────────────────

  /// Every service, retired ones included — this is the admin list. The public
  /// `/services/active` list is what the request flow reads.
  Future<PagedResponse<ServiceListing>> services({
    int? categoryId,
    int page = 0,
    int size = 30,
  }) =>
      _api.getPaged(
        '/services',
        ServiceListing.fromJson,
        page: page,
        size: size,
        query: {if (categoryId != null) 'categoryId': categoryId},
      );

  Future<ServiceListing> createService(ServiceListingRequest request) async {
    final json =
        await _api.post<Map<String, dynamic>>('/services', request.toJson());
    return ServiceListing.fromJson(json);
  }

  /// Sends all nine flags whether or not any changed — see
  /// [ServiceListingRequest] for why leaving one out switches it off.
  Future<ServiceListing> updateService(
    int id,
    ServiceListingRequest request,
  ) async {
    final json = await _api.put<Map<String, dynamic>>(
      '/services/$id',
      request.toJson(),
    );
    return ServiceListing.fromJson(json);
  }

  Future<ServiceListing> toggleService(int id) async {
    final json = await _api.patch<Map<String, dynamic>>('/services/$id/toggle');
    return ServiceListing.fromJson(json);
  }

  /// Soft delete. The row stops appearing but anything already ordered against
  /// it still resolves.
  ///
  /// `deleteText` rather than `delete`: this endpoint declares
  /// `ResponseEntity<String>` and returns a bare confirmation sentence, which
  /// is not JSON and fails to decode as any.
  Future<void> deleteService(int id) => _api.deleteText('/services/$id');

  // ── Templates ───────────────────────────────────────────────

  /// `activeOnly` defaults to **true** server-side, so the admin list passes
  /// false explicitly — otherwise a retired template becomes invisible and
  /// there is no way to bring it back.
  Future<PagedResponse<ServiceTemplate>> templates({
    int page = 0,
    int size = 30,
  }) =>
      _api.getPaged(
        '/v1/service-templates',
        ServiceTemplate.fromJson,
        page: page,
        size: size,
        query: const {'activeOnly': false},
      );

  Future<ServiceTemplate> createTemplate(ServiceTemplateRequest request) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/service-templates',
      request.toJson(),
    );
    return ServiceTemplate.fromJson(json);
  }

  Future<ServiceTemplate> updateTemplate(
    int id,
    ServiceTemplateRequest request,
  ) async {
    final json = await _api.put<Map<String, dynamic>>(
      '/v1/service-templates/$id',
      request.toJson(),
    );
    return ServiceTemplate.fromJson(json);
  }

  Future<void> deleteTemplate(int id) =>
      _api.delete<dynamic>('/v1/service-templates/$id');

  // ── Packages ────────────────────────────────────────────────

  Future<PagedResponse<ServicePackage>> packages({
    int page = 0,
    int size = 30,
  }) =>
      _api.getPaged(
        '/packages',
        ServicePackage.fromJson,
        page: page,
        size: size,
      );

  /// Reuses the create DTO, which is what the endpoint takes. Four of its
  /// fields are assigned unconditionally — see [CreateServicePackageRequest].
  Future<ServicePackage> updatePackage(
    int id,
    CreateServicePackageRequest request,
  ) async {
    final json = await _api.put<Map<String, dynamic>>(
      '/packages/$id',
      request.toJson(),
    );
    return ServicePackage.fromJson(json);
  }

  Future<ServicePackage> togglePackage(int id) async {
    final json = await _api.patch<Map<String, dynamic>>('/packages/$id/toggle');
    return ServicePackage.fromJson(json);
  }

  // ── Subscriptions ───────────────────────────────────────────

  Future<PagedResponse<PackageSubscription>> subscriptions({
    String? status,
    int page = 0,
    int size = 30,
  }) =>
      _api.getPaged(
        '/packages/subscriptions',
        PackageSubscription.fromJson,
        page: page,
        size: size,
        query: {if (status != null) 'status': status},
      );

  /// Puts a client on a package. Staff pass [clientId]; a client subscribing
  /// themselves omits it and the backend reads it from the token.
  Future<PackageSubscription> subscribe({
    required int packageId,
    int? clientId,
    bool? autoRenew,
  }) async {
    final json = await _api.post<Map<String, dynamic>>('/packages/subscribe', {
      'packageId': packageId,
      if (clientId != null) 'clientId': clientId,
      if (autoRenew != null) 'autoRenew': autoRenew,
    });
    return PackageSubscription.fromJson(json);
  }

  /// Confirms payment on a PENDING_PAYMENT subscription. In production a
  /// payment webhook does this; the app offers it because there is no other way
  /// to clear a subscription that was taken manually.
  Future<PackageSubscription> activateSubscription(int id) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '/packages/subscriptions/$id/activate',
    );
    return PackageSubscription.fromJson(json);
  }

  /// Pauses it. The reason is a **query parameter**, not a body — the
  /// controller takes `@RequestParam String reason`, so sending it as JSON
  /// would be silently dropped. `patch` has no query argument, so it goes on
  /// the path, as it does everywhere else in the app.
  Future<PackageSubscription> suspendSubscription(
    int id,
    String? reason,
  ) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '/packages/subscriptions/$id/suspend${_reason(reason)}',
    );
    return PackageSubscription.fromJson(json);
  }

  Future<PackageSubscription> reactivateSubscription(int id) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '/packages/subscriptions/$id/reactivate',
    );
    return PackageSubscription.fromJson(json);
  }

  /// Ends it for good. Same query-parameter shape as suspend.
  Future<PackageSubscription> cancelSubscription(int id, String? reason) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '/packages/subscriptions/$id/cancel${_reason(reason)}',
    );
    return PackageSubscription.fromJson(json);
  }

  /// `?reason=…`, or nothing at all. The parameter is optional server-side, and
  /// an empty one would store a blank reason rather than none.
  String _reason(String? reason) {
    final trimmed = reason?.trim();
    if (trimmed == null || trimmed.isEmpty) return '';
    return '?reason=${Uri.encodeQueryComponent(trimmed)}';
  }
}

final catalogueRepositoryProvider = Provider<CatalogueRepository>(
  (ref) => CatalogueRepository(ref.watch(apiClientProvider)),
);

/// One controller shape, four times over. Each holds a plain list rather than a
/// paged loader: a company has tens of services and packages, not thousands,
/// and the first page covers it.
class ServicesController extends AsyncNotifier<List<ServiceListing>> {
  @override
  Future<List<ServiceListing>> build() {
    ref.watch(currentUserProvider);
    return _load();
  }

  Future<List<ServiceListing>> _load() async {
    final page = await ref.read(catalogueRepositoryProvider).services();
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  void apply(ServiceListing updated) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current) if (row.id == updated.id) updated else row,
    ]);
  }

  void remove(int id) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current)
        if (row.id != id) row,
    ]);
  }
}

final servicesProvider =
    AsyncNotifierProvider<ServicesController, List<ServiceListing>>(
  ServicesController.new,
);

class TemplatesController extends AsyncNotifier<List<ServiceTemplate>> {
  @override
  Future<List<ServiceTemplate>> build() {
    ref.watch(currentUserProvider);
    return _load();
  }

  Future<List<ServiceTemplate>> _load() async {
    final page = await ref.read(catalogueRepositoryProvider).templates();
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  void apply(ServiceTemplate updated) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current) if (row.id == updated.id) updated else row,
    ]);
  }

  void remove(int id) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current)
        if (row.id != id) row,
    ]);
  }
}

final templatesProvider =
    AsyncNotifierProvider<TemplatesController, List<ServiceTemplate>>(
  TemplatesController.new,
);

class PackagesController extends AsyncNotifier<List<ServicePackage>> {
  @override
  Future<List<ServicePackage>> build() {
    ref.watch(currentUserProvider);
    return _load();
  }

  Future<List<ServicePackage>> _load() async {
    final page = await ref.read(catalogueRepositoryProvider).packages();
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  void apply(ServicePackage updated) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current) if (row.id == updated.id) updated else row,
    ]);
  }
}

final packagesProvider =
    AsyncNotifierProvider<PackagesController, List<ServicePackage>>(
  PackagesController.new,
);

class SubscriptionsController extends AsyncNotifier<List<PackageSubscription>> {
  @override
  Future<List<PackageSubscription>> build() {
    ref.watch(currentUserProvider);
    return _load();
  }

  Future<List<PackageSubscription>> _load() async {
    final page = await ref.read(catalogueRepositoryProvider).subscriptions();
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  void apply(PackageSubscription updated) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current) if (row.id == updated.id) updated else row,
    ]);
  }
}

final subscriptionsProvider =
    AsyncNotifierProvider<SubscriptionsController, List<PackageSubscription>>(
  SubscriptionsController.new,
);
