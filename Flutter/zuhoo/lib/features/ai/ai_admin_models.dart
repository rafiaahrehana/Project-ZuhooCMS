/// Configuring the assistant: which provider answers, what it is told to say,
/// and what it has cost so far.
///
/// All of it sits behind `AI_ADMIN`, a separate code from the `AI_CHAT` that
/// gates using the assistant. Most people who talk to it cannot configure it.
library;

/// Every feature the backend can generate for.
///
/// The full `AiFeature` enum, not the two-value subset threads use. Templates
/// are keyed by feature and the conversation history filters on it, so both
/// need the whole list.
abstract final class AiFeature {
  static const employmentLetter = 'EMPLOYMENT_LETTER';
  static const leavePolicy = 'LEAVE_POLICY';
  static const performanceReview = 'PERFORMANCE_REVIEW';
  static const crmLeadSummary = 'CRM_LEAD_SUMMARY';
  static const crmActivitySummary = 'CRM_ACTIVITY_SUMMARY';
  static const invoiceSummary = 'INVOICE_SUMMARY';
  static const serviceRequestSummary = 'SERVICE_REQUEST_SUMMARY';
  static const announcementDraft = 'ANNOUNCEMENT_DRAFT';
  static const holidayDraft = 'HOLIDAY_DRAFT';
  static const workflowSuggestion = 'WORKFLOW_SUGGESTION';
  static const searchAnswer = 'SEARCH_ANSWER';
  static const businessInsights = 'BUSINESS_INSIGHTS';
  static const general = 'GENERAL';
  static const timesheetEntry = 'TIMESHEET_ENTRY';
  static const expenseEntry = 'EXPENSE_ENTRY';
  static const dailyBriefing = 'DAILY_BRIEFING';
  static const agentTask = 'AGENT_TASK';

  static const all = [
    employmentLetter,
    leavePolicy,
    performanceReview,
    crmLeadSummary,
    crmActivitySummary,
    invoiceSummary,
    serviceRequestSummary,
    announcementDraft,
    holidayDraft,
    workflowSuggestion,
    searchAnswer,
    businessInsights,
    general,
    timesheetEntry,
    expenseEntry,
    dailyBriefing,
    agentTask,
  ];

  /// The ones worth asking for by hand. The rest are wired into a screen that
  /// calls them with context a person could not type — an invoice summary
  /// needs the invoice, not a description of it.
  static const draftable = [
    employmentLetter,
    leavePolicy,
    performanceReview,
    announcementDraft,
    holidayDraft,
    general,
  ];
}

abstract final class AiProviderType {
  static const gemini = 'GEMINI';
  static const claude = 'CLAUDE';
  static const openai = 'OPENAI';
  static const groq = 'GROQ';

  /// Answers canned text without calling anybody. Useful for a demo tenant,
  /// and offered so a company that has one saved can see what it is.
  static const mock = 'MOCK';

  static const all = [gemini, claude, openai, groq, mock];

  static String label(String provider) => switch (provider) {
        gemini => 'Google Gemini',
        claude => 'Anthropic Claude',
        openai => 'OpenAI',
        groq => 'Groq',
        mock => 'Mock (no provider)',
        _ => provider,
      };

  /// Which models belong to which provider.
  ///
  /// `AiModel` is one flat enum server-side with nothing tying a value to a
  /// provider, so pairing them is this app's job. Saving CLAUDE with a GPT
  /// model would be accepted and then fail at generation time.
  static const models = <String, List<String>>{
    gemini: ['GEMINI_2_5_FLASH', 'GEMINI_2_5_PRO'],
    claude: ['CLAUDE_SONNET', 'CLAUDE_OPUS'],
    openai: ['GPT_4O', 'GPT_4O_MINI'],
    groq: ['GROQ_LLAMA_3_3_70B', 'GROQ_LLAMA_3_1_8B'],
    mock: ['GEMINI_2_5_FLASH'],
  };

  static List<String> modelsFor(String provider) =>
      models[provider] ?? const ['GEMINI_2_5_FLASH'];
}

/// A saved provider. One per provider type per company, at most one active.
class AiProviderConfig {
  const AiProviderConfig({
    required this.id,
    required this.provider,
    required this.model,
    required this.active,
    required this.maxTokens,
    this.temperature,
    this.createdAt,
  });

  final int id;
  final String provider;
  final String model;
  final bool active;
  final int maxTokens;
  final double? temperature;
  final String? createdAt;

  factory AiProviderConfig.fromJson(Map<String, dynamic> json) =>
      AiProviderConfig(
        id: (json['id'] as num?)?.toInt() ?? 0,
        provider: json['provider'] as String? ?? '',
        model: json['model'] as String? ?? '',
        active: json['active'] as bool? ?? false,
        maxTokens: (json['maxTokens'] as num?)?.toInt() ?? 0,
        temperature: (json['temperature'] as num?)?.toDouble(),
        createdAt: json['createdAt'] as String?,
      );
}

/// Saving a provider.
///
/// An upsert keyed on the provider type, not the id: sending GEMINI twice
/// changes the Gemini row rather than making a second one. Saving also makes
/// that provider the active one, so this is never a quiet edit.
///
/// The key is write-only. It is encrypted on the way in and never comes back
/// out, so an edit that leaves it blank keeps the stored one — the service
/// skips a null or blank key rather than clearing it.
class AiProviderConfigRequest {
  const AiProviderConfigRequest({
    required this.provider,
    required this.model,
    this.apiKey,
    this.temperature,
    this.maxTokens,
  });

