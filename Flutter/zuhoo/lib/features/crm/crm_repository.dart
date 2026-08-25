import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import 'crm_models.dart';

/// Which slice of leads to show. Each is a server-side definition rather than
/// a client-side filter, so "stale" means whatever the backend says it means
/// and cannot drift from the web app's answer.
enum LeadView { mine, all, highPriority, neverContacted, stale, unassigned }

class CrmRepository {
  CrmRepository(this._api);

  final ApiClient _api;

  static const _leads = '/crm/leads';
  static const _opportunities = '/crm/opportunities';
  static const _clients = '/clients';

  // ── Leads ───────────────────────────────────────────────────

  Future<PagedResponse<Lead>> leads(
    LeadView view, {
    int page = 0,
    int size = 20,
  }) {
    final path = switch (view) {
      LeadView.mine => '$_leads/my',
      LeadView.all => _leads,
      LeadView.highPriority => '$_leads/high-priority',
      LeadView.neverContacted => '$_leads/never-contacted',
      LeadView.stale => '$_leads/stale',
      LeadView.unassigned => '$_leads/unassigned',
    };
    return _api.getPaged(path, Lead.fromJson, page: page, size: size);
  }

  Future<Lead> lead(int id) async {
    final json = await _api.get<Map<String, dynamic>>('$_leads/$id');
    return Lead.fromJson(json);
  }

  Future<Lead> createLead(CreateLeadRequest request) async {
    final json = await _api.post<Map<String, dynamic>>(_leads, request.toJson());
    return Lead.fromJson(json);
  }

  Future<Lead> updateLead(int id, UpdateLeadRequest request) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_leads/$id',
      request.toJson(),
    );
    return Lead.fromJson(json);
  }

  /// Soft-delete. 204, no body.
  Future<void> deleteLead(int id) => _api.delete<dynamic>('$_leads/$id');

  /// Turns a qualified lead into an opportunity. No client is created here —
  /// that happens later, if and when the opportunity is won.
  Future<Opportunity> convertLead(int id, ConvertLeadRequest request) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_leads/$id/convert-to-opportunity',
      request.toJson(),
    );
    return Opportunity.fromJson(json);
  }

  /// Lead activities have their own endpoints: the generic `/crm/activities`
  /// one requires a clientId or opportunityId, neither of which a lead has.
  Future<List<CrmActivity>> leadActivities(int id) async {
    final page = await _api.getPaged(
      '$_leads/$id/activities',
      CrmActivity.fromJson,
      page: 0,
      size: 50,
    );
    final activities = [...page.content]
      ..sort((a, b) => b.activityDate.compareTo(a.activityDate));
    return activities;
  }

  Future<CrmActivity> logActivity(int id, LogActivityRequest request) async {
    final json = await _api.post<Map<String, dynamic>>(
      '$_leads/$id/activities',
      request.toJson(),
    );
    return CrmActivity.fromJson(json);
  }

  // ── Opportunities ───────────────────────────────────────────

  Future<PagedResponse<Opportunity>> opportunities({
    String? stage,
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        _opportunities,
        Opportunity.fromJson,
        page: page,
        size: size,
        query: {'stage': stage},
      );

  Future<Opportunity> opportunity(int id) async {
    final json = await _api.get<Map<String, dynamic>>('$_opportunities/$id');
    return Opportunity.fromJson(json);
  }

  /// Opens a deal directly, rather than by converting a lead. The service
  /// requires a `clientId` on this path — there is no client-less create here,
  /// unlike the lead-conversion route.
  Future<Opportunity> createOpportunity(OpportunityRequest request) async {
    final json = await _api.post<Map<String, dynamic>>(
      _opportunities,
      request.toJson(),
    );
    return Opportunity.fromJson(json);
  }

  /// Edits a deal's details. Not its stage — that is [changeStage].
  ///
  /// Rejected by the backend for a WON or LOST deal, so the UI only offers it
  /// while the deal is still open.
  Future<Opportunity> updateOpportunity(
    int id,
    OpportunityRequest request,
  ) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_opportunities/$id',
      request.toJson(),
    );
    return Opportunity.fromJson(json);
  }

  /// Soft-delete. 204, no body.
  Future<void> deleteOpportunity(int id) =>
      _api.delete<dynamic>('$_opportunities/$id');

  Future<PipelineSummary> pipelineSummary() async {
    final json =
        await _api.get<Map<String, dynamic>>('$_opportunities/pipeline-summary');
    return PipelineSummary.fromJson(json);
  }

  Future<Opportunity> changeStage(int id, ChangeStageRequest request) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_opportunities/$id/stage',
      request.toJson(),
    );
    return Opportunity.fromJson(json);
  }

  /// Asks whether winning this deal would duplicate an existing client.
  ///
  /// Fails open, exactly as the web app does: a preview check that cannot
  /// complete must not stand between a rep and closing a deal. A null answer
  /// means "no duplicate, or we could not tell" and the caller proceeds.
  Future<DuplicateMatch?> wonDuplicateCheck(int id) async {
    try {
      final json =
          await _api.get<dynamic>('$_opportunities/$id/won-duplicate-check');
      return DuplicateMatch.tryFrom(json);
    } on ApiException {
      return null;
    }
  }

  // ── Clients ─────────────────────────────────────────────────

  Future<PagedResponse<Client>> clients({int page = 0, int size = 20}) =>
      _api.getPaged(_clients, Client.fromJson, page: page, size: size);

  Future<Client> client(int id) async {
    final json = await _api.get<Map<String, dynamic>>('$_clients/$id');
    return Client.fromJson(json);
  }

  Future<Client> createClient(CreateClientRequest request) async {
    final json =
        await _api.post<Map<String, dynamic>>(_clients, request.toJson());
    return Client.fromJson(json);
  }

  Future<Client> updateClient(int id, UpdateClientRequest request) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_clients/$id',
      request.toJson(),
    );
    return Client.fromJson(json);
  }

  /// Soft-delete, and the backend refuses it while the client still has an
  /// open opportunity rather than orphaning the deal. That arrives as a 400
  /// with a message worth showing verbatim, so this does not swallow it.
  Future<void> deleteClient(int id) => _api.delete<dynamic>('$_clients/$id');
}


