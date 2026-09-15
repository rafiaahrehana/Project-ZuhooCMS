import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/config_list.dart';
import '../../shared/widgets/primitives.dart';
import 'ai_admin_models.dart';
import 'ai_repository.dart';

/// Which feature the history is narrowed to. Null is everything.
class AiHistoryFilterController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? feature) => state = feature;
}

final aiHistoryFilterProvider =
    NotifierProvider<AiHistoryFilterController, String?>(
  AiHistoryFilterController.new,
);

final aiHistoryProvider =
    FutureProvider.autoDispose<List<AiExchange>>((ref) async {
  final feature = ref.watch(aiHistoryFilterProvider);
  final page = await ref
      .read(aiRepositoryProvider)
      .conversations(feature: feature, size: 30);
  return page.content;
});

/// Asking the assistant for one piece of text, and what has been asked before.
///
/// Distinct from the chat: nothing here remembers anything. Each answer is a
/// single shot against one feature, which is what the drafting prompts are
/// tuned for — an employment letter is written, not discussed.
class AiDraftsScreen extends StatelessWidget {
  const AiDraftsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(
          title: const Text('Drafting'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Draft'), Tab(text: 'Earlier')],
          ),
        ),
        body: const TabBarView(children: [_DraftTab(), _HistoryTab()]),
      ),
    );
  }
}

class _DraftTab extends ConsumerStatefulWidget {
  const _DraftTab();

  @override
  ConsumerState<_DraftTab> createState() => _DraftTabState();
}

class _DraftTabState extends ConsumerState<_DraftTab> {
  final _prompt = TextEditingController();
  String _feature = AiFeature.general;

  String? _result;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _draft() async {
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final exchange = await ref.read(aiRepositoryProvider).generate(
            feature: _feature,
            prompt: prompt,
          );
      setState(() => _result = exchange.result);
      // The answer is recorded server-side, so the history behind this tab is
      // now one row out of date.
      ref.invalidate(aiHistoryProvider);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not draft that.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        if (_error != null) ...[
          MessageBanner.error(
            _error!,
            onDismiss: () => setState(() => _error = null),
          ),
          const SizedBox(height: 12),
        ],
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _feature,
                decoration: const InputDecoration(labelText: 'What to write'),
                items: [
                  for (final value in AiFeature.draftable)
                    DropdownMenuItem(
                      value: value,
                      child: Text(Fmt.label(value)),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _feature = value ?? _feature),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _prompt,
                maxLines: 5,
                minLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What it needs to say',
                  hintText: 'Two weeks unpaid leave for Sara in March, '
                      'approved by her manager.',
                ),
              ),
              const SizedBox(height: 12),
              LoadingButton(
                label: 'Draft it',
                icon: Icons.auto_awesome_rounded,
                loading: _busy,
                onPressed: _draft,
              ),
            ],
          ),
        ),
        if (_result != null) ...[
          const SizedBox(height: 20),
          SectionHeader(
            'The draft',
            icon: Icons.description_outlined,
            trailing: IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _result!));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied.')),
                );
              },
            ),
          ),
          AppCard(
            child: SelectableText(
              _result!,
              style: TextStyle(color: bos.text, fontSize: 13.5, height: 1.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Read it before you use it. Nothing has been sent or saved '
            'anywhere except this history.',
            style: TextStyle(color: bos.muted, fontSize: 11.5, height: 1.5),
          ),
        ],
      ],
    );
  }
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final feature = ref.watch(aiHistoryFilterProvider);

    return ConfigList<AiExchange>(
      async: ref.watch(aiHistoryProvider),
      onRefresh: () async => ref.invalidate(aiHistoryProvider),
      emptyIcon: Icons.history_rounded,
      emptyTitle: 'Nothing asked yet',
      emptyMessage: 'Answers appear here once somebody has asked for one.',
      errorMessage: 'Could not load the history.',
      header: FilterBar(
        selected: feature,
        options: [
          const (value: null, label: 'Everything'),
          for (final value in AiFeature.draftable)
            (value: value, label: Fmt.label(value)),
        ],
        onSelected: ref.read(aiHistoryFilterProvider.notifier).set,
      ),
      itemBuilder: (context, exchange) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      Fmt.label(exchange.feature),
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (exchange.model != null)
                    Text(
                      Fmt.label(exchange.model),
                      style: TextStyle(color: bos.muted, fontSize: 11),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                exchange.result,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: bos.text, fontSize: 13, height: 1.5),
              ),
              // The response carries no timestamp and no copy of the prompt,
              // so how long it took is the only other thing there is to say.
              if (exchange.executionTimeMs > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'answered in '
                    '${(exchange.executionTimeMs / 1000).toStringAsFixed(1)}s',
                    style: TextStyle(color: bos.muted, fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
