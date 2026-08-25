import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import '../directory/directory_models.dart' show Department;
import 'admin_models.dart';

/// Company configuration.
///
/// Five lists that everything else picks from — departments, job grades,
/// announcements, service categories and custom roles. They share one shape
/// almost exactly: list, create, edit, and a toggle that retires a row rather
/// than deleting it, because something already points at it.
///
/// The one exception is custom roles, which also carry a permission set and an
/// employee assignment — see [setRolePermissions] and [assignRole].
class AdminRepository {
  AdminRepository(this._api);

  final ApiClient _api;

  // ── Departments ─────────────────────────────────────────────

  Future<PagedResponse<Department>> departments({
    int page = 0,
    int size = 50,
  }) =>
      _api.getPaged('/departments', Department.fromJson, page: page, size: size);

  Future<Department> createDepartment(DepartmentRequest request) async {
    final json =
        await _api.post<Map<String, dynamic>>('/departments', request.toJson());
    return Department.fromJson(json);
  }

  Future<Department> updateDepartment(
    int id,
    DepartmentRequest request,
  ) async {
    final json = await _api.put<Map<String, dynamic>>(
      '/departments/$id',
      request.toJson(),
    );
    return Department.fromJson(json);
  }

  /// Retires or restores it. There is no delete: a department with people in
  /// it cannot simply vanish, so the backend flips a flag instead.
  Future<Department> toggleDepartment(int id) async {
    final json =
        await _api.patch<Map<String, dynamic>>('/departments/$id/toggle');
    return Department.fromJson(json);
  }

  // ── Designations ────────────────────────────────────────────

  Future<PagedResponse<Designation>> designations({
    int page = 0,
    int size = 50,
  }) =>
      _api.getPaged(
        '/hr/designations',
        Designation.fromJson,
        page: page,
        size: size,
      );

  Future<Designation> createDesignation(DesignationRequest request) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/hr/designations',
      request.toJson(),
    );
    return Designation.fromJson(json);
  }

  Future<Designation> updateDesignation(
    int id,
    DesignationRequest request,
  ) async {
    final json = await _api.put<Map<String, dynamic>>(
      '/hr/designations/$id',
      request.toJson(),
    );
    return Designation.fromJson(json);
  }

  Future<Designation> toggleDesignation(int id) async {
    final json =
        await _api.patch<Map<String, dynamic>>('/hr/designations/$id/toggle');
    return Designation.fromJson(json);
  }

  // ── Announcements ───────────────────────────────────────────

  Future<PagedResponse<AdminAnnouncement>> announcements({
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        '/announcements',
        AdminAnnouncement.fromJson,
        page: page,
        size: size,
      );

  Future<AdminAnnouncement> createAnnouncement(
    AnnouncementRequest request,
  ) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/announcements',
      request.toJson(),
    );
    return AdminAnnouncement.fromJson(json);
  }

  /// Refused once it has been published — see [AdminAnnouncement.isEditable].
  Future<AdminAnnouncement> updateAnnouncement(
    int id,
    AnnouncementRequest request,
  ) async {
    final json = await _api.put<Map<String, dynamic>>(
      '/announcements/$id',
      request.toJson(),
    );
    return AdminAnnouncement.fromJson(json);
  }

  /// Drafts a title and body from an instruction.
  ///
  /// Nothing is saved — the draft comes back for the writer to edit and then
  /// save themselves. Gated on AI_CHAT underneath, like every other assist.
  Future<({String title, String body})> draftAnnouncement(
    String instructions,
  ) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/announcements/ai-draft',
      {'instructions': instructions.trim()},
    );
    return (
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
    );
  }

  /// Sends it out. One way — there is no unpublish, which is why the screen
  /// asks before doing it.
  Future<AdminAnnouncement> publishAnnouncement(int id) async {
    final json =
        await _api.patch<Map<String, dynamic>>('/announcements/$id/publish');
    return AdminAnnouncement.fromJson(json);
  }

  // ── Service categories ──────────────────────────────────────

  Future<PagedResponse<ServiceCategory>> serviceCategories({
    int page = 0,
    int size = 50,
  }) =>
      // `/all` rather than the default list: the plain one returns active
      // categories only, and an admin screen that cannot see what it retired
      // has no way to bring it back.
      _api.getPaged(
        '/service-categories/all',
        ServiceCategory.fromJson,
        page: page,
        size: size,
      );

  Future<ServiceCategory> createServiceCategory(
    ServiceCategoryRequest request,
  ) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/service-categories',
      request.toJson(),
    );
    return ServiceCategory.fromJson(json);
  }

  Future<ServiceCategory> updateServiceCategory(
    int id,
    ServiceCategoryRequest request,
  ) async {
    final json = await _api.put<Map<String, dynamic>>(
      '/service-categories/$id',
      request.toJson(),
    );
    return ServiceCategory.fromJson(json);
  }

  Future<ServiceCategory> toggleServiceCategory(int id) async {
    final json = await _api
        .patch<Map<String, dynamic>>('/service-categories/$id/toggle');
    return ServiceCategory.fromJson(json);
  }

  // ── Custom roles ────────────────────────────────────────────

  /// A bare list, not a page — this endpoint returns `List<CustomRoleResponse>`
  /// directly, and a company has a handful of roles rather than pages of them.
  Future<List<CustomRole>> customRoles() async {
    final list = await _api.get<List<dynamic>>('/custom-roles');
    return list
        .whereType<Map<String, dynamic>>()
        .map(CustomRole.fromJson)
        .toList(growable: false);
  }

  Future<CustomRole> createRole(CustomRoleRequest request) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/custom-roles',
      request.toJson(),
    );
    return CustomRole.fromJson(json);
  }

  Future<CustomRole> updateRole(int id, CustomRoleRequest request) async {
    final json = await _api.put<Map<String, dynamic>>(
      '/custom-roles/$id',
      request.toJson(),
    );
    return CustomRole.fromJson(json);
  }

  Future<void> deleteRole(int id) => _api.delete<dynamic>('/custom-roles/$id');

  /// The codes this role currently grants.
  Future<List<String>> rolePermissions(int id) async {
    final list = await _api.get<List<dynamic>>('/custom-roles/$id/permissions');
    return list.whereType<String>().toList(growable: false);
  }

  /// Replaces the role's whole permission set.
  ///
  /// The body is a **bare JSON array of codes**, not an object wrapping one —
  /// the controller takes `@RequestBody List<String>`. And it is a replace, not
  /// a merge: whatever is sent becomes the entire set, so the caller sends
  /// every code that should remain, not just the ones being added.
  Future<List<String>> setRolePermissions(int id, List<String> codes) async {
    final list = await _api.put<List<dynamic>>(
      '/custom-roles/$id/permissions',
      codes,
    );
    return list.whereType<String>().toList(growable: false);
  }

  /// Puts an employee into a role. Company owner only — narrower than the rest
  /// of this screen, which platform admins can also reach.
  Future<void> assignRole(int roleId, int employeeId) =>
      _api.post<dynamic>('/custom-roles/$roleId/employees/$employeeId');

  /// Takes them out of whatever role they were in. Keyed on the employee, not
  /// the role — somebody holds at most one.
  Future<void> unassignRole(int employeeId) =>
      _api.delete<dynamic>('/custom-roles/employees/$employeeId');
}

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AdminRepository(ref.watch(apiClientProvider)),
);

