import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'context_models.dart';
import 'context_repository.dart';

final contextSwitchProvider =
    FutureProvider.autoDispose.family<SupportContextSwitch, int>(
  (ref, id) => ref.read(contextSwitchRepositoryProvider).byId(id),
);

/// One spell of a support agent working inside a customer's account.
///
/// The most sensitive thing this product does, so the record of it is shown in
/// full rather than summarised: who, which company, why, from where, for how
/// long, and whether they are still in there.
class ContextSwitchDetailScreen extends ConsumerWidget {
  const ContextSwitchDetailScreen({super.key, required this.id});

  final int id;

  static void open(BuildContext context, {required int id}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ContextSwitchDetailScreen(id: id),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(contextSwitchProvider(id));

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Access record')),
      body: async.when(
        loading: () => const Loader(),
        error: (error, _) => ErrorState(
          message: error is ApiException
              ? error.message
              : 'Could not load that record.',
          onRetry: () => ref.invalidate(contextSwitchProvider(id)),
        ),
        data: (entry) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            if (entry.stillActive)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: entry.looksForgotten
                    // A switch left open for hours is almost always somebody
                    // who forgot, not somebody still working.
                    ? MessageBanner.warning(
                        'Still open after ${entry.elapsedLabel ?? "a long "
                            "while"}. This looks like it was left rather than '
                        'ended.',
                      )
                    : MessageBanner.info('This access is still open.'),
              ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.companyLabel,
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.supportAgentName ?? 'An agent',
                    style: TextStyle(color: bos.textSecondary, fontSize: 13.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    entry.hasPurpose
                        ? entry.purpose!.trim()
                        : 'No purpose recorded.',
                    style: TextStyle(
                      color: entry.hasPurpose ? bos.text : bos.muted,
                      fontSize: 13.5,
                      height: 1.5,
                      fontStyle: entry.hasPurpose
                          ? FontStyle.normal
                          : FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const SectionHeader('When', icon: Icons.schedule_rounded),
            AppCard(
              child: Column(
                children: [
                  _Fact('Went in', Fmt.dateTime(entry.switchedInTime)),
                  _Fact(
                    'Came out',
                    entry.stillActive
                        ? 'Still in there'
                        : Fmt.dateTime(entry.switchedOutTime),
                  ),
                  if (entry.elapsedLabel != null)
                    _Fact('For', entry.elapsedLabel!),
                ],
              ),
            ),
            if (entry.ipAddress != null || entry.userAgent != null) ...[
              const SizedBox(height: 20),
              const SectionHeader('From', icon: Icons.computer_outlined),
              AppCard(
                child: Column(
                  children: [
                    if (entry.ipAddress != null)
                      _Fact('Address', entry.ipAddress!),
                    if (entry.userAgent != null)
                      _Fact('Browser', entry.userAgent!),
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

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(color: bos.muted, fontSize: 12.5),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(color: bos.text, fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
