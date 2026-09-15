/// The pre-sales proposal that sits in front of a formal quotation.
///
/// For a customised project, staff draft what they intend to build — the
/// stack, the timeline, a summary and a rough budget — send it to the client,
/// and the client either accepts it or asks for changes. Only once it is
/// accepted does a binding [ServiceRequest.quotationAmount] follow.
///
/// The two halves belong to different people, which is the thing to keep hold
/// of when reading this file: `ProposalServiceImpl` lets **staff** write and
/// send, and lets **the client** accept or ask for changes. Neither can do the
/// other's half, so the UI offers each side only what it can actually do
/// rather than showing a button that answers 403.
library;

/// Where a proposal is in its life.
///
/// The names are the backend's `ProposalStatus` enum exactly; they travel on
/// the wire and are compared as strings.
abstract final class ProposalStatus {
  static const draft = 'DRAFT';
  static const sent = 'SENT';
  static const accepted = 'ACCEPTED';
  static const changesRequested = 'CHANGES_REQUESTED';
}

/// One file hung off a proposal — a mockup, a diagram, a spec.
///
/// The upload itself goes through `ApiClient.uploadDocument` first, exactly as
/// a request document does; this only records the URL that comes back.
class ProposalAttachment {
  const ProposalAttachment({
    required this.id,
    required this.fileName,
    required this.fileUrl,
    this.label,
  });

  final int id;
  final String fileName;
  final String fileUrl;

  /// What to call it on screen. Falls back to the file name, because an
  /// unlabelled row of "attachment, attachment, attachment" tells nobody
  /// which one they want.
  final String? label;

  String get displayName {
    final trimmed = label?.trim();
    return (trimmed == null || trimmed.isEmpty) ? fileName : trimmed;
  }

  factory ProposalAttachment.fromJson(Map<String, dynamic> json) =>
      ProposalAttachment(
        id: (json['id'] as num?)?.toInt() ?? 0,
        fileName: json['fileName'] as String? ?? 'Attachment',
        fileUrl: json['fileUrl'] as String? ?? '',
        label: json['label'] as String?,
      );
}

/// GET /service-requests/{id}/proposal
class Proposal {
  const Proposal({
    required this.id,
    required this.serviceRequestId,
    required this.title,
    required this.status,
    this.techStack,
    this.timeline,
    this.summary,
    this.estimatedBudget,
    this.clientFeedback,
    this.createdByName,
    this.sentAt,
    this.respondedAt,
    this.attachments = const [],
  });

  final int id;
  final int serviceRequestId;
  final String title;

  /// One of [ProposalStatus]. Kept as a string rather than an enum so an
  /// unfamiliar value from a newer backend renders as itself instead of
  /// crashing the screen.
  final String status;

  final String? techStack;
  final String? timeline;
  final String? summary;

  /// Free text, not a number — "৳ 4–6 lakh" and "depends on scope" are both
  /// things a pre-sales estimate legitimately says, and the backend types it
  /// as a String for that reason.
  final String? estimatedBudget;

  /// Why the client asked for changes. Cleared by the backend on every send,
  /// so it only ever describes the round it belongs to.
  final String? clientFeedback;

  final String? createdByName;
  final String? sentAt;
  final String? respondedAt;
  final List<ProposalAttachment> attachments;

  /// Staff may write to it while it is a draft, or after the client has asked
  /// for changes. `save` refuses anything else outright — see
  /// `ProposalServiceImpl.save`.
  bool get canEdit =>
      status == ProposalStatus.draft || status == ProposalStatus.changesRequested;

  /// Same two states send from: a fresh draft, or a revision after feedback.
  bool get canSend => canEdit;

  /// The client's move, and only from [ProposalStatus.sent].
  bool get awaitsClient => status == ProposalStatus.sent;

  /// Nothing more happens to an accepted proposal; a quotation follows it.
  bool get isSettled => status == ProposalStatus.accepted;

  factory Proposal.fromJson(Map<String, dynamic> json) => Proposal(
        id: (json['id'] as num?)?.toInt() ?? 0,
        serviceRequestId: (json['serviceRequestId'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? 'Proposal',
        status: json['status'] as String? ?? ProposalStatus.draft,
        techStack: json['techStack'] as String?,
        timeline: json['timeline'] as String?,
        summary: json['summary'] as String?,
        estimatedBudget: json['estimatedBudget'] as String?,
        clientFeedback: json['clientFeedback'] as String?,
        createdByName: json['createdByName'] as String?,
        sentAt: json['sentAt'] as String?,
        respondedAt: json['respondedAt'] as String?,
        attachments: (json['attachments'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(ProposalAttachment.fromJson)
                .toList(growable: false) ??
            const [],
      );
}

/// PUT /service-requests/{id}/proposal
///
/// One endpoint for both create and edit: the backend makes a DRAFT when the
/// request has no proposal yet and updates the existing one otherwise, so
/// there is no separate create call to make.
///
/// Every field but the title is optional to the backend, and each is sent even
/// when empty — this is a full replace, not a sparse patch, so omitting a
/// cleared field would silently keep the old value.
class ProposalRequest {
  const ProposalRequest({
    required this.title,
    this.techStack,
    this.timeline,
    this.summary,
    this.estimatedBudget,
  });

  final String title;
  final String? techStack;
  final String? timeline;
  final String? summary;
  final String? estimatedBudget;

  /// Seeds the form from what is already there, so opening an edit and saving
  /// it unchanged is a no-op rather than a way to lose four fields.
  factory ProposalRequest.from(Proposal proposal) => ProposalRequest(
        title: proposal.title,
        techStack: proposal.techStack,
        timeline: proposal.timeline,
        summary: proposal.summary,
        estimatedBudget: proposal.estimatedBudget,
      );

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  Map<String, dynamic> toJson() => {
        'title': title.trim(),
        'techStack': _clean(techStack),
        'timeline': _clean(timeline),
        'summary': _clean(summary),
        'estimatedBudget': _clean(estimatedBudget),
      };
}
