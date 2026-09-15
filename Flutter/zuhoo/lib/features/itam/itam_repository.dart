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

  /// Everything one person is holding. A page on the wire; one generous page
  /// here, since nobody is issued fifty laptops.
  Future<List<Asset>> assetsForEmployee(int employeeId) async {
    final page = await _api.getPaged(
      '$_assets/employee/$employeeId',
      Asset.fromJson,
      page: 0,
      size: 50,
    );
    return page.content;
  }

  /// Writes a piece of kit off for good.
  ///
  /// Not the same as deleting it: the asset stays on the books as disposed,
  /// which is what an audit needs. The reason is an optional query parameter,
  /// and it is the only record of why — so the sheet asks for it even though
  /// the backend does not insist.
  Future<Asset> disposeAsset(int id, {String? reason}) async {
    final trimmed = reason?.trim();
    final query = (trimmed == null || trimmed.isEmpty)
        ? ''
        : '?reason=${Uri.encodeQueryComponent(trimmed)}';
    final json =
        await _api.patch<Map<String, dynamic>>('$_assets/$id/dispose$query');
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

  /// The licence register, optionally narrowed to one state.
  ///
  /// The plain list takes no status parameter — there is a separate path per
  /// status instead — so filtering changes the URL rather than adding a query
  /// string.
  Future<PagedResponse<SoftwareLicense>> licenses({
    String? status,
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        status == null ? _software : '$_software/status/$status',
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

  /// One leaver's checklist. There is at most one per employee.
  Future<OffboardingChecklist> checklistForEmployee(int employeeId) async {
    final json = await _api.get<Map<String, dynamic>>(
      '$_offboarding/employee/$employeeId',
    );
    return OffboardingChecklist.fromJson(json);
  }

  Future<OffboardingChecklist> checklist(int id) async {
    final json = await _api.get<Map<String, dynamic>>('$_offboarding/$id');
    return OffboardingChecklist.fromJson(json);
  }

  /// The ones still open. A bare list rather than a page, unlike [checklists].
  Future<List<OffboardingChecklist>> pendingChecklists() async {
    final list = await _api.get<List<dynamic>>('$_offboarding/pending');
    return list
        .whereType<Map<String, dynamic>>()
        .map(OffboardingChecklist.fromJson)
        .toList(growable: false);
  }

  /// Removes a checklist. Unusually for a delete, this one answers with the
  /// record it removed.
  Future<OffboardingChecklist> deleteChecklist(int id) async {
    final json = await _api.delete<Map<String, dynamic>>('$_offboarding/$id');
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
  ///
  /// The five step endpoints answer `ResponseEntity<Void>` — an empty body,
  /// not the updated checklist — so this re-reads it rather than parsing the
  /// response. Parsing it threw a TypeError, which is not a DioException and
  /// so surfaced as the generic "Something went wrong".
  Future<OffboardingChecklist> completeStep(
    int checklistId,
    String stepPath, {
    String? notes,
  }) async {
    final trimmed = notes?.trim();
    await _api.patch<dynamic>(
      '$_offboarding/$checklistId/$stepPath',
      {if (trimmed != null && trimmed.isNotEmpty) 'notes': trimmed},
    );
    return checklist(checklistId);
  }

  /// Who has had what. Every hand-over and return across the company, newest
  /// first. A `Page`, so one generous page rather than paging a log nobody
  /// scrolls to the bottom of.
  Future<List<AssetHistoryEntry>> assetHistory({
    int? assetId,
    int? employeeId,
  }) async {
    final path = assetId != null
        ? '/hr/asset-history/asset/$assetId'
        : employeeId != null
            ? '/hr/asset-history/employee/$employeeId'
            : '/hr/asset-history';
    final page = await _api.getPaged(
      path,
      AssetHistoryEntry.fromJson,
      page: 0,
      size: 50,
    );
    return page.content;
  }

  /// Brings assets in from a CSV. What it could not use comes back row by row
  /// with a reason.
  Future<AssetImportResult> importAssets(
    String filePath,
    String fileName,
  ) async {
    final json = await _api.postFile<Map<String, dynamic>>(
      '/itam/asset-import',
      filePath,
      fileName,
    );
    return AssetImportResult.fromJson(json);
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
    // Watched, not read: choosing a status is what reloads the register.
    ref.watch(licenceStatusFilterProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<SoftwareLicense>> fetchPage(int page) =>
      ref.read(itamRepositoryProvider).licenses(
            status: ref.read(licenceStatusFilterProvider),
            page: page,
          );

  Future<SoftwareLicense> create(SoftwareLicenseRequest request) async {
    final created =
        await ref.read(itamRepositoryProvider).createLicense(request);
    await refresh();
    return created;
  }

  /// Swaps the row rather than reloading — an edit does not move a licence in
  /// the list.
  void apply(SoftwareLicense updated) =>
      replaceItem((licence) => licence.id == updated.id, updated);
}

/// Which state of licence the register is showing. Null is all of them.
class LicenceStatusFilterController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? status) {
    if (state == status) return;
    state = status;
  }
}

final licenceStatusFilterProvider =
    NotifierProvider<LicenceStatusFilterController, String?>(
  LicenceStatusFilterController.new,
);

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


/// Checklists that are still open — the ones somebody has to work through.
final pendingOffboardingProvider =
    FutureProvider.autoDispose<List<OffboardingChecklist>>((ref) {
  return ref.read(itamRepositoryProvider).pendingChecklists();
});

/// One leaver's checklist, looked up by the person rather than by the record.
final offboardingForEmployeeProvider =
    FutureProvider.autoDispose.family<OffboardingChecklist, int>(
  (ref, employeeId) =>
      ref.read(itamRepositoryProvider).checklistForEmployee(employeeId),
);

/// Where the company's kit has been.
final assetHistoryProvider =
    FutureProvider.autoDispose<List<AssetHistoryEntry>>((ref) {
  return ref.read(itamRepositoryProvider).assetHistory();
});


/// What one person is holding right now.
final assetsForEmployeeProvider =
    FutureProvider.autoDispose.family<List<Asset>, int>(
  (ref, employeeId) =>
      ref.read(itamRepositoryProvider).assetsForEmployee(employeeId),
);
