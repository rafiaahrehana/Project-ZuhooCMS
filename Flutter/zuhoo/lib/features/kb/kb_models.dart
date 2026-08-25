abstract final class KbPermissions {
  /// Gates the list for staff. Not for clients: `KbArticleServiceImpl.list`
  /// skips the check for a CLIENT user, who browses published, client-visible
  /// articles from the portal through the same endpoint.
  static const view = 'KNOWLEDGE_BASE_VIEW';
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
    this.categoryName,
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
  final String? categoryName;
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
        categoryName: json['categoryName'] as String?,
        relatedServiceName: json['relatedServiceName'] as String?,
        authorName: json['authorName'] as String?,
        clientVisible: json['clientVisible'] as bool? ?? false,
        publishedAt: json['publishedAt'] as String?,
      );
}
