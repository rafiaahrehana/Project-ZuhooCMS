import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import '../../shared/paged_controller.dart';
import 'recruitment_models.dart';

/// Hiring: postings, the applications against them, and the interviews and
/// offers that follow.
///
/// Deliberately absent:
///
/// * **Hiring an applicant.** `POST /applications/{id}/hire` provisions a user
///   account and its body carries a plaintext `password` alongside department,
///   designation, manager, shift and start date. That is an onboarding form,
///   not a one-handed action, and it is gated on EMPLOYEE_CREATE rather than
///   APPLICATION_UPDATE — a different entitlement from everything else here.
/// * **The careers page and recruitment reports**, which are a CMS editor and
///   a wide table respectively.
///
/// Drafting an offer and opening a posting were both on that list until
/// recently and are now here, brought over from the web app for parity.
class RecruitmentRepository {
  RecruitmentRepository(this._api);

  final ApiClient _api;

  static const _jobs = '/recruitment/jobs';
  static const _base = '/recruitment';
  static const _interviews = '/recruitment/interviews';
  static const _offers = '/recruitment/offers';
  static const _candidates = '/recruitment/candidates';
  static const _talentPool = '/recruitment/talent-pool';

  // ── Postings ────────────────────────────────────────────────

  Future<PagedResponse<JobPosting>> jobs({int page = 0, int size = 20}) =>
      _api.getPaged(_jobs, JobPosting.fromJson, page: page, size: size);

  /// Opens a posting. It lands as a DRAFT — publishing it is [publishJob],
  /// deliberately a second step, so a half-written advert is not live the
  /// moment it is saved.
  Future<JobPosting> createJob(JobPostingRequest request) async {
    final json = await _api.post<Map<String, dynamic>>(_jobs, request.toJson());
    return JobPosting.fromJson(json);
  }

  /// Edits a posting. The same DTO as create — see [JobPostingRequest] for the
  /// fields the update assigns without a null check.
  Future<JobPosting> updateJob(int id, JobPostingRequest request) async {
    final json = await _api.put<Map<String, dynamic>>(
      '$_jobs/$id',
      request.toJson(),
    );
    return JobPosting.fromJson(json);
  }