  final String provider;
  final String model;
  final String? apiKey;

  /// Null leaves whatever is stored alone — the service null-checks both of
  /// these, unlike most of this backend.
  final double? temperature;
  final int? maxTokens;

  Map<String, dynamic> toJson() => {
        'aiProviderType': provider,
        'model': model,
        if (apiKey != null && apiKey!.trim().isNotEmpty) 'apiKey': apiKey!.trim(),
        if (temperature != null) 'temperature': temperature,
        if (maxTokens != null) 'maxTokens': maxTokens,
      };
}

/// A prompt the assistant is given for one feature.
class AiPromptTemplate {
  const AiPromptTemplate({
    required this.id,
    required this.feature,
    required this.name,
    required this.template,
    required this.version,
    required this.active,
    this.changeNotes,
    this.updatedByName,
    this.updatedAt,
  });

  final int id;
  final String feature;
  final String name;
  final String template;

  /// Saving a template for a feature supersedes the last one rather than
  /// overwriting it, so the number climbs and the old text stays on record.
  final int version;

  final bool active;
  final String? changeNotes;
  final String? updatedByName;
  final String? updatedAt;

  factory AiPromptTemplate.fromJson(Map<String, dynamic> json) =>
      AiPromptTemplate(
        id: (json['id'] as num?)?.toInt() ?? 0,
        feature: json['feature'] as String? ?? '',
        name: json['name'] as String? ?? '',
        template: json['template'] as String? ?? '',
        version: (json['version'] as num?)?.toInt() ?? 1,
        active: json['active'] as bool? ?? false,
        changeNotes: json['changeNotes'] as String?,
        updatedByName: json['updatedByName'] as String?,
        updatedAt: json['updatedAt'] as String?,
      );
}

class AiPromptTemplateRequest {
  const AiPromptTemplateRequest({
    required this.feature,
    required this.name,
    required this.template,
    this.changeNotes,
  });

  final String feature;

  /// At most 100 characters, and the backend rejects a longer one outright.
  final String name;

  final String template;

  /// At most 500 characters. Worth filling in — it is the only record of why
  /// a version exists.
  final String? changeNotes;

  Map<String, dynamic> toJson() => {
        'feature': feature,
        'name': name,
        'template': template,
        if (changeNotes != null && changeNotes!.trim().isNotEmpty)
          'changeNotes': changeNotes!.trim(),
      };
}

/// What the assistant did on one day.
class AiUsageSummary {
  const AiUsageSummary({
    required this.totalRequests,
    required this.totalTokens,
    required this.avgResponseTimeMs,
    required this.requestsByFeature,
    required this.tokensByFeature,
    this.date,
  });

  final int totalRequests;
  final int totalTokens;
  final double avgResponseTimeMs;
  final Map<String, int> requestsByFeature;
  final Map<String, int> tokensByFeature;
  final String? date;

  static Map<String, int> _counts(Object? value) {
    if (value is! Map) return const {};
    return {
      for (final entry in value.entries)
        if (entry.key is String && entry.value is num)
          entry.key as String: (entry.value as num).toInt(),
    };
  }

  factory AiUsageSummary.fromJson(Map<String, dynamic> json) => AiUsageSummary(
        totalRequests: (json['totalRequests'] as num?)?.toInt() ?? 0,
        totalTokens: (json['totalTokens'] as num?)?.toInt() ?? 0,
        avgResponseTimeMs:
            (json['avgResponseTimeMs'] as num?)?.toDouble() ?? 0,
        requestsByFeature: _counts(json['requestsByFeature']),
        tokensByFeature: _counts(json['tokensByFeature']),
        date: json['date'] as String?,
      );
}

/// One answer from the assistant. Mirrors `AiGenerateResponse`.
///
/// Note what is not here: no id, no timestamp, and no copy of the prompt. The
/// conversation history returns this same DTO, so a past exchange can be read
/// but not dated, and the question that produced it is not in the response.
/// The uuid is the only thing distinguishing one row from another.
class AiExchange {
  const AiExchange({
    required this.result,
    this.conversationUuid,
    this.feature,
    this.provider,
    this.model,
    this.threadId,
    this.executionTimeMs = 0,
    this.awaitingConfirmation = false,
  });

  final String result;
  final String? conversationUuid;
  final String? feature;
  final String? provider;
  final String? model;
  final int? threadId;
  final int executionTimeMs;

  /// True when the answer is a proposed action waiting to be confirmed. Only
  /// the agent loop sets it; a one-shot draft never does.
  final bool awaitingConfirmation;

  factory AiExchange.fromJson(Map<String, dynamic> json) => AiExchange(
        result: json['result'] as String? ?? '',
        conversationUuid: json['conversationUuid'] as String?,
        feature: json['feature'] as String?,
        provider: json['provider'] as String?,
        model: json['model'] as String?,
        threadId: (json['threadId'] as num?)?.toInt(),
        executionTimeMs: (json['executionTimeMs'] as num?)?.toInt() ?? 0,
        awaitingConfirmation: json['awaitingConfirmation'] as bool? ?? false,
      );
}
