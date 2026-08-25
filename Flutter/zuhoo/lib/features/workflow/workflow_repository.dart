import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import 'workflow_models.dart';

/// The stages a service request moves through.
///
/// A template is short — half a dozen stages with a name, an order and a
/// couple of flags — which is why this one is on the phone at all while the
/// service form-field designer beside it is not.
class WorkflowRepository {
  WorkflowRepository(this._api);

  final ApiClient _api;

  static const _base = '/workflows';

  Future<PagedResponse<WorkflowTemplate>> templates({
    int page = 0,
    int size = 30,
  }) =>
      _api.getPaged(
        _base,
        WorkflowTemplate.fromJson,
        page: page,
        size: size,
      );

  /// One template with its stages.
  ///
  /// The list endpoint returns them too, but this is re-read after every stage
  /// change: the backend bumps the template's version on each one, and the
  /// stage ids of a newly added stage are only known from the answer.
  Future<WorkflowTemplate> template(int id) async {
    final json = await _api.get<Map<String, dynamic>>('$_base/$id');
    return WorkflowTemplate.fromJson(json);
  }

  Future<WorkflowTemplate> create(WorkflowTemplateRequest request) async {
    final json = await _api.post<Map<String, dynamic>>(_base, request.toJson());
    return WorkflowTemplate.fromJson(json);
  }

  Future<WorkflowTemplate> update(
    int id,
    WorkflowTemplateRequest request,
  ) async {
    final json =
        await _api.put<Map<String, dynamic>>('$_base/$id', request.toJson());
    return WorkflowTemplate.fromJson(json);
  }

  Future<WorkflowTemplate> toggle(int id) async {
    final json = await _api.patch<Map<String, dynamic>>('$_base/$id/toggle');
    return WorkflowTemplate.fromJson(json);
  }

  /// `deleteText` rather than `delete`: the endpoint declares
  /// `ResponseEntity<String>` and answers with a sentence, not JSON.
  Future<void> delete(int id) => _api.deleteText('$_base/$id');

  // ── Stages ──────────────────────────────────────────────────

  Future<WorkflowStage> addStage(
    int templateId,
    WorkflowStageRequest request,
  ) async {
    final json = await _api.post<Map<String, dynamic>>(
      '$_base/$templateId/stages',
      request.toJson(),
    );
    return WorkflowStage.fromJson(json);
  }

  /// Sends the whole stage — see [WorkflowStageRequest] for which fields are
  /// assigned without a null check.
  Future<WorkflowStage> updateStage(
    int templateId,
    int stageId,
    WorkflowStageRequest request,
  ) async {
    final json = await _api.put<Map<String, dynamic>>(
      '$_base/$templateId/stages/$stageId',
      request.toJson(),
    );
    return WorkflowStage.fromJson(json);
  }

  Future<void> deleteStage(int templateId, int stageId) =>
      _api.deleteText('$_base/$templateId/stages/$stageId');

  // ── Assistance ──────────────────────────────────────────────

  /// Proposes a set of stages for a stated goal. Saves nothing.
  Future<WorkflowSuggestion> suggest(String goal) async {
    final json = await _api.post<Map<String, dynamic>>(
      '$_base/suggest',
      {'goal': goal.trim()},
    );
    return WorkflowSuggestion.fromJson(json);
  }
}

final workflowRepositoryProvider = Provider<WorkflowRepository>(
  (ref) => WorkflowRepository(ref.watch(apiClientProvider)),
);

class WorkflowsController extends AsyncNotifier<List<WorkflowTemplate>> {
  @override
  Future<List<WorkflowTemplate>> build() {
    ref.watch(currentUserProvider);
    return _load();
  }

  Future<List<WorkflowTemplate>> _load() async {
    final page = await ref.read(workflowRepositoryProvider).templates();
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  void apply(WorkflowTemplate updated) {
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

final workflowsProvider =
    AsyncNotifierProvider<WorkflowsController, List<WorkflowTemplate>>(
  WorkflowsController.new,
);

/// One template, re-read after each stage change.
///
/// `autoDispose` because it is only alive while its screen is open, and the
/// version it holds is stale the moment a stage moves.
final workflowDetailProvider =
    FutureProvider.autoDispose.family<WorkflowTemplate, int>(
  (ref, id) => ref.read(workflowRepositoryProvider).template(id),
);
