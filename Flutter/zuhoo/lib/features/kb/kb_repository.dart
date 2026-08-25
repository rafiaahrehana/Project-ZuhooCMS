import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import '../../shared/paged_controller.dart';
import 'kb_models.dart';

/// The knowledge base, read-only.
///
/// Writing articles is `POST`/`PATCH /kb/articles` plus publish and archive —
/// an editor's job, and a long-form one. What a phone is for here is looking
/// something up while a customer is waiting, and saying whether it helped.
class KbRepository {
  KbRepository(this._api);

  final ApiClient _api;

  static const _base = '/kb/articles';

  /// Published articles only.
  ///
  /// Drafts and archived pieces are reachable through the same endpoint by
  /// passing a different status, and deliberately are not: a draft is not
  /// something to read out to a customer, and an archived one is wrong on
  /// purpose.
  Future<PagedResponse<KbArticle>> articles({
    String? keyword,
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        _base,
        KbArticle.fromJson,
        page: page,
        size: size,
        query: {
          'keyword': keyword,
          'status': KbArticleStatus.published,
        },
      );

  /// The full article. The list returns the same shape, but reading one is
  /// what increments its view count server-side.
  Future<KbArticle> article(int id) async {
    final json = await _api.get<Map<String, dynamic>>('$_base/$id');
    return KbArticle.fromJson(json);
  }

  /// Says the article helped. There is no matching "unhelpful" and no way to
  /// take it back, so the UI only ever offers it once per visit.
  Future<KbArticle> markHelpful(int id) async {
    final json = await _api.post<Map<String, dynamic>>('$_base/$id/helpful');
    return KbArticle.fromJson(json);
  }
}

final kbRepositoryProvider = Provider<KbRepository>(
  (ref) => KbRepository(ref.watch(apiClientProvider)),
);

/// The search term. Empty means "everything published".
class KbSearchController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? keyword) {
    final trimmed = keyword?.trim();
    final next = trimmed == null || trimmed.isEmpty ? null : trimmed;
    if (state == next) return;
    state = next;
  }
}

final kbSearchProvider =
    NotifierProvider<KbSearchController, String?>(KbSearchController.new);

class KbArticlesController extends AsyncNotifier<PagedState<KbArticle>>
    with PagedLoader<KbArticle> {
  @override
  Future<PagedState<KbArticle>> build() {
    ref.watch(currentUserProvider);
    ref.watch(kbSearchProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<KbArticle>> fetchPage(int page) =>
      ref.read(kbRepositoryProvider).articles(
            keyword: ref.read(kbSearchProvider),
            page: page,
          );

  /// Swaps a row after its helpful count changes, so the list behind the
  /// article agrees with what was just tapped.
  void apply(KbArticle updated) =>
      replaceItem((article) => article.id == updated.id, updated);
}

final kbArticlesProvider =
    AsyncNotifierProvider<KbArticlesController, PagedState<KbArticle>>(
  KbArticlesController.new,
);

final kbArticleProvider = FutureProvider.autoDispose.family<KbArticle, int>(
  (ref, id) => ref.read(kbRepositoryProvider).article(id),
);
