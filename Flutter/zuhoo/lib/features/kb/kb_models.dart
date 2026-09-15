abstract final class KbPermissions {
  /// Gates the list for staff. Not for clients: `KbArticleServiceImpl.list`
  /// skips the check for a CLIENT user, who browses published, client-visible
  /// articles from the portal through the same endpoint.
  static const view = 'KNOWLEDGE_BASE_VIEW';
  static const create = 'KNOWLEDGE_BASE_CREATE';

  /// The one code that covers editing, publishing and archiving alike — there
  /// is no separate publish permission, so anybody who can edit can publish.
  static const update = 'KNOWLEDGE_BASE_UPDATE';
}

abstract final class KbArticleStatus {
  static const draft = 'DRAFT';
  static const published = 'PUBLISHED';
  static const archived = 'ARCHIVED';
}

/// One knowledge-base article.
///
/// `content` is plain text as the backend stores it. It is rendered as text
/// rather than parsed as markup: the web editor does not guarantee any one
/// format, and a phone guessing wrong would show tags instead of prose.
class KbArticle {
  const KbArticle({
    required this.id,
    required this.title,
    required this.status,
    required this.viewCount,
    required this.helpfulCount,
    this.summary,
    this.content,
    this.keywords,
    this.categoryId,
    this.categoryName,
    this.relatedServiceId,
    this.relatedServiceName,
    this.authorName,
    this.clientVisible = false,
    this.publishedAt,
  });

  final int id;
  final String title;
  final String status;
  final int viewCount;
  final int helpfulCount;
  final String? summary;
  final String? content;
  final String? keywords;
  final int? categoryId;
  final String? categoryName;
  final int? relatedServiceId;
  final String? relatedServiceName;
  final String? authorName;

  /// Whether a portal client can see it too. Shown to staff as a small badge,
  /// because it changes what they can safely paste to a customer.
  final bool clientVisible;

  final String? publishedAt;

  bool get isPublished => status == KbArticleStatus.published;

  /// The line under the title in a list. The summary if there is one, else the
  /// opening of the article itself — an untitled-looking row is worse than a
  /// slightly clipped first sentence.
  String? get preview {
    final trimmedSummary = summary?.trim();
    if (trimmedSummary != null && trimmedSummary.isNotEmpty) {
      return trimmedSummary;
    }
    final body = content?.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (body == null || body.isEmpty) return null;
    return body.length <= 160 ? body : '${body.substring(0, 160)}…';
  }

  /// Keywords as a list, for the chips on the detail screen. Stored as one
  /// comma-separated string server-side.
  List<String> get keywordList {
    final raw = keywords?.trim();
    if (raw == null || raw.isEmpty) return const [];
    return raw
        .split(',')
        .map((keyword) => keyword.trim())
        .where((keyword) => keyword.isNotEmpty)
        .toList(growable: false);
  }

  factory KbArticle.fromJson(Map<String, dynamic> json) => KbArticle(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? 'Untitled article',
        status: json['status'] as String? ?? KbArticleStatus.draft,
        viewCount: (json['viewCount'] as num?)?.toInt() ?? 0,
        helpfulCount: (json['helpfulCount'] as num?)?.toInt() ?? 0,
        summary: json['summary'] as String?,
        content: json['content'] as String?,
        keywords: json['keywords'] as String?,
        categoryId: (json['categoryId'] as num?)?.toInt(),
        categoryName: json['categoryName'] as String?,
        relatedServiceId: (json['relatedServiceId'] as num?)?.toInt(),
        relatedServiceName: json['relatedServiceName'] as String?,
        authorName: json['authorName'] as String?,
        clientVisible: json['clientVisible'] as bool? ?? false,
        publishedAt: json['publishedAt'] as String?,
      );
}


/// Writing or rewriting an article.
///
/// `PATCH` in name only. `KbArticleServiceImpl.update` assigns every field
/// without a null check, so an omitted key clears what was there — and
/// `clientVisible` is a Java primitive, meaning an absent one arrives as
/// `false` and quietly hides the article from clients. Nothing is optional in
/// this model for that reason: the edit form always loads the article first
/// and sends it back whole.
///
/// The status is not in here. Publishing and archiving have their own
/// endpoints, and an edit never changes it.
class KbArticleRequest {
  const KbArticleRequest({
    required this.title,
    required this.content,
    required this.clientVisible,
    this.summary,
    this.keywords,
    this.categoryId,
    this.relatedServiceId,
  });

  final String title;
  final String content;
  final bool clientVisible;
  final String? summary;

  /// Free text, comma-separated by convention. The backend stores the string
  /// as given and searches it with a LIKE, so nothing enforces the commas.
  final String? keywords;

  final int? categoryId;
  final int? relatedServiceId;

  /// Seeds an edit from what is already there, so the fields the form does not
  /// show are sent back unchanged rather than wiped.
  factory KbArticleRequest.from(KbArticle article) => KbArticleRequest(
        title: article.title,
        content: article.content ?? '',
        clientVisible: article.clientVisible,
        summary: article.summary,
        keywords: article.keywords,
        categoryId: article.categoryId,
        relatedServiceId: article.relatedServiceId,
      );

  KbArticleRequest copyWith({
    String? title,
    String? content,
    bool? clientVisible,
    String? summary,
    String? keywords,
    int? categoryId,
    int? relatedServiceId,
  }) =>
      KbArticleRequest(
        title: title ?? this.title,
        content: content ?? this.content,
        clientVisible: clientVisible ?? this.clientVisible,
        summary: summary ?? this.summary,
        keywords: keywords ?? this.keywords,
        categoryId: categoryId ?? this.categoryId,
        relatedServiceId: relatedServiceId ?? this.relatedServiceId,
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'content': content,
        'clientVisible': clientVisible,
        'summary': summary,
        'keywords': keywords,
        'categoryId': categoryId,
        'relatedServiceId': relatedServiceId,
      };
}
