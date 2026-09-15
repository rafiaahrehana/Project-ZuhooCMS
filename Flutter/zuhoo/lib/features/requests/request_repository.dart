import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import 'proposal_models.dart';
import 'request_models.dart';
import 'request_workflow_models.dart';

class RequestRepository {
  RequestRepository(this._api);

  final ApiClient _api;

  static const _base = '/service-requests';
  static const _approvals = '/approvals';

  /// Requests raised by this user **as a portal client**.
  ///
  /// Client-scoped, not "mine" in the everyday sense: the backend looks up a
  /// Client row by user id and answers 400 "Client profile not found" for any
  /// staff account, which is most of this app's users. The screen only offers
  /// this list to a CLIENT, and the catch below is the backstop for anything
  /// that reaches it another way — a 400 here means "not applicable to you",
  /// not "something broke".
  Future<PagedResponse<ServiceRequest>> mine({int page = 0, int size = 20}) async {
    try {
      return await _api.getPaged(
        '$_base/my',
        ServiceRequest.fromJson,
        page: page,
        size: size,
      );
    } on ApiException catch (e) {
      if (e.statusCode == 400 || e.isForbidden || e.isNotFound) {
        return const PagedResponse<ServiceRequest>.empty();
      }
      rethrow;
    }
  }

  /// Requests assigned to this user to work on.
  Future<PagedResponse<ServiceRequest>> assignedToMe({
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        '$_base/assigned-to-me',
        ServiceRequest.fromJson,
        page: page,
        size: size,
      );

  Future<ServiceRequest> byId(int id) async {
    final json = await _api.get<Map<String, dynamic>>('$_base/$id');
    return ServiceRequest.fromJson(json);
  }

  Future<ServiceRequest> create(CreateServiceRequest request) async {
    final json = await _api.post<Map<String, dynamic>>(_base, request.toJson());
    return ServiceRequest.fromJson(json);
  }

  /// Corrects a request's own details.
  ///
  /// Not its status: moving a request along has its own endpoints, and routing
  /// it through here would skip the history the timeline is built from.
  /// Refused once the request is closed.
  Future<ServiceRequest> update(
    int id,
    UpdateServiceRequestRequest request,
  ) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_base/$id',
      request.toJson(),
    );
    return ServiceRequest.fromJson(json);
  }

  /// text/plain response.
  Future<void> cancel(int id) => _api.patchText('$_base/$id/cancel');

  Future<PagedResponse<RequestComment>> comments(
    int id, {
    int page = 0,
    int size = 30,
  }) =>
      _api.getPaged(
        '$_base/$id/comments',
        RequestComment.fromJson,
        page: page,
        size: size,
      );

  /// Visibility is deliberately not sent: the backend picks a role-aware
  /// default (a client's comment is PUBLIC, a staff member's is INTERNAL), and
  /// a phone guessing wrong would either leak an internal note to the client or
  /// hide a reply they were waiting for.
  Future<RequestComment> addComment(int id, String content) async {
    final json = await _api.post<Map<String, dynamic>>(
      '$_base/$id/comments',
      {'content': content.trim()},
    );
    return RequestComment.fromJson(json);
  }

  /// The status timeline. Optional: an employee without the permission to read
  /// history should still get the rest of the detail screen.
  Future<List<RequestStatusChange>> history(int id) async {
    try {
      final list = await _api.get<List<dynamic>>('$_base/$id/history');
      return list
          .whereType<Map<String, dynamic>>()
          .map(RequestStatusChange.fromJson)
          .toList(growable: false);
    } on ApiException catch (e) {
      if (e.isForbidden || e.isNotFound) return const [];
      rethrow;
    }
  }

  // ── Documents ───────────────────────────────────────────────
  // The file itself goes through `ApiClient.uploadDocument` first; this only
  // records the URL it comes back with against the request.

  Future<List<RequestDocument>> documents(int requestId) async {
    final list =
        await _api.get<List<dynamic>>('$_base/$requestId/documents');
    return list
        .whereType<Map<String, dynamic>>()
        .map(RequestDocument.fromJson)
        .toList(growable: false);
  }

  Future<RequestDocument> addDocument(
    int requestId, {
    required String fileName,
    required String fileUrl,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '$_base/$requestId/documents',
      {'fileName': fileName, 'fileUrl': fileUrl},
    );
    return RequestDocument.fromJson(json);
  }

  /// The active catalogue, for the raise-a-request sheet.
  Future<List<CatalogService>> activeServices() async {
    final list = await _api.get<List<dynamic>>('/services/active');
    return list
        .whereType<Map<String, dynamic>>()
        .map(CatalogService.fromJson)
        .toList(growable: false);
  }

  /// Adds a package to the company's catalogue.
  ///
  /// Role-gated only — `COMPANY_OWNER` or `EMPLOYEE`. There is no
  /// `SERVICE_PACKAGE_CREATE` code to check; the only permission in that family
  /// is VIEW, which the app uses as the closest configured proxy so the action
  /// does not appear for every employee in the company.
  Future<void> createPackage(CreateServicePackageRequest request) =>
      _api.post<dynamic>('/packages', request.toJson());

  /// Rates a completed request.
  ///
  /// Clients only, and only their own requests — see [SubmitReviewRequest].
  /// Posting again replaces the previous rating.
  Future<ServiceReview> submitReview(SubmitReviewRequest request) async {
    final json =
        await _api.post<Map<String, dynamic>>('/reviews', request.toJson());
    return ServiceReview.fromJson(json);
  }

  // ── Approvals ───────────────────────────────────────────────

  Future<PagedResponse<StageApproval>> pendingApprovals({
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        '$_approvals/pending',
        StageApproval.fromJson,
        page: page,
        size: size,
      );

  /// The note is omitted rather than sent as null when there isn't one — the
  /// web app's `{ decisionNotes }` drops an undefined key on serialisation, and
  /// sending an explicit null is a different thing to a validator that has to
  /// tell "not provided" from "provided as empty".
  Future<void> approve(int id, {String? notes}) => _api.post<dynamic>(
        '$_approvals/$id/approve',
        {
          if (notes != null && notes.trim().isNotEmpty)
            'decisionNotes': notes.trim(),
        },
      );

  /// The approvals raised against one request, whatever their state. A bare
  /// list, and open to the client as well — they are entitled to know their
  /// request is sitting waiting for somebody internal to sign it off.
  Future<List<StageApproval>> approvalsForRequest(int requestId) async {
    final list =
        await _api.get<List<dynamic>>('$_approvals/request/$requestId');
    return list
        .whereType<Map<String, dynamic>>()
        .map(StageApproval.fromJson)
        .toList(growable: false);
  }

  /// A rejection must say why — the backend requires the notes, and an
  /// unexplained rejection is useless to whoever has to act on it.
  Future<void> reject(int id, String notes) => _api.post<dynamic>(
        '$_approvals/$id/reject',
        {'decisionNotes': notes.trim()},
      );

  // -- The workflow behind a request ---------------------------

  /// The staff view of a request. Same shape as [byId] but computed rather
  /// than read: it fills in the AI summary and the task counts, and it is
  /// closed to clients.
  Future<ServiceRequest> summary(int id) async {
    final json = await _api.get<Map<String, dynamic>>('$_base/$id/summary');
    return ServiceRequest.fromJson(json);
  }

  /// Asks the assistant to turn rough notes into a reply. It drafts, it does
  /// not send — what comes back is text for a human to read, edit and post as
  /// a comment.
  Future<String> draftReply(int id, String roughNotes) async {
    final json = await _api.post<Map<String, dynamic>>(
      '$_base/$id/draft-reply',
      {'roughNotes': roughNotes},
    );
    return json['reply'] as String? ?? '';
  }

  /// Moves the request to a different status, with a reason for the history.
  Future<ServiceRequest> changeStatus(
    int id,
    String status, {
    String? reason,
  }) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_base/$id/status',
      {
        'status': status,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    return ServiceRequest.fromJson(json);
  }

  /// Hands the request to an employee. The id is in the path, not the body.
  Future<ServiceRequest> assignTo(int id, int employeeId) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_base/$id/assign/$employeeId',
    );
    return ServiceRequest.fromJson(json);
  }

  /// Marks the current workflow stage done and steps into the next one.
  ///
  /// Refused with a message when the next stage needs signing off — and that
  /// same refusal is what raises the approval request, so the first attempt at
  /// a gated stage is expected to fail.
  Future<ServiceRequest> advanceStage(int id) async {
    final json =
        await _api.post<Map<String, dynamic>>('$_base/$id/advance-stage');
    return ServiceRequest.fromJson(json);
  }

  /// Where the request has got to. Open to the client as well as staff.
  Future<StageProgress> stageProgress(int id) async {
    final json =
        await _api.get<Map<String, dynamic>>('$_base/$id/stage-progress');
    return StageProgress.fromJson(json);
  }

  // -- Tasks ---------------------------------------------------

  /// A bare list rather than a page.
  Future<List<RequestTask>> tasks(int id) async {
    final list = await _api.get<List<dynamic>>('$_base/$id/tasks');
    return list
        .whereType<Map<String, dynamic>>()
        .map(RequestTask.fromJson)
        .toList(growable: false);
  }

  Future<RequestTask> addTask(int id, TaskRequest request) async {
    final json = await _api.post<Map<String, dynamic>>(
      '$_base/$id/tasks',
      request.toJson(),
    );
    return RequestTask.fromJson(json);
  }

  Future<RequestTask> updateTask(
    int id,
    int taskId,
    TaskRequest request,
  ) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_base/$id/tasks/$taskId',
      request.toJson(),
    );
    return RequestTask.fromJson(json);
  }

  /// Answers plain text, not JSON.
  Future<void> deleteTask(int id, int taskId) =>
      _api.deleteText('$_base/$id/tasks/$taskId');

  // -- The quotation -------------------------------------------

  /// Quotes a price. This also drops the request into QUOTATION_PENDING and
  /// notifies the client, so it is not a quiet edit.
  Future<ServiceRequest> submitQuotation(
    int id,
    QuotationRequest request,
  ) async {
    final json = await _api.post<Map<String, dynamic>>(
      '$_base/$id/quotation',
      request.toJson(),
    );
    return ServiceRequest.fromJson(json);
  }

  /// Accepting raises an invoice for the agreed price as a side effect. Only
  /// a pending quotation can be accepted, and an expired one is refused —
  /// the backend flips it to EXPIRED on the way out.
  Future<ServiceRequest> acceptQuotation(int id) async {
    final json =
        await _api.post<Map<String, dynamic>>('$_base/$id/quotation/accept');
    return ServiceRequest.fromJson(json);
  }

  Future<ServiceRequest> rejectQuotation(int id, String reason) async {
    final json = await _api.post<Map<String, dynamic>>(
      '$_base/$id/quotation/reject',
      {'reason': reason.trim()},
    );
    return ServiceRequest.fromJson(json);
  }

  // -- What clients made of it ---------------------------------

  static const _reviews = '/reviews';

  /// Every review left for this company.
  Future<PagedResponse<ServiceReview>> reviews({
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(_reviews, ServiceReview.fromJson, page: page, size: size);

  /// Reviews of one service. Open to clients as well as staff — this is what
  /// sits under a service in the catalogue.
  Future<PagedResponse<ServiceReview>> reviewsForService(
    int hubServiceId, {
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        '$_reviews/service/$hubServiceId',
        ServiceReview.fromJson,
        page: page,
        size: size,
      );

  /// The company's average, across everything. A bare number, and null when
  /// nothing has been rated yet rather than a misleading zero.
  Future<double?> averageRating() async {
    final value = await _api.get<dynamic>('$_reviews/average-rating');
    return (value as num?)?.toDouble();
  }

  Future<double?> averageRatingForService(int hubServiceId) async {
    final value = await _api.get<dynamic>(
      '$_reviews/service/$hubServiceId/average-rating',
    );
    return (value as num?)?.toDouble();
  }

  Future<ServiceReview> review(int id) async {
    final json = await _api.get<Map<String, dynamic>>('$_reviews/$id');
    return ServiceReview.fromJson(json);
  }

  /// Takes a review down for good. There is no hiding it instead — the
  /// `published` flag on a review is not something any endpoint sets.
  Future<void> deleteReview(int id) => _api.delete<dynamic>('$_reviews/$id');

  // ── Proposals ───────────────────────────────────────────────
  // The pre-sales step before a quotation. Staff write and send; the client
  // accepts or asks for changes. `ProposalServiceImpl` enforces that split,
  // so each half is only ever called from the side that owns it.

  /// The proposal on a request, or null when there is not one yet.
  ///
  /// Having none is the ordinary case, not an error: the endpoint answers
  /// `200` with `Content-Length: 0` for any request nobody has drafted a
  /// proposal for, which is most of them.
  ///
  /// Read as `dynamic` and shape-checked rather than cast to a map, because an
  /// empty body reaches Dio as either null or an empty string depending on how
  /// it decodes the response, and `'' as Map` throws a `TypeError` — which is
  /// not a `DioException`, so it would slip past `ApiException.from` and
  /// surface as "Something went wrong" on a request that is simply new.
  Future<Proposal?> proposal(int requestId) async {
    final body = await _api.get<dynamic>('$_base/$requestId/proposal');
    if (body is! Map<String, dynamic> || body.isEmpty) return null;
    return Proposal.fromJson(body);
  }

  /// Creates the draft, or edits the existing one — one endpoint does both.
  ///
  /// Staff only, and refused once the proposal has been sent or accepted;
  /// [Proposal.canEdit] mirrors that rule so the form is not offered when the
  /// save would come back 400.
  Future<Proposal> saveProposal(int requestId, ProposalRequest request) async {
    final json = await _api.put<Map<String, dynamic>>(
      '$_base/$requestId/proposal',
      request.toJson(),
    );
    return Proposal.fromJson(json);
  }

  /// Puts it in front of the client. Also notifies them and posts a
  /// client-visible comment on the request, both backend-side.
  Future<Proposal> sendProposal(int requestId) async {
    final json = await _api.post<Map<String, dynamic>>(
      '$_base/$requestId/proposal/send',
    );
    return Proposal.fromJson(json);
  }

  /// The client's yes. Only from SENT, and only from a client account.
  Future<Proposal> acceptProposal(int requestId) async {
    final json = await _api.post<Map<String, dynamic>>(
      '$_base/$requestId/proposal/accept',
    );
    return Proposal.fromJson(json);
  }

  /// The client's "not quite". The feedback is optional to the backend, but
  /// the sheet asks for it — staff have to guess otherwise, and it is the only
  /// thing that travels back with the rejection.
  Future<Proposal> requestProposalChanges(int requestId, String? feedback) async {
    final trimmed = feedback?.trim();
    final json = await _api.post<Map<String, dynamic>>(
      '$_base/$requestId/proposal/request-changes',
      {if (trimmed != null && trimmed.isNotEmpty) 'feedback': trimmed},
    );
    return Proposal.fromJson(json);
  }

  /// Records an already-uploaded file against the proposal.
  ///
  /// Same two-step shape as a request document: the bytes go through
  /// `ApiClient.uploadDocument` first, and this stores the URL that comes back.
  Future<ProposalAttachment> addProposalAttachment(
    int requestId, {
    required String fileName,
    required String fileUrl,
    String? label,
  }) async {
    final trimmed = label?.trim();
    final json = await _api.post<Map<String, dynamic>>(
      '$_base/$requestId/proposal/attachments',
      {
        'fileName': fileName,
        'fileUrl': fileUrl,
        if (trimmed != null && trimmed.isNotEmpty) 'label': trimmed,
      },
    );
    return ProposalAttachment.fromJson(json);
  }

  Future<void> deleteProposalAttachment(int requestId, int attachmentId) =>
      _api.delete<dynamic>('$_base/$requestId/proposal/attachments/$attachmentId');
}

final requestRepositoryProvider = Provider<RequestRepository>(
  (ref) => RequestRepository(ref.watch(apiClientProvider)),
);
