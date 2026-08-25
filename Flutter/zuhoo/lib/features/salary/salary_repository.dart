import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import 'salary_models.dart';

/// Pay agreements, loans, and the component catalogue they draw on.
class SalaryRepository {
  SalaryRepository(this._api);

  final ApiClient _api;

  static const _structures = '/hr/salary-structures';
  static const _loans = '/hr/loans';
  static const _components = '/hr/salary-components';

  // ── Structures ──────────────────────────────────────────────

  Future<PagedResponse<SalaryStructure>> structures({
    int page = 0,
    int size = 30,
  }) =>
      _api.getPaged(
        _structures,
        SalaryStructure.fromJson,
        page: page,
        size: size,
      );

  /// One employee's whole history, newest first as the backend returns it.
  Future<List<SalaryStructure>> historyFor(int employeeId) async {
    final list =
        await _api.get<List<dynamic>>('$_structures/employee/$employeeId/history');
    return list
        .whereType<Map<String, dynamic>>()
        .map(SalaryStructure.fromJson)
        .toList(growable: false);
  }

  /// The structure in force for one employee, or null when they have none.
  ///
  /// Having none is the ordinary state for a new joiner and the reason payroll
  /// skips somebody, so a 404 comes back as null rather than throwing.
  Future<SalaryStructure?> activeFor(int employeeId) async {
    try {
      final json = await _api.get<Map<String, dynamic>>(
        '$_structures/employee/$employeeId/active',
      );
      return SalaryStructure.fromJson(json);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Adds a structure. If the employee already has one, this supersedes it —
  /// the old one is dated off and locked rather than overwritten.
  Future<SalaryStructure> createStructure(
    SalaryStructureRequest request,
  ) async {
    final json =
        await _api.post<Map<String, dynamic>>(_structures, request.toJson());
    return SalaryStructure.fromJson(json);
  }

  /// Edits the current structure. Refused on a superseded one with "Only the
  /// current salary structure can be edited."
  ///
  /// Sends every allowance and deduction — see [SalaryStructureRequest] for why
  /// an omitted one becomes zero rather than staying as it was.
  Future<SalaryStructure> updateStructure(
    int id,
    SalaryStructureRequest request,
  ) async {
    final json = await _api.put<Map<String, dynamic>>(
      '$_structures/$id',
      request.toJson(),
    );
    return SalaryStructure.fromJson(json);
  }

  /// `deleteText`: declares `ResponseEntity<String>` and answers with a
  /// sentence rather than JSON.
  Future<void> deleteStructure(int id) => _api.deleteText('$_structures/$id');

  // ── Loans and advances ──────────────────────────────────────

  /// A bare list. Everything outstanding across the company.
  Future<List<LoanAdvance>> loans() async {
    final list = await _api.get<List<dynamic>>(_loans);
    return list
        .whereType<Map<String, dynamic>>()
        .map(LoanAdvance.fromJson)
        .toList(growable: false);
  }

  Future<List<LoanAdvance>> loansFor(int employeeId) async {
    final list = await _api.get<List<dynamic>>('$_loans/employee/$employeeId');
    return list
        .whereType<Map<String, dynamic>>()
        .map(LoanAdvance.fromJson)
        .toList(growable: false);
  }

  Future<LoanAdvance> createLoan(CreateLoanRequest request) async {
    final json =
        await _api.post<Map<String, dynamic>>(_loans, request.toJson());
    return LoanAdvance.fromJson(json);
  }

  /// What payroll has recovered so far, month by month.
  Future<List<LoanRepayment>> repayments(int id) async {
    final list = await _api.get<List<dynamic>>('$_loans/$id/repayments');
    return list
        .whereType<Map<String, dynamic>>()
        .map(LoanRepayment.fromJson)
        .toList(growable: false);
  }

  /// Stops further recovery. There is no edit — a loan is cancelled and
  /// re-entered rather than changed, because payroll has already acted on it.
  Future<LoanAdvance> cancelLoan(int id) async {
    final json = await _api.post<Map<String, dynamic>>('$_loans/$id/cancel');
    return LoanAdvance.fromJson(json);
  }

  // ── Component catalogue ─────────────────────────────────────

  Future<List<SalaryComponent>> components() async {
    final list = await _api.get<List<dynamic>>(_components);
    return list
        .whereType<Map<String, dynamic>>()
        .map(SalaryComponent.fromJson)
        .toList(growable: false);
  }

  Future<SalaryComponent> createComponent(
    SalaryComponentRequest request,
  ) async {
    final json =
        await _api.post<Map<String, dynamic>>(_components, request.toJson());
    return SalaryComponent.fromJson(json);
  }

  Future<SalaryComponent> updateComponent(
    int id,
    SalaryComponentRequest request,
  ) async {
    final json = await _api.put<Map<String, dynamic>>(
      '$_components/$id',
      request.toJson(),
    );
    return SalaryComponent.fromJson(json);
  }
}

final salaryRepositoryProvider = Provider<SalaryRepository>(
  (ref) => SalaryRepository(ref.watch(apiClientProvider)),
);

class SalaryStructuresController extends AsyncNotifier<List<SalaryStructure>> {
  @override
  Future<List<SalaryStructure>> build() {
    ref.watch(currentUserProvider);
    return _load();
  }

  Future<List<SalaryStructure>> _load() async {
    final page = await ref.read(salaryRepositoryProvider).structures();
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  /// Reloads rather than patching after a create: adding a structure also
  /// supersedes whatever came before it, so a second row changes too.
  void apply(SalaryStructure updated) {
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

final salaryStructuresProvider =
    AsyncNotifierProvider<SalaryStructuresController, List<SalaryStructure>>(
  SalaryStructuresController.new,
);

class LoansController extends AsyncNotifier<List<LoanAdvance>> {
  @override
  Future<List<LoanAdvance>> build() {
    ref.watch(currentUserProvider);
    return ref.read(salaryRepositoryProvider).loans();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(salaryRepositoryProvider).loans(),
    );
  }

  void apply(LoanAdvance updated) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current) if (row.id == updated.id) updated else row,
    ]);
  }
}

final loansProvider = AsyncNotifierProvider<LoansController, List<LoanAdvance>>(
  LoansController.new,
);

class SalaryComponentsController extends AsyncNotifier<List<SalaryComponent>> {
  @override
  Future<List<SalaryComponent>> build() {
    ref.watch(currentUserProvider);
    return ref.read(salaryRepositoryProvider).components();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(salaryRepositoryProvider).components(),
    );
  }

  void apply(SalaryComponent updated) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current) if (row.id == updated.id) updated else row,
    ]);
  }
}

final salaryComponentsProvider =
    AsyncNotifierProvider<SalaryComponentsController, List<SalaryComponent>>(
  SalaryComponentsController.new,
);

/// One employee's history of structures, for the detail screen.
final structureHistoryProvider =
    FutureProvider.autoDispose.family<List<SalaryStructure>, int>(
  (ref, employeeId) =>
      ref.read(salaryRepositoryProvider).historyFor(employeeId),
);

/// What payroll has recovered against one loan.
final repaymentsProvider =
    FutureProvider.autoDispose.family<List<LoanRepayment>, int>(
  (ref, loanId) => ref.read(salaryRepositoryProvider).repayments(loanId),
);
