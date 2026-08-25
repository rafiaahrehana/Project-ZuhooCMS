import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/paged_response.dart';
import '../../shared/paged_controller.dart';
import 'crm_models.dart';
import 'crm_repository.dart';

/// Which lead view the Leads tab is showing. A plain notifier rather than
/// widget state so switching views survives navigating into a lead and back.
class LeadViewController extends Notifier<LeadView> {
  @override
  LeadView build() => LeadView.mine;

  void set(LeadView view) {
    if (state == view) return;
    state = view;
  }
}

final leadViewProvider =
    NotifierProvider<LeadViewController, LeadView>(LeadViewController.new);

class LeadsController extends AsyncNotifier<PagedState<Lead>>
    with PagedLoader<Lead> {
  @override
  Future<PagedState<Lead>> build() {
    ref.watch(currentUserProvider);
    // Watched, not read: changing the view is what reloads this list.
    ref.watch(leadViewProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<Lead>> fetchPage(int page) => ref
      .read(crmRepositoryProvider)
      .leads(ref.read(leadViewProvider), page: page);

  Future<Lead> create(CreateLeadRequest request) async {
    final created = await ref.read(crmRepositoryProvider).createLead(request);
    await refresh();
    return created;
  }

  /// Swaps the edited row in place rather than reloading, so a rep working
  /// down a list does not lose their scroll position on every edit.
  ///
  /// The detail provider is invalidated too: the same lead may be open behind
  /// this list, and it would otherwise keep showing the pre-edit version.
  Future<Lead> updateItem(int id, UpdateLeadRequest request) async {
    final updated =
        await ref.read(crmRepositoryProvider).updateLead(id, request);
    replaceItem((lead) => lead.id == id, updated);
    ref.invalidate(leadDetailProvider(id));
    return updated;
  }

  /// Drops the row locally instead of refetching. A deleted lead cannot come
  /// back on the next page, so there is nothing a reload would correct.
  Future<void> delete(int id) async {
    await ref.read(crmRepositoryProvider).deleteLead(id);
    removeItem((lead) => lead.id == id);
  }
}

final leadsProvider = AsyncNotifierProvider<LeadsController, PagedState<Lead>>(
  LeadsController.new,
);

final leadDetailProvider = FutureProvider.autoDispose.family<Lead, int>(
  (ref, id) => ref.watch(crmRepositoryProvider).lead(id),
);

final leadActivitiesProvider =
    FutureProvider.autoDispose.family<List<CrmActivity>, int>(
  (ref, id) => ref.watch(crmRepositoryProvider).leadActivities(id),
);

/// Which stage the pipeline is filtered to. Null means every open stage.
class PipelineStageController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? stage) {
    if (state == stage) return;
    state = stage;
  }
}

final pipelineStageProvider =
    NotifierProvider<PipelineStageController, String?>(
  PipelineStageController.new,
);

class OpportunitiesController extends AsyncNotifier<PagedState<Opportunity>>
    with PagedLoader<Opportunity> {
  @override
  Future<PagedState<Opportunity>> build() {
    ref.watch(currentUserProvider);
    ref.watch(pipelineStageProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<Opportunity>> fetchPage(int page) => ref
      .read(crmRepositoryProvider)
      .opportunities(stage: ref.read(pipelineStageProvider), page: page);

  /// Moves a deal, then refreshes the list and the headline figures.
  ///
  /// The summary is refetched rather than adjusted locally: probability and the
  /// weighted forecast are server-derived from the stage, and a phone
  /// recalculating them would quietly disagree with the web app's numbers.
  Future<Opportunity> changeStage(int id, ChangeStageRequest request) async {
    final updated =
        await ref.read(crmRepositoryProvider).changeStage(id, request);
    ref.invalidate(pipelineSummaryProvider);
    ref.invalidate(opportunityDetailProvider(id));
    await refresh();
    return updated;
  }

  Future<Opportunity> create(OpportunityRequest request) async {
    final created =
        await ref.read(crmRepositoryProvider).createOpportunity(request);
    ref.invalidate(pipelineSummaryProvider);
    await refresh();
    return created;
  }

  /// Edits a deal's details.
  ///
  /// The summary is invalidated because the amount is editable here and the
  /// weighted forecast is derived from it — leaving the headline figures on
  /// the old number would have the board disagree with the row beneath it.
  Future<Opportunity> updateItem(int id, OpportunityRequest request) async {
    final updated =
        await ref.read(crmRepositoryProvider).updateOpportunity(id, request);
    replaceItem((opportunity) => opportunity.id == id, updated);
    ref.invalidate(pipelineSummaryProvider);
    ref.invalidate(opportunityDetailProvider(id));
    return updated;
  }

  Future<void> delete(int id) async {
    await ref.read(crmRepositoryProvider).deleteOpportunity(id);
    removeItem((opportunity) => opportunity.id == id);
    ref.invalidate(pipelineSummaryProvider);
  }
}

final opportunitiesProvider =
    AsyncNotifierProvider<OpportunitiesController, PagedState<Opportunity>>(
  OpportunitiesController.new,
);

final opportunityDetailProvider =
    FutureProvider.autoDispose.family<Opportunity, int>(
  (ref, id) => ref.watch(crmRepositoryProvider).opportunity(id),
);

final pipelineSummaryProvider = FutureProvider<PipelineSummary>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(crmRepositoryProvider).pipelineSummary();
});

class ClientsController extends AsyncNotifier<PagedState<Client>>
    with PagedLoader<Client> {
  @override
  Future<PagedState<Client>> build() {
    ref.watch(currentUserProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<Client>> fetchPage(int page) =>
      ref.read(crmRepositoryProvider).clients(page: page);

  Future<Client> create(CreateClientRequest request) async {
    final created = await ref.read(crmRepositoryProvider).createClient(request);
    await refresh();
    return created;
  }

  Future<Client> updateItem(int id, UpdateClientRequest request) async {
    final updated =
        await ref.read(crmRepositoryProvider).updateClient(id, request);
    replaceItem((client) => client.id == id, updated);
    ref.invalidate(clientDetailProvider(id));
    return updated;
  }

  /// Refused by the backend while the client still has an open opportunity,
  /// so the row is only dropped once the call has actually succeeded.
  Future<void> delete(int id) async {
    await ref.read(crmRepositoryProvider).deleteClient(id);
    removeItem((client) => client.id == id);
  }
}

final clientsProvider =
    AsyncNotifierProvider<ClientsController, PagedState<Client>>(
  ClientsController.new,
);

final clientDetailProvider = FutureProvider.autoDispose.family<Client, int>(
  (ref, id) => ref.watch(crmRepositoryProvider).client(id),
);
