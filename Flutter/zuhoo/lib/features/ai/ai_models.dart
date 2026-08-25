import '../search/search_models.dart';

/// Gates the whole feature — daily briefing and ask alike both resolve to
/// `AiServiceImpl.generateRaw`, which checks this one code no matter which
/// controller called it.
abstract final class AiPermissions {
  static const chat = 'AI_CHAT';
}

/// POST /api/search/ask response.
class AskAnswer {
  const AskAnswer({
    required this.question,
    required this.answer,
    required this.sources,
  });

  final String question;
  final String answer;

  /// The records the answer was grounded on — the same shape global search
  /// returns, so a source opens exactly like a search result does.
  final List<SearchHit> sources;

  factory AskAnswer.fromJson(Map<String, dynamic> json) => AskAnswer(
        question: json['question'] as String? ?? '',
        answer: json['answer'] as String? ?? '',
        sources: (json['sources'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(SearchHit.fromJson)
                .toList(growable: false) ??
            const [],
      );
}

/// Which kind of thread to open.
///
/// The backend's `AiFeature` has twenty-odd values, most of them one-shot
/// drafting helpers rather than conversations. Only these two make sense as a
/// thread you talk to: AGENT_TASK gets the tool-calling loop that can actually
/// do things, GENERAL is plain question-and-answer.
abstract final class AiThreadFeature {
  /// The assistant that can act — leave, attendance, timesheets. Write actions
  /// come back for confirmation before anything happens.
  static const agent = 'AGENT_TASK';

  /// Question and answer, no tools.
  static const general = 'GENERAL';
}

/// A conversation.
class AiThread {
  const AiThread({
    required this.id,
    required this.feature,
    this.title,
    this.updatedAt,
  });

  final int id;
  final String feature;
  final String? title;
  final String? updatedAt;

  bool get isAgent => feature == AiThreadFeature.agent;

  /// Threads are created before anything has been said, so a fresh one has no
  /// title until the backend derives one.
  String get label {
    final trimmed = title?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    return isAgent ? 'New task' : 'New conversation';
  }

  factory AiThread.fromJson(Map<String, dynamic> json) => AiThread(
        id: (json['id'] as num?)?.toInt() ?? 0,
        feature: json['feature'] as String? ?? AiThreadFeature.general,
        title: json['title'] as String?,
        updatedAt: json['updatedAt'] as String? ?? json['createdAt'] as String?,
      );
}

/// One turn in a conversation, as the app shows it.
///
/// **The backend does not return the user's own messages.**
/// `getThreadMessages` maps only `responsePayload` into `result` — the question
/// is stored as `requestPayload` and never exposed. So a thread reopened later
/// reads as the assistant's replies alone, while a conversation held in this
/// session reads properly because the app remembers what was typed.
class AiMessage {
  const AiMessage({
    required this.text,
    required this.fromUser,
    this.awaitingConfirmation = false,
  });

  const AiMessage.user(this.text)
      : fromUser = true,
        awaitingConfirmation = false;

  final String text;
  final bool fromUser;

  /// The agent has proposed a write action and is waiting to be told to go
  /// ahead. Nothing has happened yet — replying "yes" is what commits it.
  final bool awaitingConfirmation;

  factory AiMessage.fromJson(Map<String, dynamic> json) => AiMessage(
        text: json['result'] as String? ?? '',
        fromUser: false,
        awaitingConfirmation: json['awaitingConfirmation'] as bool? ?? false,
      );
}
