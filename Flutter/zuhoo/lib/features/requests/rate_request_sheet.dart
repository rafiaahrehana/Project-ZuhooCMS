import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/widgets/primitives.dart';
import 'request_models.dart';
import 'request_repository.dart';

/// Rates a completed request.
///
/// Returns true when a rating was left. Only offered to a portal client on
/// their own completed request — the backend refuses every other case, and
/// each refusal is a sentence worth showing rather than a button that fails.
Future<bool> showRateRequestSheet(
  BuildContext context, {
  required ServiceRequest request,
}) async {
  final rated = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _RateRequestSheet(request: request),
  );
  return rated ?? false;
}

class _RateRequestSheet extends ConsumerStatefulWidget {
  const _RateRequestSheet({required this.request});

  final ServiceRequest request;

  @override
  ConsumerState<_RateRequestSheet> createState() => _RateRequestSheetState();
}

class _RateRequestSheetState extends ConsumerState<_RateRequestSheet> {
  final _comment = TextEditingController();

  /// Starts unset rather than at a default: a prefilled score is one the
  /// client never actually chose.
  int? _rating;

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_rating == null) {
      setState(() => _error = 'Pick a rating first.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(requestRepositoryProvider).submitReview(
            SubmitReviewRequest(
              serviceRequestId: widget.request.id,
              rating: _rating!,
              comment: _comment.text,
            ),
          );
      if (!mounted) return;
      navigator.pop(true);
      messenger.showSnackBar(
        const SnackBar(content: Text('Thanks — your rating was recorded.')),
      );
    } on ApiException catch (e) {
      // "Reviews can only be submitted for completed requests" and "You can
      // only review your own service requests" both land here.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not record that rating.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'How did it go?',
              style: TextStyle(
                color: bos.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.request.hubServiceName ?? widget.request.title,
              style: TextStyle(color: bos.muted, fontSize: 13),
            ),
            const SizedBox(height: 18),
            if (_error != null) ...[
              MessageBanner.error(
                _error!,
                onDismiss: () => setState(() => _error = null),
              ),
              const SizedBox(height: 14),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var star = 1; star <= 5; star++)
                  IconButton(
                    icon: Icon(
                      _rating != null && star <= _rating!
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      size: 34,
                      color: _rating != null && star <= _rating!
                          ? bos.warning
                          : bos.muted,
                    ),
                    tooltip: '$star',
                    onPressed:
                        _submitting ? null : () => setState(() => _rating = star),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                _rating == null ? 'Tap a star' : _label(_rating!),
                style: TextStyle(color: bos.muted, fontSize: 12.5),
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _comment,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Anything to add? (optional)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 18),
            LoadingButton(
              label: 'Submit rating',
              loading: _submitting,
              icon: Icons.send_rounded,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }

  static String _label(int rating) => switch (rating) {
        1 => 'Poor',
        2 => 'Not great',
        3 => 'Fine',
        4 => 'Good',
        _ => 'Excellent',
      };
}
