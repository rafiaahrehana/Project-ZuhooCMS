import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import '../../shared/paged_controller.dart';
import 'itam_models.dart';

/// IT asset management.
///
/// Three endpoints families that live nowhere near each other: hardware is
/// `/hr/assets`, software is `/v1/itam/software`, and offboarding is
/// `/v1/company/offboarding/checklist`. Only one of the three is under an
/// `itam` path at all — worth stating, because the obvious guess is wrong for
/// two of them.
///
/// Creating, editing and deleting hardware now live here too, brought over
/// from the web app for parity — an earlier version of this file deliberately
/// left them out on the grounds that they were desk work.
///
/// Still absent: **asset import**, which is a CSV upload against a downloadable
/// template and has no sensible phone equivalent.
class ItamRepository {
  ItamRepository(this._api);

  final ApiClient _api;

  static const _assets = '/hr/assets';
  static const _software = '/v1/itam/software';
  static const _offboarding = '/v1/company/offboarding/checklist';

  // ── Hardware ────────────────────────────────────────────────

  Future<PagedResponse<Asset>> assets({int page = 0, int size = 20}) =>
      _api.getPaged(_assets, Asset.fromJson, page: page, size: size);

  Future<Asset> asset(int id) async {
    final json = await _api.get<Map<String, dynamic>>('$_assets/$id');
    return Asset.fromJson(json);
  }

  Future<Asset> createAsset(AssetRequest request) async {
    final json =
        await _api.post<Map<String, dynamic>>(_assets, request.toJson());
    return Asset.fromJson(json);
  }

  /// `PUT`, but a sparse update underneath — see [AssetRequest].
  Future<Asset> updateAsset(int id, AssetRequest request) async {
    final json = await _api.put<Map<String, dynamic>>(
      '$_assets/$id',
      request.toJson(),
    );
    return Asset.fromJson(json);
  }

  /// Soft-delete.
  ///
  /// `deleteText`, not `delete`: this endpoint is declared
  /// `ResponseEntity<String>` and answers with the bare word "Deleted
  /// successfully", which is not JSON and fails to decode as any.
  ///
  /// Refused for an asset that is currently assigned — the backend says so in
  /// the message, and that message is worth showing rather than replacing.
  Future<void> deleteAsset(int id) => _api.deleteText('$_assets/$id');

  /// Hands a machine to somebody. The employee is a **path segment**, not a
  /// body or a query — `PATCH /hr/assets/{id}/assign/{employeeId}`.
  Future<Asset> assignAsset(int id, int employeeId) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_assets/$id/assign/$employeeId',
    );
    return Asset.fromJson(json);
  }

  Future<Asset> unassignAsset(int id) async {
    final json = await _api.patch<Map<String, dynamic>>('$_assets/$id/unassign');
    return Asset.fromJson(json);
  }

  /// Sends a machine for repair, or brings it back. A query parameter, so a
  /// JSON body would be accepted and ignored.
  Future<Asset> setMaintenance(int id, bool underMaintenance) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_assets/$id/maintenance?underMaintenance=$underMaintenance',
    );
    return Asset.fromJson(json);
  }

  // ── Software ────────────────────────────────────────────────

  Future<PagedResponse<SoftwareLicense>> licenses({
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        _software,
        SoftwareLicense.fromJson,
        page: page,
        size: size,
      );

  /// Registers a licence. Nine of its fields are required — see
  /// [SoftwareLicenseRequest] — so most of the form is mandatory.
  Future<SoftwareLicense> createLicense(SoftwareLicenseRequest request) async {
    final json =
        await _api.post<Map<String, dynamic>>(_software, request.toJson());
    return SoftwareLicense.fromJson(json);
  }

  Future<void> assignSeat(int licenseId, int employeeId) => _api.post<dynamic>(
        '$_software/$licenseId/assign-seat?employeeId=$employeeId',
      );

  Future<void> releaseSeat(int licenseId, int employeeId) => _api.post<dynamic>(
        '$_software/$licenseId/release-seat?employeeId=$employeeId',
      );

  // ── Offboarding ─────────────────────────────────────────────

  /// Read as a page, not a bare list: the endpoint returns
  /// `Page<OffboardingChecklistResponse>`, so casting the body to a List threw
  /// and the whole tab failed to load. One generous page rather than paging —
  /// a company has a handful of people leaving at a time, not fifty.
  Future<List<OffboardingChecklist>> checklists() async {
    final page = await _api.getPaged(
      _offboarding,
      OffboardingChecklist.fromJson,
      page: 0,
      size: 50,
    );
    return page.content;
  }

  /// Opens a leaver's checklist. The five steps start unticked.
  Future<OffboardingChecklist> createChecklist(
    OffboardingChecklistRequest request,
  ) async {
    final json = await _api.post<Map<String, dynamic>>(
      _offboarding,
      request.toJson(),
    );
    return OffboardingChecklist.fromJson(json);
  }

  /// Ticks one step off.
  ///
  /// Every step has its own endpoint and they all take the same body, so the
  /// step's path segment is carried on [OffboardingStep] rather than switched
  /// on here — adding a sixth step should not mean editing a method.
  ///
  /// There is no un-tick: the backend exposes no endpoint to clear a step, so
  /// the UI must not offer a toggle that can only travel one way.
  Future<OffboardingChecklist> completeStep(
    int checklistId,
    String stepPath, {
    String? notes,
  }) async {
    final trimmed = notes?.trim();
    final json = await _api.patch<Map<String, dynamic>>(
      '$_offboarding/$checklistId/$stepPath',
      {if (trimmed != null && trimmed.isNotEmpty) 'notes': trimmed},
    );
    return OffboardingChecklist.fromJson(json);
  }
}

