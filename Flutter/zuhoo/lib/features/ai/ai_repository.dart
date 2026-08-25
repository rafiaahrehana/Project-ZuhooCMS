import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import 'ai_models.dart';

class AiRepository {
  AiRepository(this._api);

  final ApiClient _api;

  Future<AskAnswer> ask(String question) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/search/ask',
      {'question': question.trim()},
    );
    return AskAnswer.fromJson(json);
  }

  // ── Threads ─────────────────────────────────────────────────

  /// Opens a conversation. Created empty — the title arrives once there is
  /// something to derive one from.
  Future<AiThread> createThread(String feature) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/ai/threads',
      {'feature': feature},
    );
    return AiThread.fromJson(json);
  }

  /// This user's own threads. Scoped by user server-side, not just by company,
  /// so there is no way to read somebody else's.
  Future<PagedResponse<AiThread>> threads({int page = 0, int size = 20}) =>
      _api.getPaged('/ai/threads', AiThread.fromJson, page: page, size: size);

  /// The stored replies, oldest first.
  ///
  /// Assistant turns only — see [AiMessage] for why the questions are missing.
  Future<List<AiMessage>> threadMessages(int threadId) async {
    final page = await _api.getPaged(
      '/ai/threads/$threadId/messages',
      AiMessage.fromJson,
      page: 0,
      size: 100,
    );
    return page.content;
  }

  /// Says something to the agent and gets its reply.
  ///
  /// A reply with `awaitingConfirmation` set has *not* acted: the agent is
  /// proposing a write and waiting to be told to go ahead, which is another
  /// turn on the same thread.
  Future<AiMessage> agentTurn({
    required int threadId,
    required String message,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/ai/agent/turn',
      {'threadId': threadId, 'message': message.trim()},
    );
    return AiMessage.fromJson(json);
  }

  Future<void> deleteThread(int id) => _api.delete<dynamic>('/ai/threads/$id');

  /// One built once per company per day and handed back to everyone who asks
  /// — see `DailyBriefingService.getOrBuildToday` — so this is cheap to call
  /// on every visit to the screen.
  Future<String> dailyBriefing() async {
    final json = await _api.get<Map<String, dynamic>>('/ai/daily-briefing');
    return json['content'] as String? ?? '';
  }
}

final aiRepositoryProvider = Provider<AiRepository>(
  (ref) => AiRepository(ref.watch(apiClientProvider)),
);

final dailyBriefingProvider = FutureProvider.autoDispose<String>(
  (ref) => ref.watch(aiRepositoryProvider).dailyBriefing(),
);

/// This user's conversations, newest activity first.
///
/// A plain future rather than a paged controller: nobody accumulates enough
/// threads for a second page to matter, and the list is refetched whenever one
/// is opened, created or deleted.
final aiThreadsProvider = FutureProvider<List<AiThread>>((ref) async {
  final page = await ref.read(aiRepositoryProvider).threads(size: 50);
  return page.content;
});