/// Every permission code that exists, for the role editor's checklist.
///
/// Fetched once and kept: the catalogue is fixed by the backend's enum and
/// does not change while the app is open.
final permissionCatalogueProvider =
    FutureProvider<List<PermissionOption>>((ref) async {
  final list =
      await ref.read(apiClientProvider).get<List<dynamic>>('/permissions');
  return list
      .whereType<Map<String, dynamic>>()
      .map(PermissionOption.fromJson)
      .toList(growable: false);
});

class DepartmentsAdminController extends AsyncNotifier<List<Department>> {
  @override
  Future<List<Department>> build() {
    ref.watch(currentUserProvider);
    return _load();
  }

  Future<List<Department>> _load() async {
    final page = await ref.read(adminRepositoryProvider).departments();
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  /// Swaps the row rather than reloading — the list is alphabetical and an
  /// edit does not move anything.
  void apply(Department updated) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current) if (row.id == updated.id) updated else row,
    ]);
  }
}

final departmentsAdminProvider =
    AsyncNotifierProvider<DepartmentsAdminController, List<Department>>(
  DepartmentsAdminController.new,
);

class DesignationsAdminController extends AsyncNotifier<List<Designation>> {
  @override
  Future<List<Designation>> build() {
    ref.watch(currentUserProvider);
    return _load();
  }

  Future<List<Designation>> _load() async {
    final page = await ref.read(adminRepositoryProvider).designations();
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  void apply(Designation updated) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current) if (row.id == updated.id) updated else row,
    ]);
  }
}

final designationsAdminProvider =
    AsyncNotifierProvider<DesignationsAdminController, List<Designation>>(
  DesignationsAdminController.new,
);

class AnnouncementsAdminController
    extends AsyncNotifier<List<AdminAnnouncement>> {
  @override
  Future<List<AdminAnnouncement>> build() {
    ref.watch(currentUserProvider);
    return _load();
  }

  Future<List<AdminAnnouncement>> _load() async {
    final page = await ref.read(adminRepositoryProvider).announcements();
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  void apply(AdminAnnouncement updated) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current) if (row.id == updated.id) updated else row,
    ]);
  }
}

final announcementsAdminProvider = AsyncNotifierProvider<
    AnnouncementsAdminController, List<AdminAnnouncement>>(
  AnnouncementsAdminController.new,
);

class ServiceCategoriesAdminController
    extends AsyncNotifier<List<ServiceCategory>> {
  @override
  Future<List<ServiceCategory>> build() {
    ref.watch(currentUserProvider);
    return _load();
  }

  Future<List<ServiceCategory>> _load() async {
    final page = await ref.read(adminRepositoryProvider).serviceCategories();
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  void apply(ServiceCategory updated) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current) if (row.id == updated.id) updated else row,
    ]);
  }
}

final serviceCategoriesAdminProvider = AsyncNotifierProvider<
    ServiceCategoriesAdminController, List<ServiceCategory>>(
  ServiceCategoriesAdminController.new,
);

final customRolesProvider = FutureProvider<List<CustomRole>>((ref) {
  ref.watch(currentUserProvider);
  return ref.read(adminRepositoryProvider).customRoles();
});

final rolePermissionsProvider =
    FutureProvider.autoDispose.family<List<String>, int>(
  (ref, roleId) => ref.read(adminRepositoryProvider).rolePermissions(roleId),
);
