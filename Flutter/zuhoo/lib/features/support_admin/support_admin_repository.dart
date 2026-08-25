import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import 'support_admin_models.dart';

/// Running the support desk.
///
/// Note the two different prefixes. Agents live under `/v1/support/...` with
/// the tickets and messages; categories, SLA policies and audit logs live under
/// plain `/support/...`. That is how the backend is laid out, not a typo.
class SupportAdminRepository {
  SupportAdminRepository(this._api);

  final ApiClient _api;

  static const _agents = '/v1/support/agents';
  static const _categories = '/support/categories';
  static const _sla = '/support/sla-policies';
  static const _audit = '/support/audit-logs';

  // ── Agents ──────────────────────────────────────────────────

  /// The whole desk, or one slice of it.
  ///
  /// The filter is a **path segment**, not a query parameter — the backend has
  /// a separate endpoint per status rather than one optional filter, plus
  /// `/available` for those free to take a ticket right now.
  ///
  /// `/available` returns a bare list rather than a page; `getPaged` reads
  /// either shape, so both go through here.
  Future<PagedResponse<SupportAgent>> agents({
    String? status,
    int page = 0,
    int size = 30,
  }) {
    // Written out rather than as a switch: a bare identifier in a pattern
    // position binds a variable instead of comparing against the constant.
    final String path;
    if (status == null) {
      path = _agents;
    } else if (status == availableAgentsFilter) {
      path = '$_agents/available';
    } else {
      path = '$_agents/status/$status';
    }
    return _api.getPaged(
      path,
      SupportAgent.fromJson,
      page: page,
      size: size,
    );
  }

  /// Makes a platform user into an agent.
  ///
  /// `userId` is required, but the backend enforces it with a plain
  /// `IllegalArgumentException` rather than validation, so a missing one comes
  /// back as a server error rather than a readable message. The form requires
  /// it before submitting.
  Future<SupportAgent> createAgent(SupportAgentRequest request) async {
    final json =
        await _api.post<Map<String, dynamic>>(_agents, request.toJson());
    return SupportAgent.fromJson(json);
  }

  /// Sends the whole record — see [SupportAgentRequest] for why an omitted
  /// field is not a field left alone.
  Future<SupportAgent> updateAgent(int id, SupportAgentRequest request) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_agents/$id',
      request.toJson(),
    );
    return SupportAgent.fromJson(json);
  }

  /// Query parameter, and the response is empty — there is nothing to parse
  /// back, so the caller applies the change itself.
  Future<void> setAgentStatus(int id, String status) =>
      _api.patch<dynamic>('$_agents/$id/status?status=$status');

  /// Whether new tickets can land on them. Also a query parameter with an empty
  /// response.
  Future<void> setAcceptingTickets(int id, bool accepting) =>
      _api.patch<dynamic>('$_agents/$id/accepting-tickets?accepting=$accepting');

  // ── Categories ──────────────────────────────────────────────

  Future<PagedResponse<SupportCategory>> categories({
    int page = 0,
    int size = 50,
  }) =>
      _api.getPaged(
        _categories,
        SupportCategory.fromJson,
        page: page,
        size: size,
      );

  Future<SupportCategory> createCategory(SupportCategoryRequest request) async {
    final json =
        await _api.post<Map<String, dynamic>>(_categories, request.toJson());
    return SupportCategory.fromJson(json);
  }

  Future<SupportCategory> updateCategory(
    int id,
    SupportCategoryRequest request,
  ) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_categories/$id',
      request.toJson(),
    );
    return SupportCategory.fromJson(json);
  }

  /// Retire or restore. Query parameter, empty response.
  Future<void> setCategoryActive(int id, bool active) =>
      _api.patch<dynamic>('$_categories/$id/status?active=$active');

  Future<void> deleteCategory(int id) =>
      _api.delete<dynamic>('$_categories/$id');

  // ── SLA policies ────────────────────────────────────────────

  Future<PagedResponse<SlaPolicy>> slaPolicies({
    String? priority,
    int page = 0,
    int size = 50,
  }) =>
      // Same shape as the agent filter: the priority is a path segment, and
      // that endpoint returns a bare list rather than a page. `getPaged`
      // tolerates both.
      _api.getPaged(
        priority == null ? _sla : '$_sla/priority/$priority',
        SlaPolicy.fromJson,
        page: page,
        size: size,
      );

  Future<SlaPolicy> createSlaPolicy(SlaPolicyRequest request) async {
    final json = await _api.post<Map<String, dynamic>>(_sla, request.toJson());
    return SlaPolicy.fromJson(json);
  }

  Future<SlaPolicy> updateSlaPolicy(int id, SlaPolicyRequest request) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_sla/$id',
      request.toJson(),
    );
    return SlaPolicy.fromJson(json);
  }

  Future<void> setSlaActive(int id, bool active) =>
      _api.patch<dynamic>('$_sla/$id/status?active=$active');

  Future<void> deleteSlaPolicy(int id) => _api.delete<dynamic>('$_sla/$id');

  // ── Audit trail ─────────────────────────────────────────────

  /// One endpoint per filter rather than one endpoint with parameters, so the
  /// filter decides the URL.
  Future<PagedResponse<SupportAuditEntry>> auditLog({
    AuditFilter filter = const AuditFilter(),
    int page = 0,
    int size = 25,
  }) {
    var path = _audit;
    final query = <String, dynamic>{};

    if (filter.actionType != null) {
      path = '$_audit/action/${Uri.encodeComponent(filter.actionType!)}';
    } else if (filter.hasDateRange) {
      path = '$_audit/date-range';
      query['start'] = filter.start;
      query['end'] = filter.end;
    }

    return _api.getPaged(
      path,
      SupportAuditEntry.fromJson,
      page: page,
      size: size,
      query: query,
    );
  }
}

