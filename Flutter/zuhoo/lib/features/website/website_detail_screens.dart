import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'website_repository.dart';

/// One service, opened from the Services tab with the summary row already in
/// hand — the full description arrives with the detail call the same way the
/// knowledge base's article screen upgrades from a list row to the full
/// article.
class WebsiteServiceDetailScreen extends ConsumerWidget {
  const WebsiteServiceDetailScreen({
    super.key,
    required this.subdomain,
    required this.slug,
  });

  final String subdomain;
  final String slug;

  static void open(
    BuildContext context, {
    required String subdomain,
    required String slug,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            WebsiteServiceDetailScreen(subdomain: subdomain, slug: slug),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final args = (subdomain: subdomain, slug: slug);
    final async = ref.watch(websiteServiceDetailProvider(args));

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Service')),
      body: async.when(
        loading: () => const Loader(),
        error: (error, _) => ErrorState(
          message:
              error is ApiException ? error.message : 'Could not load that.',
          onRetry: () => ref.invalidate(websiteServiceDetailProvider(args)),
        ),
        data: (service) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text(
              service.title,
              style: TextStyle(
                color: bos.text,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            if (service.categoryName != null) ...[
              const SizedBox(height: 6),
              Text(
                service.categoryName!,
                style: TextStyle(color: bos.muted, fontSize: 12.5),
              ),
            ],
            const SizedBox(height: 16),
            if (service.startingPrice != null || service.estimatedTime != null)
              Row(
                children: [
                  if (service.startingPrice != null)
                    Expanded(
                      child: _Stat(label: 'Starting at', value: service.startingPrice!),
                    ),
                  if (service.estimatedTime != null)
                    Expanded(
                      child: _Stat(label: 'Estimated time', value: service.estimatedTime!),
                    ),
                ],
              ),
            const SizedBox(height: 16),
            AppCard(
              padding: const EdgeInsets.all(18),
              child: Text(
                (service.description?.trim().isNotEmpty ?? false)
                    ? service.description!.trim()
                    : (service.summary ?? 'No description yet.'),
                style: TextStyle(color: bos.text, fontSize: 14, height: 1.55),
              ),
            ),
            if (service.features.isNotEmpty) ...[
              const SizedBox(height: 16),
              const SectionHeader('What is included', icon: Icons.checklist_rounded),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final feature in service.features)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.check_rounded, size: 15, color: bos.success),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                feature,
                                style: TextStyle(color: bos.text, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: bos.muted, fontSize: 11.5)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: bos.brandInk,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// One blog post, opened from the Blog tab. Pages reached from the site nav
/// tree share the same `WebsiteContent` shape but have no list of their own
/// to open a detail screen from, so only posts get one here.
class WebsiteBlogDetailScreen extends ConsumerWidget {
  const WebsiteBlogDetailScreen({
    super.key,
    required this.subdomain,
    required this.slug,
  });

  final String subdomain;
  final String slug;

  static void open(
    BuildContext context, {
    required String subdomain,
    required String slug,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            WebsiteBlogDetailScreen(subdomain: subdomain, slug: slug),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final args = (subdomain: subdomain, slug: slug);
    final async = ref.watch(websiteBlogPostProvider(args));

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Post')),
      body: async.when(
        loading: () => const Loader(),
        error: (error, _) => ErrorState(
          message:
              error is ApiException ? error.message : 'Could not load that.',
          onRetry: () => ref.invalidate(websiteBlogPostProvider(args)),
        ),
        data: (post) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text(
              post.title ?? 'Untitled post',
              style: TextStyle(
                color: bos.text,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (post.author != null) ...[
                  Text(post.author!, style: TextStyle(color: bos.muted, fontSize: 12.5)),
                  const SizedBox(width: 10),
                ],
                if (post.publishedAt != null)
                  Text(
                    Fmt.date(post.publishedAt),
                    style: TextStyle(color: bos.muted, fontSize: 12.5),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            AppCard(
              padding: const EdgeInsets.all(18),
              child: SelectableText(
                (post.body?.trim().isNotEmpty ?? false)
                    ? post.body!.trim()
                    : (post.excerpt ?? 'This post has no body yet.'),
                style: TextStyle(color: bos.text, fontSize: 14.5, height: 1.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