final itamRepositoryProvider = Provider<ItamRepository>(
  (ref) => ItamRepository(ref.watch(apiClientProvider)),
);

class AssetsController extends AsyncNotifier<PagedState<Asset>>
    with PagedLoader<Asset> {
  @override
  Future<PagedState<Asset>> build() {
    ref.watch(currentUserProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<Asset>> fetchPage(int page) =>
      ref.read(itamRepositoryProvider).assets(page: page);

  /// Swaps the row in place after an action rather than reloading, so someone
  /// working down a list of machines does not lose their position each time.
  void apply(Asset updated) =>
      replaceItem((asset) => asset.id == updated.id, updated);

  Future<Asset> create(AssetRequest request) async {
    final created = await ref.read(itamRepositoryProvider).createAsset(request);
    await refresh();
    return created;
  }

  /// Returns the server's version so the detail screen — which holds its own
  /// copy of the asset rather than watching a provider — can adopt it.
  Future<Asset> updateItem(int id, AssetRequest request) async {
    final updated =
        await ref.read(itamRepositoryProvider).updateAsset(id, request);
    apply(updated);
    return updated;
  }

  /// Refused by the backend while the asset is still assigned to somebody, so
  /// the row is only dropped once the call has actually succeeded.
  Future<void> delete(int id) async {
    await ref.read(itamRepositoryProvider).deleteAsset(id);
    removeItem((asset) => asset.id == id);
  }
}

final assetsProvider = AsyncNotifierProvider<AssetsController, PagedState<Asset>>(
  AssetsController.new,
);

class LicensesController extends AsyncNotifier<PagedState<SoftwareLicense>>
    with PagedLoader<SoftwareLicense> {
  @override
  Future<PagedState<SoftwareLicense>> build() {
    ref.watch(currentUserProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<SoftwareLicense>> fetchPage(int page) =>
      ref.read(itamRepositoryProvider).licenses(page: page);

  Future<SoftwareLicense> create(SoftwareLicenseRequest request) async {
    final created =
        await ref.read(itamRepositoryProvider).createLicense(request);
    await refresh();
    return created;
  }
}

final licensesProvider =
    AsyncNotifierProvider<LicensesController, PagedState<SoftwareLicense>>(
  LicensesController.new,
);

class OffboardingController extends AsyncNotifier<List<OffboardingChecklist>> {
  @override
  Future<List<OffboardingChecklist>> build() {
    ref.watch(currentUserProvider);
    return ref.read(itamRepositoryProvider).checklists();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(itamRepositoryProvider).checklists(),
    );
  }

  Future<OffboardingChecklist> create(
    OffboardingChecklistRequest request,
  ) async {
    final created =
        await ref.read(itamRepositoryProvider).createChecklist(request);
    await refresh();
    return created;
  }

  /// Replaces one checklist with the server's version of it after a step lands.
  void apply(OffboardingChecklist updated) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final checklist in current)
        if (checklist.id == updated.id) updated else checklist,
    ]);
  }
}

final offboardingProvider =
    AsyncNotifierProvider<OffboardingController, List<OffboardingChecklist>>(
  OffboardingController.new,
);