final supportAdminRepositoryProvider = Provider<SupportAdminRepository>(
  (ref) => SupportAdminRepository(ref.watch(apiClientProvider)),
);

/// Which status the agent list is narrowed to. Null means every one.
class AgentStatusFilterController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? status) {
    if (state == status) return;
    state = status;
  }
}

final agentStatusFilterProvider =
    NotifierProvider<AgentStatusFilterController, String?>(
  AgentStatusFilterController.new,
);

class SupportAgentsController extends AsyncNotifier<List<SupportAgent>> {
  @override
  Future<List<SupportAgent>> build() {
    ref.watch(currentUserProvider);
    // Watched here rather than in _load: changing the filter rebuilds the
    // controller, while a pull-to-refresh reads whatever is set at the time.
    ref.watch(agentStatusFilterProvider);
    return _load();
  }

  Future<List<SupportAgent>> _load() async {
    final page = await ref
        .read(supportAdminRepositoryProvider)
        .agents(status: ref.read(agentStatusFilterProvider));
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  void apply(SupportAgent updated) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current) if (row.id == updated.id) updated else row,
    ]);
  }
}

final supportAgentsProvider =
    AsyncNotifierProvider<SupportAgentsController, List<SupportAgent>>(
  SupportAgentsController.new,
);

class SupportCategoriesController extends AsyncNotifier<List<SupportCategory>> {
  @override
  Future<List<SupportCategory>> build() {
    ref.watch(currentUserProvider);
    return _load();
  }

  Future<List<SupportCategory>> _load() async {
    final page = await ref.read(supportAdminRepositoryProvider).categories();
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  void apply(SupportCategory updated) {
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

final supportCategoriesProvider =
    AsyncNotifierProvider<SupportCategoriesController, List<SupportCategory>>(
  SupportCategoriesController.new,
);

/// Which priority the SLA list is narrowed to. Null means every one.
class SlaPriorityFilterController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? priority) {
    if (state == priority) return;
    state = priority;
  }
}

final slaPriorityFilterProvider =
    NotifierProvider<SlaPriorityFilterController, String?>(
  SlaPriorityFilterController.new,
);

class SlaPoliciesController extends AsyncNotifier<List<SlaPolicy>> {
  @override
  Future<List<SlaPolicy>> build() {
    ref.watch(currentUserProvider);
    ref.watch(slaPriorityFilterProvider);
    return _load();
  }

  Future<List<SlaPolicy>> _load() async {
    final page = await ref
        .read(supportAdminRepositoryProvider)
        .slaPolicies(priority: ref.read(slaPriorityFilterProvider));
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  void apply(SlaPolicy updated) {
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

final slaPoliciesProvider =
    AsyncNotifierProvider<SlaPoliciesController, List<SlaPolicy>>(
  SlaPoliciesController.new,
);

/// The audit filter currently in force.
class AuditFilterController extends Notifier<AuditFilter> {
  @override
  AuditFilter build() => const AuditFilter();

  void set(AuditFilter filter) {
    state = filter;
  }

  void clear() {
    state = const AuditFilter();
  }
}

final auditFilterProvider =
    NotifierProvider<AuditFilterController, AuditFilter>(
  AuditFilterController.new,
);

class SupportAuditController extends AsyncNotifier<List<SupportAuditEntry>> {
  @override
  Future<List<SupportAuditEntry>> build() {
    ref.watch(currentUserProvider);
    ref.watch(auditFilterProvider);
    return _load();
  }

  Future<List<SupportAuditEntry>> _load() async {
    final page = await ref
        .read(supportAdminRepositoryProvider)
        .auditLog(filter: ref.read(auditFilterProvider));
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }
}

final supportAuditProvider =
    AsyncNotifierProvider<SupportAuditController, List<SupportAuditEntry>>(
  SupportAuditController.new,
);
