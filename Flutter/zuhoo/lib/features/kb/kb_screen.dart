import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/primitives.dart';
import 'kb_models.dart';
import 'kb_repository.dart';

/// The knowledge base: what to tell a customer, looked up while they wait.
class KbScreen extends ConsumerWidget {
  const KbScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final permissions = ref.watch(permissionControllerProvider);

    if (!permissions.loaded && permissions.codes.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Knowledge base')),
        body: const Loader(),
      );
    }

    if (!permissions.has(KbPermissions.view)) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Knowledge base')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Not available to you',
          message:
              'Reading the knowledge base needs its own permission. Your '
              'administrator can grant it.',
        ),
      );
    }

    final controller = ref.read(kbArticlesProvider.notifier);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Knowledge base')),
      body: Column(
        children: [
          const _SearchField(),
          Expanded(
            child: PagedListView<KbArticle>(
              async: ref.watch(kbArticlesProvider),
              onRefresh: controller.refresh,
              onLoadMore: () => guardListAction(context, controller.loadMore),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              emptyIcon: Icons.menu_book_outlined,
              emptyTitle: 'Nothing here',
              emptyMessage:
                  'No published article matches that. Try a different word, or '
                  'clear the search.',
              errorMessage: 'Could not load the knowledge base.',
              itemBuilder: (context, article) => _ArticleCard(article: article),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Debounced for the same reason the directory's is: every change restarts a
  /// paged request, and an earlier slower one must not land last.
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(kbSearchProvider.notifier).set(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _controller,
        onChanged: _onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search articles',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close_rounded, size: 18, color: bos.muted),
                  tooltip: 'Clear',
                  onPressed: () {
                    _controller.clear();
                    _debounce?.cancel();
                    ref.read(kbSearchProvider.notifier).set(null);
                    setState(() {});
                  },
                ),
        ),
      ),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  const _ArticleCard({required this.article});

  final KbArticle article;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => KbArticleScreen.open(context, article: article),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                article.title,
                style: TextStyle(
                  color: bos.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (article.preview != null) ...[
                const SizedBox(height: 4),
                Text(
                  article.preview!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: bos.textSecondary,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  if (article.categoryName != null) ...[
                    Icon(Icons.folder_outlined, size: 13, color: bos.muted),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        article.categoryName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: bos.muted, fontSize: 11.5),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Icon(Icons.thumb_up_outlined, size: 13, color: bos.muted),
                  const SizedBox(width: 4),
                  Text(
                    '${article.helpfulCount}',
                    style: TextStyle(color: bos.muted, fontSize: 11.5),
                  ),
                  const Spacer(),
                  if (article.clientVisible)
                    const StatusChip(
                      'PUBLISHED',
                      label: 'Client-visible',
                      dense: true,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One article, and the one thing worth doing with it on a phone.
class KbArticleScreen extends ConsumerStatefulWidget {
  const KbArticleScreen({super.key, required this.article});

  final KbArticle article;

  static void open(BuildContext context, {required KbArticle article}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => KbArticleScreen(article: article)),
    );
  }

  @override
  ConsumerState<KbArticleScreen> createState() => _KbArticleScreenState();
}

class _KbArticleScreenState extends ConsumerState<KbArticleScreen> {
  /// Once per visit. There is no way to take it back server-side, so offering
  /// it again would only let somebody inflate a count by tapping twice.
  bool _saidHelpful = false;
  bool _busy = false;

  Future<void> _markHelpful(KbArticle article) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated =
          await ref.read(kbRepositoryProvider).markHelpful(article.id);
      ref.read(kbArticlesProvider.notifier).apply(updated);
      if (!mounted) return;
      setState(() => _saidHelpful = true);
      messenger.showSnackBar(
        const SnackBar(content: Text('Noted — thanks.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not record that.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    // Opened with the row that was tapped so the title is on screen at once,
    // then upgraded to the full record — the list carries a summary, and the
    // body only arrives with the article itself.
    final full = ref.watch(kbArticleProvider(widget.article.id));
    final article = full.valueOrNull ?? widget.article;

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Article')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            article.title,
            style: TextStyle(
              color: bos.text,
              fontSize: 21,
              fontWeight: FontWeight.w700,
              height: 1.25,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (article.authorName != null) ...[
                Text(
                  article.authorName!,
                  style: TextStyle(color: bos.muted, fontSize: 12.5),
                ),
                const SizedBox(width: 10),
              ],
              if (article.publishedAt != null)
                Text(
                  Fmt.date(article.publishedAt),
                  style: TextStyle(color: bos.muted, fontSize: 12.5),
                ),
            ],
          ),
          if (article.keywordList.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final keyword in article.keywordList)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: bos.bgSubtle,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: bos.borderLight),
                    ),
                    child: Text(
                      keyword,
                      style: TextStyle(color: bos.muted, fontSize: 11.5),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          if (full.isLoading && article.content == null)
            const Loader(padding: 24)
          else if (full.hasError && article.content == null)
            const AppCard(
              child: MessageBanner.info('Could not load the article body.'),
            )
          else
            AppCard(
              padding: const EdgeInsets.all(18),
              child: SelectableText(
                article.content?.trim().isNotEmpty == true
                    ? article.content!.trim()
                    : (article.summary ?? 'This article has no body yet.'),
                style: TextStyle(color: bos.text, fontSize: 14.5, height: 1.55),
              ),
            ),
          const SizedBox(height: 20),
          if (_busy)
            const Loader(padding: 8)
          else if (_saidHelpful)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_rounded, size: 17, color: bos.success),
                const SizedBox(width: 6),
                Text(
                  'Marked as helpful',
                  style: TextStyle(color: bos.success, fontSize: 13.5),
                ),
              ],
            )
          else
            OutlinedButton.icon(
              onPressed: () => _markHelpful(article),
              icon: const Icon(Icons.thumb_up_outlined, size: 17),
              label: const Text('This helped'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
            ),
        ],
      ),
    );
  }
}
