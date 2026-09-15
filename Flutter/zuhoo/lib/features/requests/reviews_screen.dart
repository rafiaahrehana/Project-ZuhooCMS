import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/config_list.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import 'request_controllers.dart';
import 'request_models.dart';
import 'request_repository.dart';

/// Which service the list is narrowed to. Null is all of them.
class ReviewServiceFilterController extends Notifier<int?> {
  @override
  int? build() => null;

  void set(int? hubServiceId) => state = hubServiceId;
}

final reviewServiceFilterProvider =
    NotifierProvider<ReviewServiceFilterController, int?>(
  ReviewServiceFilterController.new,
);

final reviewsProvider =
    FutureProvider.autoDispose<List<ServiceReview>>((ref) async {
  final serviceId = ref.watch(reviewServiceFilterProvider);
  final repo = ref.read(requestRepositoryProvider);
  final page = serviceId == null
      ? await repo.reviews(size: 50)
      : await repo.reviewsForService(serviceId, size: 50);
  return page.content;
});

/// The average, for whatever the list is currently showing.
final averageRatingProvider = FutureProvider.autoDispose<double?>((ref) {
  final serviceId = ref.watch(reviewServiceFilterProvider);
  final repo = ref.read(requestRepositoryProvider);
  return serviceId == null
      ? repo.averageRating()
      : repo.averageRatingForService(serviceId);
});

/// What clients made of the work.
///
/// Read and delete only. A review is written by the client who raised the
/// request and nobody else can edit one — the endpoint for that is
/// `hasRole('CLIENT')` and keyed to their own request.
class ReviewsScreen extends ConsumerWidget {
  const ReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final services = ref.watch(catalogServicesProvider).value;
    final selected = ref.watch(reviewServiceFilterProvider);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('What clients said')),
      body: ConfigList<ServiceReview>(
        async: ref.watch(reviewsProvider),
        onRefresh: () async {
          ref.invalidate(reviewsProvider);
          ref.invalidate(averageRatingProvider);
        },
        emptyIcon: Icons.star_border_rounded,
        emptyTitle: 'No reviews yet',
        emptyMessage: selected == null
            ? 'Clients can rate a request once it is completed. Nothing has '
                'been rated so far.'
            : 'Nothing has been said about that service yet.',
        errorMessage: 'Could not load the reviews.',
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Average(),
            const SizedBox(height: 12),
            if (services != null && services.isNotEmpty)
              FilterBar(
                // The filter carries service ids, and FilterBar deals in
                // strings, so they go through as text and come back parsed.
                selected: selected?.toString(),
                options: [
                  const (value: null, label: 'Everything'),
                  for (final service in services)
                    (value: service.id.toString(), label: service.name),
                ],
                onSelected: (value) => ref
                    .read(reviewServiceFilterProvider.notifier)
                    .set(value == null ? null : int.tryParse(value)),
              ),
          ],
        ),
        itemBuilder: (context, review) => _ReviewCard(review: review),
      ),
    );
  }
}

class _Average extends ConsumerWidget {
  const _Average();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(averageRatingProvider);

    return AppCard(
      child: async.when(
        loading: () => const Loader(padding: 12),
        error: (_, _) => Text(
          'The average could not be worked out.',
          style: TextStyle(color: bos.muted, fontSize: 13),
        ),
        data: (average) => average == null
            ? Text(
                'Nothing rated yet, so there is no average.',
                style: TextStyle(color: bos.muted, fontSize: 13),
              )
            : Row(
                children: [
                  Text(
                    average.toStringAsFixed(1),
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Stars(rating: average.round()),
                        const SizedBox(height: 4),
                        Text(
                          'out of five, on average',
                          style: TextStyle(color: bos.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.rating});

  final int rating;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 17,
            color: i <= rating ? bos.warning : bos.muted,
          ),
      ],
    );
  }
}

class _ReviewCard extends ConsumerStatefulWidget {
  const _ReviewCard({required this.review});

  final ServiceReview review;

  @override
  ConsumerState<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends ConsumerState<_ReviewCard> {
  bool _busy = false;

  Future<void> _delete() async {
    final confirmed = await confirmAction(
      context,
      title: 'Delete this review?',
      message: 'It goes for good, and it counts towards your average until it '
          'does. Deleting one because it is unflattering is worth a second '
          'thought.',
      action: 'Delete',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(requestRepositoryProvider).deleteReview(widget.review.id);
      ref.invalidate(reviewsProvider);
      ref.invalidate(averageRatingProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Deleted.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not delete that review.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final review = widget.review;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Stars(rating: review.rating),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    review.hubServiceName ?? 'A service',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: bos.muted, fontSize: 12),
                  ),
                ),
                if (_busy)
                  const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  PopupMenuButton<String>(
                    onSelected: (_) => _delete(),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'Delete',
                          style: TextStyle(color: bos.danger),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            if (review.comment != null && review.comment!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  review.comment!,
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 13.5,
                    height: 1.5,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              [
                review.clientName ?? 'A client',
                if (review.createdAt != null) Fmt.relative(review.createdAt),
                if (!review.published) 'not shown publicly',
              ].join(' · '),
              style: TextStyle(color: bos.muted, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}
