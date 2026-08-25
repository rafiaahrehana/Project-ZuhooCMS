import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/widgets/primitives.dart';
import 'ai_models.dart';
import 'ai_repository.dart';

/// One conversation with the assistant.
///
/// Opened on a thread that already exists — creating it is the caller's job,
/// so this screen never has to render an empty state that is really a loading
/// state.
class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key, required this.thread});

  final AiThread thread;

  static Future<void> open(BuildContext context, {required AiThread thread}) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AiChatScreen(thread: thread)),
    );
  }

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  /// The transcript as this session knows it.
  ///
  /// Seeded from the stored replies, then appended to as the conversation goes
  /// on. What the user typed only exists here — the backend does not return it
  /// — so a reopened thread starts one-sided and fills in properly from the
  /// next message onward.
  final List<AiMessage> _messages = [];

  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final history =
          await ref.read(aiRepositoryProvider).threadMessages(widget.thread.id);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(history);
        _loading = false;
      });
      _scrollToEnd();
    } on ApiException catch (e) {
      if (mounted) setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        _error = 'Could not load this conversation.';
        _loading = false;
      });
    }
  }

  /// After the frame, so the list has the new item before we measure it.
  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _messages.add(AiMessage.user(text));
      _input.clear();
      _sending = true;
      _error = null;
    });
    _scrollToEnd();

    try {
      final reply = await ref.read(aiRepositoryProvider).agentTurn(
            threadId: widget.thread.id,
            message: text,
          );
      if (!mounted) return;
      setState(() => _messages.add(reply));
      _scrollToEnd();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'The assistant did not answer.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: Text(widget.thread.label)),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: MessageBanner.error(
                _error!,
                onDismiss: () => setState(() => _error = null),
              ),
            ),
          Expanded(
            child: _loading
                ? const Loader()
                : _messages.isEmpty
                    ? EmptyState(
                        icon: Icons.auto_awesome_outlined,
                        title: widget.thread.isAgent
                            ? 'Ask it to do something'
                            : 'Ask it something',
                        message: widget.thread.isAgent
                            ? 'Book leave, check your hours, log a timesheet. '
                                'It will ask before it changes anything.'
                            : 'Anything about your work here.',
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) =>
                            _Bubble(message: _messages[index]),
                      ),
          ),
          if (_sending)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    height: 13,
                    width: 13,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Thinking…',
                    style: TextStyle(color: bos.muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          _Composer(
            controller: _input,
            enabled: !_sending && !_loading,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final AiMessage message;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final fromUser = message.fromUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            fromUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.82,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: fromUser ? bos.brandSoft : bos.bgCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: message.awaitingConfirmation
                      ? bos.warning.withValues(alpha: 0.5)
                      : bos.borderLight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    message.text,
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 14.5,
                      height: 1.45,
                    ),
                  ),
                  // The agent has proposed a write and is waiting. Said out
                  // loud because nothing has happened yet, and the next reply
                  // is what decides whether it does.
                  if (message.awaitingConfirmation) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.pending_outlined,
                          size: 14,
                          color: bos.warning,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Nothing has changed yet — reply to confirm.',
                            style: TextStyle(
                              color: bos.warning,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        8 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: bos.bgCard,
        border: Border(top: BorderSide(color: bos.borderLight)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'Type a message',
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send_rounded),
              color: bos.brand,
              tooltip: 'Send',
              onPressed: enabled ? onSend : null,
            ),
          ],
        ),
      ),
    );
  }
}
