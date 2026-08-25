import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import '../../shared/paged_controller.dart';
import 'directory_models.dart';

/// The company's people.
///
/// Adding and editing a colleague are here now, brought over from the web app
/// for parity — an earlier version of this file was read-only on the grounds
/// that the forms were too wide for a phone.
///
/// That reasoning still shapes what the edit form offers. `PATCH /employees`
/// is a sparse patch, so a narrow form is safe: it sends what it shows and
/// leaves everything else alone. Salary, bank details and emergency contacts
/// are therefore still absent, because [Person] does not carry them and a form
/// cannot honestly edit a value it cannot display.
///
/// Still absent entirely: **terminating** an employee, which is its own
/// endpoint and its own decision.
class DirectoryRepository {
  DirectoryRepository(this._api);

  final ApiClient _api;

  Future<PagedResponse<Person>> people({
    String? search,
    int? departmentId,
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        '/employees',
        Person.fromJson,
        page: page,
        size: size,
        query: {
          'search': search,
          'departmentId': departmentId,
          // The company owner is not an employee of it in the usual sense and
          // has no department or job title, so they surface as a blank row at
          // the top of an alphabetical list. The endpoint knows how to leave
          // them out.
          'excludeOwner': true,
        },
      );

  Future<Person> person(int id) async {
    final json = await _api.get<Map<String, dynamic>>('/employees/$id');
    return Person.fromJson(json);
  }

  /// Adds a colleague, and provisions the login they will sign in with.
  ///
  /// A duplicate email is refused by the backend with a message that says so.
  Future<Person> create(CreateEmployeeRequest request) async {
    final json =
        await _api.post<Map<String, dynamic>>('/employees', request.toJson());
    return Person.fromJson(json);
  }

  /// Edits the parts of an employee this app can also show — see
  /// [UpdateEmployeeRequest] for why that boundary matters.
  Future<Person> update(int id, UpdateEmployeeRequest request) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '/employees/$id',
      request.toJson(),
    );
    return Person.fromJson(json);
  }

  /// Departments that still exist, for the filter. Optional: without them the
  /// filter simply is not offered.
  Future<List<Department>> departments() async {
    try {
      final list = await _api.get<List<dynamic>>('/departments/active');
      return list
          .whereType<Map<String, dynamic>>()
          .map(Department.fromJson)
          .where((d) => d.name.isNotEmpty)
          .toList(growable: false);
    } on ApiException {
      return const [];
    }
  }
}

final directoryRepositoryProvider = Provider<DirectoryRepository>(
  (ref) => DirectoryRepository(ref.watch(apiClientProvider)),
);

/// The typed search term. Held separately so the list controller can rebuild
/// on it without the text field owning the request.
class DirectorySearchController extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) {
    final trimmed = value.trim();
    if (state == trimmed) return;
    state = trimmed;
  }
}

final directorySearchProvider =
    NotifierProvider<DirectorySearchController, String>(
  DirectorySearchController.new,
);

/// Which department the list is narrowed to. Null means everyone.
class DepartmentFilterController extends Notifier<int?> {
  @override
  int? build() => null;

  void set(int? departmentId) {
    if (state == departmentId) return;
    state = departmentId;
  }
}

final departmentFilterProvider =
    NotifierProvider<DepartmentFilterController, int?>(
  DepartmentFilterController.new,
);

class DirectoryController extends AsyncNotifier<PagedState<Person>>
    with PagedLoader<Person> {
  @override
  Future<PagedState<Person>> build() {
    ref.watch(currentUserProvider);
    ref.watch(directorySearchProvider);
    ref.watch(departmentFilterProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<Person>> fetchPage(int page) {
    final search = ref.read(directorySearchProvider);
    return ref.read(directoryRepositoryProvider).people(
          search: search.isEmpty ? null : search,
          departmentId: ref.read(departmentFilterProvider),
          page: page,
        );
  }

  /// Reloads rather than inserting: the list is alphabetical and filtered, and
  /// where a new colleague belongs in it is the server's answer, not ours.
  Future<Person> create(CreateEmployeeRequest request) async {
    final created =
        await ref.read(directoryRepositoryProvider).create(request);
    await refresh();
    return created;
  }

  Future<Person> updateItem(int id, UpdateEmployeeRequest request) async {
    final updated =
        await ref.read(directoryRepositoryProvider).update(id, request);
    replaceItem((person) => person.id == id, updated);
    ref.invalidate(personProvider(id));
    return updated;
  }
}

final directoryProvider =
    AsyncNotifierProvider<DirectoryController, PagedState<Person>>(
  DirectoryController.new,
);

final departmentsProvider = FutureProvider<List<Department>>((ref) {
  ref.watch(currentUserProvider);
  return ref.read(directoryRepositoryProvider).departments();
});

/// One colleague's full record, for the detail screen.
final personProvider = FutureProvider.autoDispose.family<Person, int>(
  (ref, id) => ref.read(directoryRepositoryProvider).person(id),
);