  /// Puts a recruiter on it. The id travels as a **body**, not a path segment
  /// or a query parameter — the controller takes an `AssignRecruiterRequest`
  /// wrapping a single field.
  Future<JobPosting> assignRecruiter(int id, int recruiterId) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_jobs/$id/assign-recruiter',
      {'recruiterId': recruiterId},
    );
    return JobPosting.fromJson(json);
  }

  /// Moves an interview. The same DTO as scheduling one.
  Future<Interview> rescheduleInterview(
    int id,
    InterviewRequest request,
  ) async {
    final json = await _api.put<Map<String, dynamic>>(
      '$_interviews/$id',
      request.toJson(),
    );
    return Interview.fromJson(json);
  }

  /// How hiring is going. Every date is optional; without them the backend
  /// picks its own window.
  Future<RecruitmentKpis> kpis({String? from, String? to}) async {
    final json = await _api.get<Map<String, dynamic>>(
      '$_base/kpis',
      query: {
        if (from != null) 'from': from,
        if (to != null) 'to': to,
      },
    );
    return RecruitmentKpis.fromJson(json);
  }

  Future<JobPosting> publishJob(int id) async {
    final json = await _api.patch<Map<String, dynamic>>('$_jobs/$id/publish');
    return JobPosting.fromJson(json);
  }

  Future<JobPosting> closeJob(int id) async {
    final json = await _api.patch<Map<String, dynamic>>('$_jobs/$id/close');
    return JobPosting.fromJson(json);
  }

  // ── Applications ────────────────────────────────────────────

  Future<PagedResponse<JobApplication>> applications({
    String? status,
    int? jobPostingId,
    int page = 0,
    int size = 20,
  }) {
    // Two different endpoints rather than one with a filter: applications for
    // a posting live under the posting.
    final path = jobPostingId == null
        ? '$_base/applications'
        : '$_jobs/$jobPostingId/applications';
    return _api.getPaged(
      path,
      JobApplication.fromJson,
      page: page,
      size: size,
      query: {'status': status},
    );
  }

  Future<JobApplication> application(int id) async {
    final json =
        await _api.get<Map<String, dynamic>>('$_base/applications/$id');
    return JobApplication.fromJson(json);
  }

  Future<JobApplication> setApplicationStatus(int id, String status) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_base/applications/$id/status',
      {'status': status},
    );
    return JobApplication.fromJson(json);
  }

  /// Scores an applicant out of whatever scale the team uses; the backend
  /// averages whichever are present into `overallScore`.
  Future<JobApplication> evaluate(
    int id, {
    int? education,
    int? experience,
    int? technicalSkills,
    int? interview,
    int? communication,
  }) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_base/applications/$id/evaluate',
      {
        'scoreEducation': ?education,
        'scoreExperience': ?experience,
        'scoreTechnicalSkills': ?technicalSkills,
        'scoreInterview': ?interview,
        'scoreCommunication': ?communication,
      },
    );
    return JobApplication.fromJson(json);
  }

  // ── Interviews ──────────────────────────────────────────────

  /// Passing a status is not only a filter: the repository sorts **ascending**
  /// when one is given and descending when it is not. So the scheduled list
  /// arrives soonest-first, which is what an upcoming list wants, and the
  /// unfiltered list arrives newest-first, which is what a history wants.
  Future<PagedResponse<Interview>> interviews({
    String? status,
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        _interviews,
        Interview.fromJson,
        page: page,
        size: size,
        query: {'status': status},
      );

  /// Books an interview.
  ///
  /// Refused for an application that is already hired, rejected or withdrawn —
  /// "This application is closed" — so the action is hidden on those rather
  /// than offered and then bounced. Scheduling the first round also pulls the
  /// application forward to INTERVIEW_SCHEDULED, which is why the caller
  /// refreshes the application behind it.
  Future<Interview> scheduleInterview(InterviewRequest request) async {
    final json =
        await _api.post<Map<String, dynamic>>(_interviews, request.toJson());
    return Interview.fromJson(json);
  }

  Future<List<Interview>> interviewsForApplication(int applicationId) async {
    final list = await _api.get<List<dynamic>>(
      '$_interviews/application/$applicationId',
    );
    return list
        .whereType<Map<String, dynamic>>()
        .map(Interview.fromJson)
        .toList(growable: false);
  }

  Future<Interview> submitFeedback(
    int id, {
    int? rating,
    String? strengths,
    String? concerns,
    String? recommendation,
    bool noShow = false,
  }) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_interviews/$id/feedback',
      {
        'rating': ?rating,
        if (strengths != null && strengths.trim().isNotEmpty)
          'strengths': strengths.trim(),
        if (concerns != null && concerns.trim().isNotEmpty)
          'concerns': concerns.trim(),
        'recommendation': ?recommendation,
        'noShow': noShow,
      },
    );
    return Interview.fromJson(json);
  }

  Future<Interview> cancelInterview(int id) async {
    final json =
        await _api.patch<Map<String, dynamic>>('$_interviews/$id/cancel');
    return Interview.fromJson(json);
  }

  // ── Offers ──────────────────────────────────────────────────

  Future<List<JobOffer>> offersForApplication(int applicationId) async {
    final list = await _api.get<List<dynamic>>(
      '$_offers/application/$applicationId',
    );
    return list
        .whereType<Map<String, dynamic>>()
        .map(JobOffer.fromJson)
        .toList(growable: false);
  }

  Future<JobOffer> offerTransition(int id, String action, {String? reason}) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_offers/$id/$action',
      {if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()},
    );
    return JobOffer.fromJson(json);
  }

  /// Drafts an offer. It is created unsent — putting it in front of the
  /// candidate is the separate `send` transition, so the numbers can be
  /// checked before anyone sees them. Creating one moves the application to
  /// OFFER_PENDING, so the caller refreshes the application behind it.
  ///
  /// Refused when the application already holds a live offer: "a second offer
  /// while one is pending is how companies double-commit by accident".
  Future<JobOffer> createOffer(OfferRequest request) async {
    final json =
        await _api.post<Map<String, dynamic>>(_offers, request.toJson());
    return JobOffer.fromJson(json);
  }

  // ── Candidates ──────────────────────────────────────────────
  // The person, independent of any one application.

  Future<PagedResponse<Candidate>> candidates({
    String? q,
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        _candidates,
        Candidate.fromJson,
        page: page,
        size: size,
        query: {'q': q},
      );

  Future<Candidate> candidate(int id) async {
    final json = await _api.get<Map<String, dynamic>>('$_candidates/$id');
    return Candidate.fromJson(json);
  }

  Future<List<JobApplication>> candidateApplications(int id) async {
    final list =
        await _api.get<List<dynamic>>('$_candidates/$id/applications');
    return list
        .whereType<Map<String, dynamic>>()
        .map(JobApplication.fromJson)
        .toList(growable: false);
  }

  Future<Candidate> updateCandidate(int id, CandidateRequest request) async {
    final json = await _api.put<Map<String, dynamic>>(
      '$_candidates/$id',
      request.toJson(),
    );
    return Candidate.fromJson(json);
  }

  /// Needs APPLICATION_DELETE, which is a different code from the
  /// APPLICATION_UPDATE that covers editing — somebody may edit a candidate
  /// without being able to remove one.
  Future<void> deleteCandidate(int id) =>
      _api.delete<dynamic>('$_candidates/$id');

  /// Removes an application. `deleteText`, not `delete`: the endpoint is
  /// declared `ResponseEntity<String>` and answers with the bare words
  /// "Deleted successfully", which is not JSON.
  Future<void> deleteApplication(int id) =>
      _api.deleteText('$_base/applications/$id');

  // ── Talent pool ─────────────────────────────────────────────
  // Three ways in: pooling an existing application in one tap, composing an
  // entry by hand, and editing one already there. The last two take
  // `TalentPoolRequest` — a different shape from a candidate's, despite the
  // backend naming both DTOs `CandidateRequest`.

  Future<PagedResponse<TalentPoolCandidate>> talentPool({
    String? keyword,
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        _talentPool,
        TalentPoolCandidate.fromJson,
        page: page,
        size: size,
        query: {'keyword': keyword},
      );

  Future<TalentPoolCandidate> poolApplication(
    int applicationId, {
    String? reason,
    String? notes,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '$_talentPool/from-application/$applicationId',
      {
        'reason': ?reason,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
    );
    return TalentPoolCandidate.fromJson(json);
  }

  Future<TalentPoolCandidate> addToTalentPool(TalentPoolRequest request) async {
    final json = await _api.post<Map<String, dynamic>>(
      _talentPool,
      request.toJson(),
    );
    return TalentPoolCandidate.fromJson(json);
  }

  Future<TalentPoolCandidate> updateTalentPoolEntry(
    int id,
    TalentPoolRequest request,
  ) async {
    final json = await _api.put<Map<String, dynamic>>(
      '$_talentPool/$id',
      request.toJson(),
    );
    return TalentPoolCandidate.fromJson(json);
  }

  Future<void> removeFromTalentPool(int id) =>
      _api.delete<dynamic>('$_talentPool/$id');
}

final recruitmentRepositoryProvider = Provider<RecruitmentRepository>(
  (ref) => RecruitmentRepository(ref.watch(apiClientProvider)),
);

class JobsController extends AsyncNotifier<PagedState<JobPosting>>
    with PagedLoader<JobPosting> {
  @override
  Future<PagedState<JobPosting>> build() {
    ref.watch(currentUserProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<JobPosting>> fetchPage(int page) =>
      ref.read(recruitmentRepositoryProvider).jobs(page: page);

  void apply(JobPosting updated) =>
      replaceItem((job) => job.id == updated.id, updated);

  /// A new posting lands as a DRAFT at the top of the list, so this reloads
  /// rather than inserting — the server decides the ordering.
  Future<JobPosting> create(JobPostingRequest request) async {
    final created =
        await ref.read(recruitmentRepositoryProvider).createJob(request);
    await refresh();
    return created;
  }

  /// An edit does not move the posting, so the row is swapped in place.
  Future<JobPosting> update(int id, JobPostingRequest request) async {
    final updated =
        await ref.read(recruitmentRepositoryProvider).updateJob(id, request);
    apply(updated);
    return updated;
  }

  /// Puts a recruiter on a posting.
  Future<JobPosting> assignRecruiter(int id, int recruiterId) async {
    final updated = await ref
        .read(recruitmentRepositoryProvider)
        .assignRecruiter(id, recruiterId);
    apply(updated);
    return updated;
  }
}

final jobsProvider =
    AsyncNotifierProvider<JobsController, PagedState<JobPosting>>(
  JobsController.new,
);

/// Which pipeline stage the applications list is narrowed to. Null is all.
class ApplicationFilterController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? status) {
    if (state == status) return;
    state = status;
  }
}

final applicationFilterProvider =
    NotifierProvider<ApplicationFilterController, String?>(
  ApplicationFilterController.new,
);

class ApplicationsController extends AsyncNotifier<PagedState<JobApplication>>
    with PagedLoader<JobApplication> {
  @override
  Future<PagedState<JobApplication>> build() {
    ref.watch(currentUserProvider);
    ref.watch(applicationFilterProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<JobApplication>> fetchPage(int page) =>
      ref.read(recruitmentRepositoryProvider).applications(
            status: ref.read(applicationFilterProvider),
            page: page,
          );

  void apply(JobApplication updated) {
    final filter = ref.read(applicationFilterProvider);
    // A status change can move the row out of the stage being viewed.
    if (filter != null && updated.status != filter) {
      removeItem((application) => application.id == updated.id);
    } else {
      replaceItem((application) => application.id == updated.id, updated);
    }
  }
}

final applicationsProvider =
    AsyncNotifierProvider<ApplicationsController, PagedState<JobApplication>>(
  ApplicationsController.new,
);

/// Interviews still to happen, soonest first.
class UpcomingInterviewsController extends AsyncNotifier<PagedState<Interview>>
    with PagedLoader<Interview> {
  @override
  Future<PagedState<Interview>> build() {
    ref.watch(currentUserProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<Interview>> fetchPage(int page) =>
      ref.read(recruitmentRepositoryProvider).interviews(
            status: InterviewStatus.scheduled,
            page: page,
          );

  void apply(Interview updated) {
    // Feedback and cancellation both move an interview out of SCHEDULED, so
    // it leaves this list rather than sitting in it with the wrong state.
    if (updated.status != InterviewStatus.scheduled) {
      removeItem((interview) => interview.id == updated.id);
    } else {
      replaceItem((interview) => interview.id == updated.id, updated);
    }
  }
}

final upcomingInterviewsProvider =
    AsyncNotifierProvider<UpcomingInterviewsController, PagedState<Interview>>(
  UpcomingInterviewsController.new,
);

final applicationInterviewsProvider =
    FutureProvider.autoDispose.family<List<Interview>, int>(
  (ref, applicationId) => ref
      .read(recruitmentRepositoryProvider)
      .interviewsForApplication(applicationId),
);

final applicationOffersProvider =
    FutureProvider.autoDispose.family<List<JobOffer>, int>(
  (ref, applicationId) =>
      ref.read(recruitmentRepositoryProvider).offersForApplication(applicationId),
);

// ── Candidates ────────────────────────────────────────────────

class CandidateSearchController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? keyword) {
    final trimmed = keyword?.trim();
    final next = trimmed == null || trimmed.isEmpty ? null : trimmed;
    if (state == next) return;
    state = next;
  }
}

final candidateSearchProvider =
    NotifierProvider<CandidateSearchController, String?>(
  CandidateSearchController.new,
);

class CandidatesController extends AsyncNotifier<PagedState<Candidate>>
    with PagedLoader<Candidate> {
  @override
  Future<PagedState<Candidate>> build() {
    ref.watch(currentUserProvider);
    ref.watch(candidateSearchProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<Candidate>> fetchPage(int page) =>
      ref.read(recruitmentRepositoryProvider).candidates(
            q: ref.read(candidateSearchProvider),
            page: page,
          );

  /// Returns the server's version so the detail screen — which fetches the
  /// candidate into its own state rather than watching a provider — can adopt
  /// it without a second round trip.
  Future<Candidate> updateItem(int id, CandidateRequest request) async {
    final updated = await ref
        .read(recruitmentRepositoryProvider)
        .updateCandidate(id, request);
    replaceItem((candidate) => candidate.id == id, updated);
    return updated;
  }

  Future<void> delete(int id) async {
    await ref.read(recruitmentRepositoryProvider).deleteCandidate(id);
    removeItem((candidate) => candidate.id == id);
  }
}

final candidatesProvider =
    AsyncNotifierProvider<CandidatesController, PagedState<Candidate>>(
  CandidatesController.new,
);

final candidateApplicationsProvider =
    FutureProvider.autoDispose.family<List<JobApplication>, int>(
  (ref, candidateId) => ref
      .read(recruitmentRepositoryProvider)
      .candidateApplications(candidateId),
);

// ── Talent pool ───────────────────────────────────────────────

class TalentPoolSearchController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? keyword) {
    final trimmed = keyword?.trim();
    final next = trimmed == null || trimmed.isEmpty ? null : trimmed;
    if (state == next) return;
    state = next;
  }
}

final talentPoolSearchProvider =
    NotifierProvider<TalentPoolSearchController, String?>(
  TalentPoolSearchController.new,
);

class TalentPoolListController
    extends AsyncNotifier<PagedState<TalentPoolCandidate>>
    with PagedLoader<TalentPoolCandidate> {
  @override
  Future<PagedState<TalentPoolCandidate>> build() {
    ref.watch(currentUserProvider);
    ref.watch(talentPoolSearchProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<TalentPoolCandidate>> fetchPage(int page) =>
      ref.read(recruitmentRepositoryProvider).talentPool(
            keyword: ref.read(talentPoolSearchProvider),
            page: page,
          );

  void removeCandidate(int id) => removeItem((c) => c.id == id);

  Future<TalentPoolCandidate> add(TalentPoolRequest request) async {
    final created =
        await ref.read(recruitmentRepositoryProvider).addToTalentPool(request);
    await refresh();
    return created;
  }

  Future<TalentPoolCandidate> updateItem(int id, TalentPoolRequest request) async {
    final updated = await ref
        .read(recruitmentRepositoryProvider)
        .updateTalentPoolEntry(id, request);
    replaceItem((c) => c.id == id, updated);
    return updated;
  }
}

final talentPoolProvider = AsyncNotifierProvider<TalentPoolListController,
    PagedState<TalentPoolCandidate>>(
  TalentPoolListController.new,
);
