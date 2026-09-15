import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'support_admin_models.dart';
import 'support_admin_repository.dart';

/// One entry from the trail, in full.
///
/// The list rows carry only a summary. What matters when somebody actually
/// investigates is here: what changed, where the request came from, and the
/// two ways out — everything that happened to the same record, and everything
/// the same person did.
class AuditDetailScreen extends ConsumerWidget {
  const AuditDetailScreen({super.key, required this.id});

  final int id;

  static void open(BuildContext context, {required int id}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AuditDetailScreen(id: id)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(auditEntryProvider(id));

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Trail entry')),
      body: async.when(
        loading: () => const Loader(),
        error: (error, _) => ErrorState(
          message: error is ApiException
              ? error.message
              : 'Could not load that entry.',
          onRetry: () => ref.invalidate(auditEntryProvider(id)),
        ),
        data: (entry) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Fmt.label(entry.actionType),
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (entry.description != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      entry.description!,
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 13.5,
                        height: 1.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    [
                      entry.actionByUserName ?? 'Somebody',
                      Fmt.dateTime(entry.createdAt),
                    ].join('  ·  '),
                    style: TextStyle(color: bos.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (entry.contextSwitchToCompanyName != null) ...[
              const SizedBox(height: 12),
              // The single most important thing on any entry: this action was
              // taken by somebody outside the company, working inside it.
              MessageBanner.warning(
                'Done while switched into '
                '${entry.contextSwitchToCompanyName}.',
              ),
            ],
            const SizedBox(height: 20),
            const SectionHeader('Details', icon: Icons.info_outline_rounded),
            AppCard(
              child: Column(
                children: [
                  if (entry.resourceType != null)
                    _Fact('What', Fmt.label(entry.resourceType)),
                  if (entry.resourceId != null)
                    _Fact('Which', '#${entry.resourceId}'),
                  if (entry.ipAddress != null)
                    _Fact('From', entry.ipAddress!),
                  if (entry.userAgent != null)
                    _Fact('Using', entry.userAgent!),
                ],
              ),
            ),
            if (entry.changes != null && entry.changes!.trim().isNotEmpty) ...[
              const SizedBox(height: 20),
              const SectionHeader(
                'What changed',
                icon: Icons.difference_outlined,
              ),
              AppCard(
                // Shown as it came. Its shape depends on which module wrote
                // it, so parsing it would only be guessing.
                child: SelectableText(
                  entry.changes!,
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 12.5,
                    height: 1.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (entry.resourceId != null)
              _RelatedButton(
                label: 'Everything that happened to this record',
                icon: Icons.link_rounded,
                onPressed: () => RelatedTrailScreen.open(
                  context,
                  title: entry.resourceType == null
                      ? 'This record'
                      : Fmt.label(entry.resourceType),
                  provider: auditForResourceProvider(entry.resourceId!),
                ),
              ),
            if (entry.actionByUserId != null) ...[
              const SizedBox(height: 8),
              _RelatedButton(
                label: 'Everything ${entry.actionByUserName ?? "they"} did',
                icon: Icons.person_search_outlined,
                onPressed: () => RelatedTrailScreen.open(
                  context,
                  title: entry.actionByUserName ?? 'That person',
                  provider: auditForUserProvider(entry.actionByUserId!),
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
            width: 64,
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

class _RelatedButton extends StatelessWidget {
  const _RelatedButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        label: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}

/// A trail narrowed to one record or one person.
///
/// Takes the provider rather than an id and a flag, so the two lookups —
/// which return different shapes on the wire and are paged differently — each
/// keep their own repository method.
class RelatedTrailScreen extends ConsumerWidget {
  const RelatedTrailScreen({
    super.key,
    required this.title,
    required this.provider,
  });

  final String title;
  final FutureProvider<List<SupportAuditEntry>> provider;

  static void open(
    BuildContext context, {
    required String title,
    required FutureProvider<List<SupportAuditEntry>> provider,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RelatedTrailScreen(title: title, provider: provider),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(provider);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: Text(title)),
      body: async.when(
        loading: () => const Loader(),
        error: (error, _) => ErrorState(
          message: error is ApiException
              ? error.message
              : 'Could not load that trail.',
        ),
        data: (entries) => entries.isEmpty
            ? const EmptyState(
                icon: Icons.history_rounded,
                title: 'Nothing recorded',
                message: 'No entries for this.',
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                itemCount: entries.length,
                itemBuilder: (context, i) {
                  final entry = entries[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      onTap: () =>
                          AuditDetailScreen.open(context, id: entry.id),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            Fmt.label(entry.actionType),
                            style: TextStyle(
                              color: bos.text,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (entry.description != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                entry.description!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: bos.textSecondary,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          const SizedBox(height: 4),
                          Text(
                            [
                              entry.actionByUserName ?? 'Somebody',
                              Fmt.relative(entry.createdAt),
                              if (entry.contextSwitchToCompanyName != null)
                                'in ${entry.contextSwitchToCompanyName}',
                            ].join('  ·  '),
                            style: TextStyle(color: bos.muted, fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
