import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/paged_response.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/config_list.dart';
import '../../shared/widgets/form_sheet.dart';
import '../../shared/widgets/prompts.dart';
import 'kb_models.dart';
import 'kb_repository.dart';

/// Which state of article the authoring list is showing. Null is everything.
class KbStatusFilterController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? status) => state = status;
}

final kbStatusFilterProvider =
    NotifierProvider<KbStatusFilterController, String?>(
  KbStatusFilterController.new,
);

/// Every article, whatever state it is in.
final kbAllArticlesProvider =
    FutureProvider.autoDispose<List<KbArticle>>((ref) async {
  final status = ref.watch(kbStatusFilterProvider);
  final PagedResponse<KbArticle> page =
      await ref.read(kbRepositoryProvider).allArticles(status: status, size: 50);
  return page.content;
});

/// Writing the knowledge base rather than reading it.
///
/// Kept apart from the reading screen because the two want opposite things.
/// A reader wants published articles and nothing else; an author needs to see
/// the drafts, and half of what they do — publish, archive — is meaningless to
/// a reader.
class KbAuthoringScreen extends ConsumerWidget {
  const KbAuthoringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final permissions = ref.watch(permissionControllerProvider);
    final canCreate = permissions.has(KbPermissions.create);
    final canEdit = permissions.has(KbPermissions.update);
    final status = ref.watch(kbStatusFilterProvider);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Articles')),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => showArticleSheet(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Write one'),
            )
          : null,
      body: ConfigList<KbArticle>(
        async: ref.watch(kbAllArticlesProvider),
        onRefresh: () async => ref.invalidate(kbAllArticlesProvider),
        emptyIcon: Icons.article_outlined,
        emptyTitle: status == null ? 'Nothing written yet' : 'Nothing here',
        emptyMessage: status == null
            ? 'The knowledge base is empty. An article is whatever your team '
                'ends up explaining twice.'
            : 'No articles in that state.',
        errorMessage: 'Could not load the articles.',
        header: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: FilterBar(
            selected: status,
            options: const [
              (value: null, label: 'All'),
              (value: KbArticleStatus.draft, label: 'Drafts'),
              (value: KbArticleStatus.published, label: 'Published'),
              (value: KbArticleStatus.archived, label: 'Archived'),
            ],
            onSelected: ref.read(kbStatusFilterProvider.notifier).set,
          ),
        ),
        itemBuilder: (context, article) => _ArticleRow(
          article: article,
          canEdit: canEdit,
        ),
      ),
    );
  }
}

class _ArticleRow extends ConsumerStatefulWidget {
  const _ArticleRow({required this.article, required this.canEdit});

  final KbArticle article;
  final bool canEdit;

  @override
  ConsumerState<_ArticleRow> createState() => _ArticleRowState();
}

class _ArticleRowState extends ConsumerState<_ArticleRow> {
  bool _busy = false;

