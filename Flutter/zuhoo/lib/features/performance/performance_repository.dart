import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import '../../shared/paged_controller.dart';
import '../profile/employee_repository.dart';
import 'performance_models.dart';

/// Performance reviews.
///
/// Writing one is here now — nine competencies, the free-text sections and the
/// recommendations — brought over from the web app for parity. An earlier
/// version of this file left it out on the grounds that an appraisal belongs
/// on a desk, which is still true of the *reading* experience; what a phone is
/// good for is a manager filling in scores shortly after the conversation.
///
/// Still absent: **attachments**, which need a file picker and are the one
/// part of a review that is genuinely a desk task, and the **goals** field,
/// which the DTO takes as a hand-composed JSON array.
class PerformanceRepository {
  PerformanceRepository(this._api);

  final ApiClient _api;

  static const _base = '/hr/performance';

  Future<PagedResponse<PerformanceReview>> all({
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        _base,
        PerformanceReview.fromJson,
        page: page,
        size: size,
      );

  /// One person's reviews.
  ///
  /// Reachable without PERFORMANCE_VIEW when the id is the caller's own —
  /// `guardOwnReviewAccess` allows it deliberately, so this is what the
  /// personal tab uses.
  ///
  /// Read as a page, not a bare list: the endpoint returns
  /// `Page<PerformanceReviewResponse>`, so casting the body to a List threw
  /// and every employee's own reviews tab failed to load. One generous page
  /// rather than paging, because nobody has fifty reviews.
  Future<List<PerformanceReview>> forEmployee(int employeeId) async {
    final page = await _api.getPaged(
      '$_base/employee/$employeeId',
      PerformanceReview.fromJson,
      page: 0,
      size: 50,
    );
    return page.content;
  }

  Future<PerformanceReview> review(int id) async {
    final json = await _api.get<Map<String, dynamic>>('$_base/$id');
    return PerformanceReview.fromJson(json);
  }

  /// Opens a review. The reviewer is taken from the session, never the body —
  /// the service resolves it from the signed-in user's employee record, and
  /// answers "Employee profile not found" if they have none.
  Future<PerformanceReview> create(PerformanceReviewRequest request) async {
    final json =
        await _api.post<Map<String, dynamic>>(_base, request.toJson());
    return PerformanceReview.fromJson(json);
  }

  /// Edits the scores and write-ups.
  ///
  /// Refused once the review is finalised — "Cannot edit a finalised review" —
  /// so the UI hides the action rather than offering one that 400s.
  Future<PerformanceReview> update(
    int id,
    PerformanceReviewRequest request,
  ) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_base/$id',
      request.toJson(),
    );
    return PerformanceReview.fromJson(json);
  }

  /// Moves a review to the next stage. The backend decides which that is —
  /// there is no way to jump or to go back, so the UI offers one button.
  Future<PerformanceReview> advance(int id) async {
    final json = await _api.post<Map<String, dynamic>>('$_base/$id/advance');
    return PerformanceReview.fromJson(json);
  }

  /// Signs the review off. Irreversible.
  Future<PerformanceReview> finalise(int id) async {
    final json = await _api.patch<Map<String, dynamic>>('$_base/$id/finalise');
    return PerformanceReview.fromJson(json);
  }
}

final performanceRepositoryProvider = Provider<PerformanceRepository>(
  (ref) => PerformanceRepository(ref.watch(apiClientProvider)),
);

/// Everybody's reviews. Needs PERFORMANCE_VIEW.
class TeamReviewsController extends AsyncNotifier<PagedState<PerformanceReview>>
    with PagedLoader<PerformanceReview> {
  @override
  Future<PagedState<PerformanceReview>> build() {
    ref.watch(currentUserProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<PerformanceReview>> fetchPage(int page) =>
      ref.read(performanceRepositoryProvider).all(page: page);

  void apply(PerformanceReview updated) =>
      replaceItem((review) => review.id == updated.id, updated);

  Future<PerformanceReview> create(PerformanceReviewRequest request) async {
    final created =
        await ref.read(performanceRepositoryProvider).create(request);
    await refresh();
    // The subject may be looking at their own list.
    ref.invalidate(myReviewsProvider);
    return created;
  }

  /// Returns the server's version so the detail screen can adopt it — the
  /// overall score is recomputed on every write, and the client cannot guess
  /// it without re-implementing the averaging rule.
  Future<PerformanceReview> updateItem(
    int id,
    PerformanceReviewRequest request,
  ) async {
    final updated =
        await ref.read(performanceRepositoryProvider).update(id, request);
    apply(updated);
    ref.invalidate(myReviewsProvider);
    return updated;
  }
}

final teamReviewsProvider =
    AsyncNotifierProvider<TeamReviewsController, PagedState<PerformanceReview>>(
  TeamReviewsController.new,
);

/// The signed-in person's own reviews.
///
/// Depends on their employee record, which company owners do not have — the
/// screen explains that rather than showing an error.
final myReviewsProvider = FutureProvider<List<PerformanceReview>>((ref) async {
  final employee = await ref.watch(myEmployeeProvider.future);
  if (employee == null) return const [];
  return ref.read(performanceRepositoryProvider).forEmployee(employee.id);
});
