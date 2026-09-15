import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import 'budget_models.dart';

class BudgetRepository {
  BudgetRepository(this._api);

  final ApiClient _api;

  static const _base = '/company/finance/budgets';

  Future<List<Budget>> listForYear(int fiscalYear) async {
    final list = await _api.get<List<dynamic>>(
      _base,
      query: {'fiscalYear': fiscalYear},
    );
    return list
        .whereType<Map<String, dynamic>>()
        .map(Budget.fromJson)
        .toList(growable: false);
  }

  /// Distinct category names already budgeted, offered as suggestions on this
  /// form and (elsewhere) on the expense-claim one.
  Future<List<String>> categories() async {
    final list = await _api.get<List<dynamic>>('$_base/categories');
    return list.whereType<String>().toList(growable: false);
  }

  Future<Budget> create(BudgetRequest request) async {
    final json = await _api.post<Map<String, dynamic>>(_base, request.toJson());
    return Budget.fromJson(json);
  }

  Future<Budget> update(int id, BudgetRequest request) async {
    final json =
        await _api.put<Map<String, dynamic>>('$_base/$id', request.toJson());
    return Budget.fromJson(json);
  }

  Future<void> delete(int id) => _api.delete<dynamic>('$_base/$id');
}

final budgetRepositoryProvider = Provider<BudgetRepository>(
  (ref) => BudgetRepository(ref.watch(apiClientProvider)),
);

/// Which fiscal year the Budgets screen is showing. Defaults to whatever year
/// it is now, which is right far more often than not.
class BudgetYearController extends Notifier<int> {
  @override
  int build() => DateTime.now().year;

  void set(int year) {
    if (state == year) return;
    state = year;
  }
}

final budgetYearProvider =
    NotifierProvider<BudgetYearController, int>(BudgetYearController.new);

class BudgetsController extends AsyncNotifier<List<Budget>> {
  @override
  Future<List<Budget>> build() {
    ref.watch(currentUserProvider);
    ref.watch(budgetYearProvider);
    return _load();
  }

  Future<List<Budget>> _load() =>
      ref.read(budgetRepositoryProvider).listForYear(ref.read(budgetYearProvider));

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  void apply(Budget updated) {
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

final budgetsProvider =
    AsyncNotifierProvider<BudgetsController, List<Budget>>(BudgetsController.new);

final budgetCategoriesProvider = FutureProvider<List<String>>(
  (ref) => ref.read(budgetRepositoryProvider).categories(),
);