  Future<void> _run(
    Future<KbArticle> Function(KbRepository) action,
    String done,
  ) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action(ref.read(kbRepositoryProvider));
      ref.invalidate(kbAllArticlesProvider);
      // The reading list only shows published articles, and this may have just
      // changed which ones those are.
      ref.invalidate(kbArticlesProvider);
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('That did not go through.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archive() async {
    final confirmed = await confirmAction(
      context,
      title: 'Archive this article?',
      message: 'It stops being findable. Nothing is deleted, and publishing '
          'again brings it straight back.',
      action: 'Archive',
    );
    if (!confirmed || !mounted) return;
    await _run(
      (repo) => repo.archive(widget.article.id),
      'Archived.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final article = widget.article;

    final facts = <String>[
      if (article.categoryName != null) article.categoryName!,
      if (article.clientVisible) 'clients can see it',
      '${article.viewCount} views',
      if (article.publishedAt != null)
        'published ${Fmt.dateShort(article.publishedAt)}',
    ];

    return ConfigRow(
      title: article.title,
      subtitle: facts.join(' · '),
      active: article.isPublished,
      inactiveLabel: Fmt.label(article.status),
      busy: _busy,
      onEdit: widget.canEdit
          ? () => showArticleSheet(context, article: article)
          : null,
      actions: [
        if (widget.canEdit && article.status != KbArticleStatus.published)
          RowAction(
            label: 'Publish',
            onSelected: () => _run(
              (repo) => repo.publish(article.id),
              'Published.',
            ),
          ),
        if (widget.canEdit && article.status != KbArticleStatus.archived)
          RowAction(
            label: 'Archive',
            destructive: true,
            onSelected: _archive,
          ),
      ],
    );
  }
}

/// Writing an article, or rewriting one.
///
/// An edit seeds every field from the article first, including the ones this
/// form does not show. The endpoint overwrites whatever it is sent rather than
/// merging, so anything left out of the payload would be lost.
Future<void> showArticleSheet(
  BuildContext context, {
  KbArticle? article,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ArticleSheet(article: article),
    );

class _ArticleSheet extends ConsumerStatefulWidget {
  const _ArticleSheet({this.article});

  final KbArticle? article;

  @override
  ConsumerState<_ArticleSheet> createState() => _ArticleSheetState();
}

class _ArticleSheetState extends ConsumerState<_ArticleSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title =
      TextEditingController(text: widget.article?.title ?? '');
  late final TextEditingController _summary =
      TextEditingController(text: widget.article?.summary ?? '');
  late final TextEditingController _content =
      TextEditingController(text: widget.article?.content ?? '');
  late final TextEditingController _keywords =
      TextEditingController(text: widget.article?.keywords ?? '');
  late bool _clientVisible = widget.article?.clientVisible ?? false;

  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _summary.dispose();
    _content.dispose();
    _keywords.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(kbRepositoryProvider);

      // An edit starts from the whole article and overwrites only what this
      // form shows. The category and the related service are not on the form
      // and would be cleared if they were not carried across — the endpoint
      // assigns every field it is sent, null included.
      final existing = widget.article;
      final request = (existing == null
              ? const KbArticleRequest(
                  title: '',
                  content: '',
                  clientVisible: false,
                )
              : KbArticleRequest.from(existing))
          .copyWith(
        title: _title.text.trim(),
        content: _content.text.trim(),
        clientVisible: _clientVisible,
        summary: _summary.text.trim(),
        keywords: _keywords.text.trim(),
      );

      if (widget.article == null) {
        await repo.create(request);
      } else {
        await repo.update(widget.article!.id, request);
      }
      ref.invalidate(kbAllArticlesProvider);
      ref.invalidate(kbArticlesProvider);
      if (widget.article != null) {
        ref.invalidate(kbArticleProvider(widget.article!.id));
      }
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not save that article.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: widget.article == null ? 'New article' : 'Edit article',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: widget.article == null ? 'Save as a draft' : 'Save',
      submitting: _busy,
      onSubmit: _submit,
      children: [
        TextFormField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Title'),
          validator: (value) =>
              (value?.trim().isEmpty ?? true) ? 'A title, please.' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _summary,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Summary',
            hintText: 'The one line somebody sees in a list of results.',
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _content,
          maxLines: 10,
          minLines: 6,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'The article'),
          validator: (value) => (value?.trim().isEmpty ?? true)
              ? 'An article needs something in it.'
              : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _keywords,
          decoration: const InputDecoration(
            labelText: 'Keywords',
            hintText: 'refund, cancellation, sla',
          ),
        ),
        const SizedBox(height: 4),
        SwitchListTile.adaptive(
          value: _clientVisible,
          onChanged: (value) => setState(() => _clientVisible = value),
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Clients can read it',
            style: TextStyle(color: bos.text, fontSize: 14),
          ),
          subtitle: Text(
            'Off means staff only. Worth checking before you publish.',
            style: TextStyle(color: bos.muted, fontSize: 12),
          ),
        ),
        if (widget.article == null)
          Text(
            'It saves as a draft. Nobody sees it until you publish it from '
            'the list.',
            style: TextStyle(color: bos.muted, fontSize: 11.5, height: 1.5),
          ),
      ],
    );
  }
}