/// Everything about contacts, tags and the activity timeline.
///
/// Kept as an extension rather than folded into [CrmRepository] so the
/// original file stays the shape it was — these are additions to the same
/// module, not a rewrite of it.
extension CrmContactsAndTags on CrmRepository {
  // ── Contacts ──────────────────────────────────────────────

  /// Every contact at one client. A bare list.
  Future<List<ClientContact>> contactsFor(int clientId) async {
    final list = await _api.get<List<dynamic>>('/clients/$clientId/contacts');
    return list
        .whereType<Map<String, dynamic>>()
        .map(ClientContact.fromJson)
        .toList(growable: false);
  }

  /// Every contact across every client, searchable. Paged.
  Future<PagedResponse<ClientContact>> allContacts({
    String? keyword,
    int page = 0,
    int size = 30,
  }) =>
      _api.getPaged(
        '/crm/contacts',
        ClientContact.fromJson,
        page: page,
        size: size,
        query: {if (keyword != null && keyword.isNotEmpty) 'keyword': keyword},
      );

  Future<ClientContact> createContact(
    int clientId,
    ClientContactRequest request,
  ) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/clients/$clientId/contacts',
      request.toJson(),
    );
    return ClientContact.fromJson(json);
  }

  /// Sends the whole contact — see [ClientContactRequest] for why an omitted
  /// field is cleared rather than left alone.
  Future<ClientContact> updateContact(
    int clientId,
    int id,
    ClientContactRequest request,
  ) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '/clients/$clientId/contacts/$id',
      request.toJson(),
    );
    return ClientContact.fromJson(json);
  }

  /// Makes them the one primary contact, clearing whoever held it.
  Future<ClientContact> makePrimaryContact(int clientId, int id) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '/clients/$clientId/contacts/$id/primary',
    );
    return ClientContact.fromJson(json);
  }

  Future<void> deleteContact(int clientId, int id) =>
      _api.delete<dynamic>('/clients/$clientId/contacts/$id');

  // ── Tags ──────────────────────────────────────────────────

  /// The shared vocabulary. A bare list.
  Future<List<Tag>> tags() async {
    final list = await _api.get<List<dynamic>>('/crm/tags');
    return list
        .whereType<Map<String, dynamic>>()
        .map(Tag.fromJson)
        .toList(growable: false);
  }

  Future<Tag> createTag(TagRequest request) async {
    final json =
        await _api.post<Map<String, dynamic>>('/crm/tags', request.toJson());
    return Tag.fromJson(json);
  }

  Future<Tag> updateTag(int id, TagRequest request) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '/crm/tags/$id',
      request.toJson(),
    );
    return Tag.fromJson(json);
  }

  /// Removes it from the vocabulary. Records already tagged with it lose the
  /// tag, which is why the screen asks first.
  Future<void> deleteTag(int id) => _api.delete<dynamic>('/crm/tags/$id');

  // ── Activities ────────────────────────────────────────────

  /// The timeline, optionally narrowed to one client or one opportunity.
  Future<PagedResponse<CrmActivity>> activities({
    int? clientId,
    int? opportunityId,
    int page = 0,
    int size = 30,
  }) =>
      _api.getPaged(
        '/crm/activities',
        CrmActivity.fromJson,
        page: page,
        size: size,
        query: {
          if (clientId != null) 'clientId': clientId,
          if (opportunityId != null) 'opportunityId': opportunityId,
        },
      );

  Future<CrmActivity> logActivity(CrmActivityRequest request) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/crm/activities',
      request.toJson(),
    );
    return CrmActivity.fromJson(json);
  }

  Future<CrmActivity> completeActivity(int id) async {
    final json =
        await _api.patch<Map<String, dynamic>>('/crm/activities/$id/complete');
    return CrmActivity.fromJson(json);
  }

  Future<void> deleteActivity(int id) =>
      _api.delete<dynamic>('/crm/activities/$id');

  /// A paragraph summarising what has happened with a client or an
  /// opportunity. Drafted, not saved.
  Future<String> summariseActivity({
    int? clientId,
    int? opportunityId,
  }) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/crm/activities/summary',
      query: {
        if (clientId != null) 'clientId': clientId,
        if (opportunityId != null) 'opportunityId': opportunityId,
      },
    );
    return json['summary'] as String? ?? '';
  }

  // ── Clients ───────────────────────────────────────────────

  /// Those still trading with, as a bare list. What a picker reads.
  Future<List<Client>> activeClients() async {
    final list = await _api.get<List<dynamic>>('/clients/active');
    return list
        .whereType<Map<String, dynamic>>()
        .map(Client.fromJson)
        .toList(growable: false);
  }

  /// Sends the client a portal invitation, and turns their portal access on.
  Future<Client> inviteToPortal(int id) async {
    final json =
        await _api.post<Map<String, dynamic>>('/clients/$id/invite-portal');
    return Client.fromJson(json);
  }
}

final crmRepositoryProvider = Provider<CrmRepository>(
  (ref) => CrmRepository(ref.watch(apiClientProvider)),
);
