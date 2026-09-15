import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import 'ai_admin_models.dart';
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

  // ── One-shot drafting ───────────────────────────────────────

  /// Asks for one piece of text. No conversation and no memory — the thread
  /// endpoints are for that.
  Future<AiExchange> generate({
    required String feature,
    required String prompt,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/ai/generate',
      {'feature': feature, 'prompt': prompt.trim()},
    );
    return AiExchange.fromJson(json);
  }

  /// What has been asked before, newest first. Optionally narrowed to one
  /// feature.
  Future<PagedResponse<AiExchange>> conversations({
    String? feature,
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        '/ai/conversations',
        AiExchange.fromJson,
        page: page,
        size: size,
        query: {'feature': ?feature},
      );

  // ── Configuration, all behind AI_ADMIN ──────────────────────

  /// Every provider this company has saved.
  Future<List<AiProviderConfig>> configs() async {
    final list = await _api.get<List<dynamic>>('/ai/configs');
    return list
        .whereType<Map<String, dynamic>>()
        .map(AiProviderConfig.fromJson)
        .toList(growable: false);
  }

  /// Saves a provider and makes it the active one. An upsert on the provider
  /// type rather than the id — see [AiProviderConfigRequest].
  Future<AiProviderConfig> saveConfig(AiProviderConfigRequest request) async {
    final json =
        await _api.post<Map<String, dynamic>>('/ai/config', request.toJson());
    return AiProviderConfig.fromJson(json);
  }

  Future<AiProviderConfig> activateConfig(int id) async {
    final json =
        await _api.patch<Map<String, dynamic>>('/ai/config/$id/activate');
    return AiProviderConfig.fromJson(json);
  }

  Future<void> deleteConfig(int id) => _api.delete<dynamic>('/ai/config/$id');

  /// The prompts, ordered by feature.
  Future<PagedResponse<AiPromptTemplate>> templates({
    int page = 0,
    int size = 50,
  }) =>
      _api.getPaged(
        '/ai/templates',
        AiPromptTemplate.fromJson,
        page: page,
        size: size,
      );

  /// Saves a prompt. Supersedes the last one for that feature rather than
  /// replacing it, so the version number climbs.
  Future<AiPromptTemplate> saveTemplate(
    AiPromptTemplateRequest request,
  ) async {
    final json =
        await _api.post<Map<String, dynamic>>('/ai/templates', request.toJson());
    return AiPromptTemplate.fromJson(json);
  }

  Future<void> deleteTemplate(int id) =>
      _api.delete<dynamic>('/ai/templates/$id');

  /// What the assistant did on one day. Without a date the backend uses today.
  Future<AiUsageSummary> usage({String? date}) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/ai/usage',
      query: {'date': ?date},
    );
    return AiUsageSummary.fromJson(json);
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
