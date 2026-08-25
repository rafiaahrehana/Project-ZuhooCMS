import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import '../search/search_screen.dart' show openSearchHit;
import 'ai_chat_screen.dart';
import 'ai_models.dart';
import 'ai_repository.dart';

/// A lightweight assistant: this morning's briefing, and one question at a
/// time answered from the company's own records.
///
/// Deliberately not the full AI module — conversation history, provider
/// configuration and usage reporting are an admin console, not something
/// worth building for a phone. See `AiController`: everything here maps to
/// the two endpoints gated on plain `AI_CHAT`, never `AI_ADMIN`.
class AiScreen extends ConsumerStatefulWidget {
  const AiScreen({super.key});

  @override
  ConsumerState<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends ConsumerState<AiScreen> {
  final _controller = TextEditingController();
  bool _asking = false;
  AskAnswer? _answer;
  Object? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final question = _controller.text.trim();
    if (question.isEmpty || _asking) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _asking = true;
      _error = null;
    });

    try {
      final answer = await ref.read(aiRepositoryProvider).ask(question);
      if (!mounted) return;
      setState(() => _answer = answer);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final permissions = ref.watch(permissionControllerProvider);

    if (!permissions.loaded && permissions.codes.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('AI Assistant')),
        body: const Loader(),
      );
    }

    if (!permissions.has(AiPermissions.chat)) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('AI Assistant')),
        body: const EmptyState(
          icon: Icons.auto_awesome_outlined,
          title: 'Not available to you',
          message: 'Ask your company owner to grant AI access.',
        ),
      );
    }

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('AI Assistant')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          const _Briefing(),
          const SizedBox(height: 22),
          const SectionHeader('Ask something', icon: Icons.auto_awesome_rounded),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _ask(),
                  decoration: const InputDecoration(
                    hintText: 'Which invoices are overdue?',
                    border: InputBorder.none,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: LoadingButton(
                    label: 'Ask',
                    loading: _asking,
                    icon: Icons.send_rounded,
                    onPressed: _ask,
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            MessageBanner.error(
              _error is ApiException
                  ? (_error! as ApiException).message
                  : 'Could not get an answer. Please try again.',
              onDismiss: () => setState(() => _error = null),
            ),
          ],
          if (_answer != null) ...[
            const SizedBox(height: 18),
            _Answer(answer: _answer!),
          ],
          const SizedBox(height: 22),
          const _Threads(),
        ],
      ),
    );
  }
}

/// Conversations, as distinct from the one-shot ask above.
///
/// The ask box answers a question and forgets it. A thread keeps going, and an
/// agent thread can act — which is why starting one is a deliberate choice
/// rather than what happens when you type in the box.
class _Threads extends ConsumerStatefulWidget {
  const _Threads();

  @override
  ConsumerState<_Threads> createState() => _ThreadsState();
}

class _ThreadsState extends ConsumerState<_Threads> {
  bool _starting = false;

  Future<void> _start(String feature) async {
    setState(() => _starting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final thread = await ref.read(aiRepositoryProvider).createThread(feature);
      ref.invalidate(aiThreadsProvider);
      if (!mounted) return;
      await AiChatScreen.open(context, thread: thread);
      // Its title is derived from what was said, so the list is stale now.
      ref.invalidate(aiThreadsProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not start that conversation.')),
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _delete(AiThread thread) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete “${thread.label}”?'),
        content: const Text('The conversation and its replies are removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(aiRepositoryProvider).deleteThread(thread.id);
      ref.invalidate(aiThreadsProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not delete that conversation.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final threads = ref.watch(aiThreadsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Conversations', icon: Icons.forum_outlined),
        if (_starting)
          const Loader(padding: 12)
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _start(AiThreadFeature.agent),
                  icon: const Icon(Icons.bolt_rounded, size: 17),
                  label: const Text('New task'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 42),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _start(AiThreadFeature.general),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
                  label: const Text('New chat'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 42),
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        threads.when(
          loading: () => const Loader(padding: 12),
          error: (_, _) => const AppCard(
            child: MessageBanner.info('Could not load your conversations.'),
          ),
          data: (list) {
            if (list.isEmpty) {
              return AppCard(
                child: Text(
                  'Nothing yet. A task can book leave or log hours for you; a '
                  'chat just answers.',
                  style: TextStyle(color: bos.muted, fontSize: 12.5, height: 1.4),
                ),
              );
            }
            return AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (var i = 0; i < list.length; i++) ...[
                    ListTile(
                      leading: Icon(
                        list[i].isAgent
                            ? Icons.bolt_rounded
                            : Icons.chat_bubble_outline_rounded,
                        size: 20,
                        color: list[i].isAgent ? bos.brandInk : bos.muted,
                      ),
                      title: Text(
                        list[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: bos.text, fontSize: 14),
                      ),
                      subtitle: list[i].updatedAt == null
                          ? null
                          : Text(
                              Fmt.relative(list[i].updatedAt),
                              style:
                                  TextStyle(color: bos.muted, fontSize: 11.5),
                            ),
                      trailing: IconButton(
                        icon: Icon(Icons.close_rounded,
                            size: 18, color: bos.muted),
                        tooltip: 'Delete',
                        onPressed: () => _delete(list[i]),
                      ),
                      onTap: () async {
                        await AiChatScreen.open(context, thread: list[i]);
                        ref.invalidate(aiThreadsProvider);
                      },
                    ),
                    if (i != list.length - 1)
                      Divider(height: 1, indent: 16, color: bos.borderLight),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Briefing extends ConsumerWidget {
  const _Briefing();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(dailyBriefingProvider);

    return async.when(
      // A briefing that fails to load is not worth a whole error screen — the
      // ask box below still works fine without it.
      loading: () => const AppCard(child: Loader(padding: 8)),
      error: (_, _) => const SizedBox.shrink(),
      data: (content) {
        if (content.trim().isEmpty) return const SizedBox.shrink();
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.wb_sunny_outlined, size: 16, color: bos.brandInk),
                  const SizedBox(width: 8),
                  Text(
                    'Today\'s briefing',
                    style: TextStyle(
                      color: bos.brandInk,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                content.trim(),
                style: TextStyle(color: bos.text, fontSize: 13.5, height: 1.45),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Answer extends StatelessWidget {
  const _Answer({required this.answer});

  final AskAnswer answer;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                answer.question,
                style: TextStyle(
                  color: bos.muted,
                  fontSize: 12.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                answer.answer,
                style: TextStyle(color: bos.text, fontSize: 14, height: 1.45),
              ),
            ],
          ),
        ),
        if (answer.sources.isNotEmpty) ...[
          const SizedBox(height: 14),
          SectionHeader('Sources', icon: Icons.link_rounded),
          for (final source in answer.sources)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => openSearchHit(context, source),
                child: AppCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              source.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: bos.text,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (source.subtitle?.trim().isNotEmpty == true)
                              Text(
                                source.subtitle!.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: bos.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          size: 18, color: bos.muted),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}
