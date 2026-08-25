abstract final class CrmPermissions {
  static const leadView = 'LEAD_VIEW';
  static const leadCreate = 'LEAD_CREATE';
  static const leadUpdate = 'LEAD_UPDATE';
  static const leadDelete = 'LEAD_DELETE';

  static const opportunityView = 'OPPORTUNITY_VIEW';
  static const opportunityCreate = 'OPPORTUNITY_CREATE';
  static const opportunityUpdate = 'OPPORTUNITY_UPDATE';
  static const opportunityDelete = 'OPPORTUNITY_DELETE';

  static const clientView = 'CLIENT_VIEW';
  static const clientCreate = 'CLIENT_CREATE';
  static const clientUpdate = 'CLIENT_UPDATE';
  static const clientDelete = 'CLIENT_DELETE';

  static const contactView = 'CONTACT_VIEW';
  static const contactCreate = 'CONTACT_CREATE';
  static const contactUpdate = 'CONTACT_UPDATE';
  static const contactDelete = 'CONTACT_DELETE';

  static const tagView = 'TAG_VIEW';

  /// One code covers creating, editing and removing a tag.
  static const tagManage = 'TAG_MANAGE';
}

/// Where a deal sits. Order matters — it is the order of the pipeline, and the
/// screens render stages in this sequence.
abstract final class Stage {
  static const qualification = 'QUALIFICATION';
  static const presentation = 'PRESENTATION';
  static const proposal = 'PROPOSAL';
  static const negotiation = 'NEGOTIATION';
  static const won = 'WON';
  static const lost = 'LOST';

  /// Still in play. The closed pair is deliberately excluded from the board:
  /// a pipeline is what you can still act on.
  static const open = [qualification, presentation, proposal, negotiation];

  static const all = [...open, won, lost];

  static bool isOpen(String stage) => open.contains(stage);
  static bool isClosed(String stage) => stage == won || stage == lost;
}

abstract final class LeadStatus {
  static const isNew = 'NEW';
  static const contacted = 'CONTACTED';
  static const qualified = 'QUALIFIED';
  static const disqualified = 'DISQUALIFIED';

  static const all = [isNew, contacted, qualified, disqualified];
}

const leadSources = <String>[
  'WEBSITE',
  'REFERRAL',
  'SOCIAL_MEDIA',
  'EMAIL',
  'PHONE',
  'COLD_CALL',
  'OTHER',
];

const leadPriorities = <String>['LOW', 'NORMAL', 'HIGH', 'URGENT'];

/// Mirrors the backend's `ClientStatus`. BLOCKED is a real state a client can
/// be put into, not a soft-delete — deleting is its own endpoint.
const clientStatuses = <String>['ACTIVE', 'INACTIVE', 'BLOCKED'];

const crmActivityTypes = <String>[
  'CALL',
  'MEETING',
  'EMAIL',
  'NOTE',
  'TASK',
  'FOLLOW_UP',
];

/// Why a deal was lost. The backend requires the code on a LOST transition, and
/// free-text detail on top of it when the code is OTHER.
const lostReasons = <({String code, String label})>[
  (code: 'PRICE', label: 'Price too high'),
  (code: 'COMPETITOR', label: 'Chose a competitor'),
  (code: 'NO_BUDGET', label: 'No budget'),
  (code: 'NO_RESPONSE', label: 'Went silent / no response'),
  (code: 'BAD_TIMING', label: 'Bad timing'),
  (code: 'REQUIREMENTS_MISMATCH', label: "Requirements didn't fit"),
  (code: 'OTHER', label: 'Other'),
];

class Tag {
  const Tag({required this.id, required this.name, required this.color});

  final int id;
  final String name;
  final String color;

  /// The backend stores a CSS hex. Anything it cannot parse falls back to null
  /// so the caller can use a neutral chip rather than crash on a bad value.
  int? get argb {
    var hex = color.trim().replaceFirst('#', '');
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length != 6) return null;
    final value = int.tryParse(hex, radix: 16);
    return value == null ? null : 0xFF000000 | value;
  }

  factory Tag.fromJson(Map<String, dynamic> json) => Tag(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        color: json['color'] as String? ?? '',
      );

  static List<Tag> listFrom(Object? raw) => raw is List
      ? raw.whereType<Map<String, dynamic>>().map(Tag.fromJson).toList()
      : const [];
}

/// A client the backend thinks this deal might already belong to.
class DuplicateMatch {
  const DuplicateMatch({
    required this.clientId,
    required this.clientCompanyName,
    required this.matchedOn,
  });

  final int clientId;
  final String clientCompanyName;

  /// Which field matched — the reason to trust or dismiss the suggestion.
  final String matchedOn;

  static DuplicateMatch? tryFrom(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = (json['clientId'] as num?)?.toInt();
    if (id == null) return null;
    return DuplicateMatch(
      clientId: id,
      clientCompanyName: json['clientCompanyName'] as String? ?? '',
      matchedOn: json['matchedOn'] as String? ?? '',
    );
  }
}

class Lead {
  const Lead({
    required this.id,
    required this.contactName,
    required this.status,
    required this.source,
    required this.createdAt,
    required this.converted,
    this.companyName,
    this.email,
    this.phone,
    this.industry,
    this.jobTitle,
    this.notes,
    this.priority,
    this.estimatedValue,
    this.expectedCloseDate,
    this.assignedToName,
    this.lastContactDate,
    this.lastActivityAt,
    this.convertedClientName,
    this.activitiesCount,
    this.tags = const [],
    this.possibleDuplicate,
  });

  final int id;
  final String contactName;
  final String status;
  final String source;
  final String createdAt;
  final bool converted;
  final String? companyName;
  final String? email;
  final String? phone;
  final String? industry;
  final String? jobTitle;
  final String? notes;
  final String? priority;
  final double? estimatedValue;
  final String? expectedCloseDate;
  final String? assignedToName;
  final String? lastContactDate;
  final String? lastActivityAt;
  final String? convertedClientName;
  final int? activitiesCount;
  final List<Tag> tags;
  final DuplicateMatch? possibleDuplicate;

  /// Only a qualified lead that has not already been converted can become an
  /// opportunity — the backend enforces both, and offering the action anyway
  /// would just produce an error.
  bool get canConvert => status == LeadStatus.qualified && !converted;

  bool get isUnassigned => assignedToName == null;

  /// Nobody has recorded contact yet.
  bool get neverContacted => lastContactDate == null && lastActivityAt == null;

  /// What to call this lead in a list: the company if there is one, since a
  /// rep thinks in accounts, with the person underneath.
  String get headline =>
      (companyName != null && companyName!.trim().isNotEmpty)
          ? companyName!
          : contactName;

  String? get subline =>
      (companyName != null && companyName!.trim().isNotEmpty)
          ? contactName
          : (jobTitle ?? email);

  factory Lead.fromJson(Map<String, dynamic> json) => Lead(
        id: (json['id'] as num?)?.toInt() ?? 0,
        contactName: json['contactName'] as String? ?? '',
        status: json['status'] as String? ?? LeadStatus.isNew,
        source: json['source'] as String? ?? '',
        createdAt: json['createdAt'] as String? ?? '',
        converted: json['converted'] as bool? ?? false,
        companyName: json['companyName'] as String?,
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        industry: json['industry'] as String?,
        jobTitle: json['jobTitle'] as String?,
        notes: json['notes'] as String? ?? json['description'] as String?,
        priority: json['priority'] as String?,
        estimatedValue: (json['estimatedValue'] as num?)?.toDouble(),
        expectedCloseDate: json['expectedCloseDate'] as String?,
        assignedToName: json['assignedToName'] as String?,
        lastContactDate: json['lastContactDate'] as String?,
        lastActivityAt: json['lastActivityAt'] as String?,
        convertedClientName: json['convertedClientName'] as String?,
        activitiesCount: (json['activitiesCount'] as num?)?.toInt(),
        tags: Tag.listFrom(json['tags']),
        possibleDuplicate: DuplicateMatch.tryFrom(json['possibleDuplicate']),
      );
}

class Opportunity {
  const Opportunity({
    required this.id,
    required this.name,
    required this.stage,
    required this.probability,
    required this.createdAt,
    this.description,
    this.source,
    this.amount,
    this.weightedAmount,
    this.expectedCloseDate,
    this.actualCloseDate,
    this.nextStep,
    this.lostReason,
    this.lostReasonCode,
    this.clientId,
    this.clientCompanyName,
    this.contactName,
    this.ownerName,
    this.lastActivityAt,
    this.stageChangedAt,
    this.sourceLeadId,
    this.tags = const [],
  });

  final int id;
  final String name;
  final String stage;

  /// Percent, server-derived from the stage.
  final int probability;

  final String createdAt;
  final String? description;
  final String? source;
  final double? amount;

  /// amount × probability, computed server-side. Taken as given so the phone
  /// and the web forecast cannot disagree.
  final double? weightedAmount;

  final String? expectedCloseDate;
  final String? actualCloseDate;
  final String? nextStep;
  final String? lostReason;
  final String? lostReasonCode;

  /// Null until the deal reaches Won and a client is created or linked.
  final int? clientId;

  final String? clientCompanyName;
  final String? contactName;
  final String? ownerName;
  final String? lastActivityAt;
  final String? stageChangedAt;
  final int? sourceLeadId;
  final List<Tag> tags;

  bool get isOpen => Stage.isOpen(stage);
  bool get isWon => stage == Stage.won;
  bool get isLost => stage == Stage.lost;

  /// Winning a deal with no client attached is what triggers the duplicate
  /// check — the backend has to decide whether to create a client or link an
  /// existing one, and it asks first.
  bool get needsClientDecisionOnWin => clientId == null;

  /// Past its expected close date and still open.
  bool get isOverdue {
    if (!isOpen || expectedCloseDate == null) return false;
    final due = DateTime.tryParse(expectedCloseDate!);
    if (due == null) return false;
    final today = DateTime.now();
    return DateTime(due.year, due.month, due.day)
        .isBefore(DateTime(today.year, today.month, today.day));
  }

  factory Opportunity.fromJson(Map<String, dynamic> json) => Opportunity(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        stage: json['stage'] as String? ?? Stage.qualification,
        probability: (json['probability'] as num?)?.toInt() ?? 0,
        createdAt: json['createdAt'] as String? ?? '',
        description: json['description'] as String?,
        source: json['source'] as String?,
        amount: (json['amount'] as num?)?.toDouble(),
        weightedAmount: (json['weightedAmount'] as num?)?.toDouble(),
        expectedCloseDate: json['expectedCloseDate'] as String?,
        actualCloseDate: json['actualCloseDate'] as String?,
        nextStep: json['nextStep'] as String?,
        lostReason: json['lostReason'] as String?,
        lostReasonCode: json['lostReasonCode'] as String?,
        clientId: (json['clientId'] as num?)?.toInt(),
        clientCompanyName: json['clientCompanyName'] as String?,
        contactName: json['contactName'] as String?,
        ownerName: json['ownerName'] as String?,
        lastActivityAt: json['lastActivityAt'] as String?,
        stageChangedAt: json['stageChangedAt'] as String?,
        sourceLeadId: (json['sourceLeadId'] as num?)?.toInt(),
        tags: Tag.listFrom(json['tags']),
      );
}

class PipelineStageSummary {
  const PipelineStageSummary({
    required this.stage,
    required this.dealCount,
    required this.totalAmount,
    required this.weightedAmount,
  });

  final String stage;
  final int dealCount;
  final double totalAmount;
  final double weightedAmount;

  factory PipelineStageSummary.fromJson(Map<String, dynamic> json) =>
      PipelineStageSummary(
        stage: json['stage'] as String? ?? '',
        dealCount: (json['dealCount'] as num?)?.toInt() ?? 0,
        totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0,
        weightedAmount: (json['weightedAmount'] as num?)?.toDouble() ?? 0,
      );
}

class PipelineSummary {
  const PipelineSummary({
    this.stages = const [],
    this.openPipelineValue = 0,
    this.weightedForecast = 0,
    this.wonValue = 0,
    this.totalOpenDeals = 0,
  });

  final List<PipelineStageSummary> stages;
  final double openPipelineValue;
  final double weightedForecast;
  final double wonValue;
  final int totalOpenDeals;

  PipelineStageSummary? forStage(String stage) {
    for (final summary in stages) {
      if (summary.stage == stage) return summary;
    }
    return null;
  }

  factory PipelineSummary.fromJson(Map<String, dynamic> json) =>
      PipelineSummary(
        stages: (json['stages'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(PipelineStageSummary.fromJson)
                .toList() ??
            const [],
        openPipelineValue: (json['openPipelineValue'] as num?)?.toDouble() ?? 0,
        weightedForecast: (json['weightedForecast'] as num?)?.toDouble() ?? 0,
        wonValue: (json['wonValue'] as num?)?.toDouble() ?? 0,
        totalOpenDeals: (json['totalOpenDeals'] as num?)?.toInt() ?? 0,
      );
}

class CrmActivity {
  const CrmActivity({
    required this.id,
    required this.type,
    required this.subject,
    required this.activityDate,
    required this.completed,
    required this.systemGenerated,
    this.description,
    this.performedByName,
    this.createdAt,
  });

  final int id;
  final String type;
  final String subject;
  final String activityDate;
  final bool completed;

  /// Written by the backend rather than a person — a stage change, say. Shown
  /// differently so a rep can tell their own notes from the audit trail.
  final bool systemGenerated;

  final String? description;
  final String? performedByName;
  final String? createdAt;

  factory CrmActivity.fromJson(Map<String, dynamic> json) => CrmActivity(
        id: (json['id'] as num?)?.toInt() ?? 0,
        type: json['type'] as String? ?? 'NOTE',
        subject: json['subject'] as String? ?? '',
        activityDate: json['activityDate'] as String? ??
            json['createdAt'] as String? ??
            '',
        completed: json['completed'] as bool? ?? false,
        systemGenerated: json['systemGenerated'] as bool? ?? false,
        description: json['description'] as String?,
        performedByName: json['performedByName'] as String?,
        createdAt: json['createdAt'] as String?,
      );
}

class Client {
  const Client({
    required this.id,
    required this.status,
    required this.createdAt,
    this.firstName,
    this.lastName,
    this.email,
    this.phone,
    this.clientCompanyName,
    this.industry,
    this.website,
    this.portalAccessEnabled,
    this.accountManagerName,
    this.onboardedAt,
    this.employeeCount,
    this.annualRevenue,
    this.lifetimeValue,
    this.totalRequests,
    this.tags = const [],
  });

  final int id;
  final String status;
  final String createdAt;
  final String? firstName;
  final String? lastName;
  final String? email;
  final String? phone;
  final String? clientCompanyName;
  final String? industry;
  final String? website;
  final bool? portalAccessEnabled;
  final String? accountManagerName;
  final String? onboardedAt;
  final int? employeeCount;
  final double? annualRevenue;
  final double? lifetimeValue;
  final int? totalRequests;
  final List<Tag> tags;

  String get contactName => [firstName, lastName]
      .where((part) => part != null && part.trim().isNotEmpty)
      .join(' ')
      .trim();

  /// The account is the company where there is one; otherwise the person.
  String get headline {
    final company = clientCompanyName?.trim();
    if (company != null && company.isNotEmpty) return company;
    final contact = contactName;
    return contact.isNotEmpty ? contact : (email ?? 'Client #$id');
  }

  String? get subline {
    final company = clientCompanyName?.trim();
    if (company != null && company.isNotEmpty) {
      final contact = contactName;
      return contact.isNotEmpty ? contact : email;
    }
    return email;
  }

  String get initials {
    final source = headline.trim();
    if (source.isEmpty) return '?';
    final parts = source.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory Client.fromJson(Map<String, dynamic> json) => Client(
        id: (json['id'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? 'ACTIVE',
        createdAt: json['createdAt'] as String? ?? '',
        firstName: json['firstName'] as String?,
        lastName: json['lastName'] as String?,
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        clientCompanyName: json['clientCompanyName'] as String?,
        industry: json['industry'] as String?,
        website: json['website'] as String?,
        portalAccessEnabled: json['portalAccessEnabled'] as bool?,
        accountManagerName: json['accountManagerName'] as String?,
        onboardedAt: json['onboardedAt'] as String?,
        employeeCount: (json['employeeCount'] as num?)?.toInt(),
        annualRevenue: (json['annualRevenue'] as num?)?.toDouble(),
        lifetimeValue: (json['lifetimeValue'] as num?)?.toDouble(),
        totalRequests: (json['totalRequests'] as num?)?.toInt(),
        tags: Tag.listFrom(json['tagList']),
      );
}

/// PATCH /crm/leads/{id}/convert-to-opportunity
class ConvertLeadRequest {
  const ConvertLeadRequest({
    required this.opportunityName,
    required this.expectedValue,
    required this.expectedCloseDate,
  });

  final String opportunityName;
  final double expectedValue;

  /// `yyyy-MM-dd`.
  final String expectedCloseDate;

  Map<String, dynamic> toJson() => {
        'opportunityName': opportunityName.trim(),
        'expectedValue': expectedValue,
        'expectedCloseDate': expectedCloseDate,
      };
}

/// PATCH /crm/opportunities/{id}/stage
class ChangeStageRequest {
  const ChangeStageRequest({
    required this.stage,
    this.lostReasonCode,
    this.lostReason,
    this.linkToExistingClientId,
    this.forceCreateNewClient,
  });

  final String stage;
  final String? lostReasonCode;
  final String? lostReason;

  /// Winning a client-less deal: attach it to this existing client…
  final int? linkToExistingClientId;

  /// …or tell the backend to make a new one anyway.
  final bool? forceCreateNewClient;

  Map<String, dynamic> toJson() => {
        'stage': stage,
        if (lostReasonCode != null) 'lostReasonCode': lostReasonCode,
        if (lostReason != null && lostReason!.trim().isNotEmpty)
          'lostReason': lostReason!.trim(),
        if (linkToExistingClientId != null)
          'linkToExistingClientId': linkToExistingClientId,
        if (forceCreateNewClient != null)
          'forceCreateNewClient': forceCreateNewClient,
      };
}

/// POST /crm/leads
class CreateLeadRequest {
  const CreateLeadRequest({
    required this.contactName,
    required this.source,
    this.companyName,
    this.email,
    this.phone,
    this.jobTitle,
    this.priority,
    this.estimatedValue,
    this.notes,
  });

  final String contactName;
  final String source;
  final String? companyName;
  final String? email;
  final String? phone;
  final String? jobTitle;
  final String? priority;
  final double? estimatedValue;
  final String? notes;

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'contactName': contactName.trim(),
      'source': source,
      if (clean(companyName) != null) 'companyName': clean(companyName),
      if (clean(email) != null) 'email': clean(email),
      if (clean(phone) != null) 'phone': clean(phone),
      if (clean(jobTitle) != null) 'jobTitle': clean(jobTitle),
      if (priority != null) 'priority': priority,
      if (estimatedValue != null) 'estimatedValue': estimatedValue,
      if (clean(notes) != null) 'notes': clean(notes),
    };
  }
}

/// POST /crm/leads/{id}/activities
class LogActivityRequest {
  const LogActivityRequest({
    required this.type,
    required this.subject,
    this.description,
  });

  final String type;
  final String subject;
  final String? description;

  Map<String, dynamic> toJson() => {
        'type': type,
        'subject': subject.trim(),
        if (description != null && description!.trim().isNotEmpty)
          'description': description!.trim(),
        // Logging something that already happened; a scheduled follow-up is a
        // different flow the web app owns.
        'completed': true,
      };
}

/// PATCH /crm/leads/{id}
///
/// The endpoint takes the same `LeadRequest` as create and validates it with
/// `@Valid`, so **contactName is always sent** even when it has not been
/// touched — a body without it fails `@NotBlank` before the service runs.
/// Everything else is a true sparse patch: `updateLead` only assigns fields
/// that arrive non-null, so an omitted key leaves the stored value alone.
///
/// The service refuses to edit a lead that is converted or DISQUALIFIED, which
/// is why the UI hides the action rather than offering an edit that 400s.
class UpdateLeadRequest {
  const UpdateLeadRequest({
    required this.contactName,
    this.companyName,
    this.email,
    this.phone,
    this.jobTitle,
    this.industry,
    this.status,
    this.source,
    this.priority,
    this.estimatedValue,
    this.notes,
  });

  final String contactName;
  final String? companyName;
  final String? email;
  final String? phone;
  final String? jobTitle;
  final String? industry;
  final String? status;
  final String? source;
  final String? priority;
  final double? estimatedValue;
  final String? notes;

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'contactName': contactName.trim(),
      if (clean(companyName) != null) 'companyName': clean(companyName),
      if (clean(email) != null) 'email': clean(email),
      if (clean(phone) != null) 'phone': clean(phone),
      if (clean(jobTitle) != null) 'jobTitle': clean(jobTitle),
      if (clean(industry) != null) 'industry': clean(industry),
      if (status != null) 'status': status,
      if (source != null) 'source': source,
      if (priority != null) 'priority': priority,
      if (estimatedValue != null) 'estimatedValue': estimatedValue,
      if (clean(notes) != null) 'notes': clean(notes),
    };
  }
}

/// POST /clients
///
/// `provisionPortalLogin` is sent explicitly as false. The backend defaults it
/// to false too, but switching it on emails the client a set-password link —
/// that is a decision, not a default worth inheriting silently. Inviting them
/// to the portal later is its own endpoint, which stays on the web.
class CreateClientRequest {
  const CreateClientRequest({
    required this.firstName,
    required this.lastName,
    required this.email,
    this.phone,
    this.clientCompanyName,
    this.industry,
    this.website,
    this.employeeCount,
  });

  final String firstName;
  final String lastName;
  final String email;
  final String? phone;
  final String? clientCompanyName;
  final String? industry;
  final String? website;
  final int? employeeCount;

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'firstName': firstName.trim(),
      'lastName': lastName.trim(),
      'email': email.trim(),
      'provisionPortalLogin': false,
      if (clean(phone) != null) 'phone': clean(phone),
      if (clean(clientCompanyName) != null)
        'clientCompanyName': clean(clientCompanyName),
      if (clean(industry) != null) 'industry': clean(industry),
      if (clean(website) != null) 'website': clean(website),
      if (employeeCount != null) 'employeeCount': employeeCount,
    };
  }
}

/// PATCH /clients/{id}
///
/// A genuine sparse patch — `ClientServiceImpl.update` null-checks every field,
/// so an omitted key leaves it alone. Name and email are absent on purpose:
/// they live on the client's user account rather than the client record, and
/// this endpoint cannot change them.
class UpdateClientRequest {
  const UpdateClientRequest({
    this.clientCompanyName,
    this.industry,
    this.website,
    this.status,
    this.employeeCount,
  });

  final String? clientCompanyName;
  final String? industry;
  final String? website;
  final String? status;
  final int? employeeCount;

  factory UpdateClientRequest.from(Client client) => UpdateClientRequest(
        clientCompanyName: client.clientCompanyName,
        industry: client.industry,
        website: client.website,
        status: client.status,
        employeeCount: client.employeeCount,
      );

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      if (clean(clientCompanyName) != null)
        'clientCompanyName': clean(clientCompanyName),
      if (clean(industry) != null) 'industry': clean(industry),
      if (clean(website) != null) 'website': clean(website),
      if (status != null) 'status': status,
      if (employeeCount != null) 'employeeCount': employeeCount,
    };
  }
}

/// POST /crm/opportunities and PATCH /crm/opportunities/{id}
///
/// One class for both, because the backend uses one DTO for both.
///
/// **`description` and `nextStep` are always sent, even when empty.** Unlike
/// every other field on this endpoint, `OpportunityServiceImpl.update` assigns
/// those two *unconditionally* — omitting them does not leave them alone, it
/// erases them. So the edit form seeds both from the current deal and sends
/// them back whether or not they were touched.
///
/// The stage is deliberately absent: moving a deal is `PATCH /{id}/stage`, and
/// routing it through here would skip the stage-change bookkeeping that drives
/// probability and the weighted forecast.
class OpportunityRequest {
  const OpportunityRequest({
    required this.name,
    required this.description,
    required this.nextStep,
    this.clientId,
    this.amount,
    this.expectedCloseDate,
    this.source,
  });

  final String name;

  /// Nullable but never omitted — see the class comment.
  final String? description;

  /// Nullable but never omitted — see the class comment.
  final String? nextStep;

  /// Required by the service on create, ignored on update.
  final int? clientId;

  final double? amount;
  final String? expectedCloseDate;
  final String? source;

  factory OpportunityRequest.from(Opportunity opportunity) =>
      OpportunityRequest(
        name: opportunity.name,
        description: opportunity.description,
        nextStep: opportunity.nextStep,
        clientId: opportunity.clientId,
        amount: opportunity.amount,
        expectedCloseDate: opportunity.expectedCloseDate,
        source: opportunity.source,
      );

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'name': name.trim(),
      // Deliberately unconditional: see the class comment.
      'description': clean(description),
      'nextStep': clean(nextStep),
      if (clientId != null) 'clientId': clientId,
      if (amount != null) 'amount': amount,
      if (expectedCloseDate != null) 'expectedCloseDate': expectedCloseDate,
      if (source != null) 'source': source,
    };
  }
}

/// A named person at a client company.
///
/// Distinct from the client itself: a client is an organisation, and the
/// contacts are the people at it you actually deal with. One of them is the
/// primary, and there is only ever one — marking a new primary clears the old.
class ClientContact {
  const ClientContact({
    required this.id,
    required this.fullName,
    required this.primaryContact,
    this.clientId,
    this.clientCompanyName,
    this.email,
    this.phone,
    this.jobTitle,
    this.department,
    this.notes,
  });

  final int id;
  final String fullName;
  final bool primaryContact;
  final int? clientId;
  final String? clientCompanyName;
  final String? email;
  final String? phone;
  final String? jobTitle;
  final String? department;
  final String? notes;

  /// What they do and where, for the row's subtitle.
  String get role => [
        if (jobTitle != null) jobTitle!,
        if (department != null) department!,
      ].join(' · ');

  factory ClientContact.fromJson(Map<String, dynamic> json) => ClientContact(
        id: (json['id'] as num?)?.toInt() ?? 0,
        fullName: json['fullName'] as String? ?? '',
        primaryContact: json['primaryContact'] as bool? ?? false,
        clientId: (json['clientId'] as num?)?.toInt(),
        clientCompanyName: json['clientCompanyName'] as String?,
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        jobTitle: json['jobTitle'] as String?,
        department: json['department'] as String?,
        notes: json['notes'] as String?,
      );
}

/// POST and PATCH /clients/{clientId}/contacts
///
/// The update assigns email, phone, job title, department and notes
/// **unconditionally** — only the name is null-guarded — so all five go on
/// every save. The name is `@NotBlank` and capped at 150; email 255, phone 30,
/// job title and department 100 each.
///
/// `primaryContact` is one-way: setting it true clears whoever held it, and
/// setting it false does nothing. Somebody has to be the primary, so the form
/// offers promotion rather than a toggle.
class ClientContactRequest {
  const ClientContactRequest({
    required this.fullName,
    this.email,
    this.phone,
    this.jobTitle,
    this.department,
    this.notes,
    this.primaryContact,
  });

  final String fullName;
  final String? email;
  final String? phone;
  final String? jobTitle;
  final String? department;
  final String? notes;
  final bool? primaryContact;

  factory ClientContactRequest.from(ClientContact contact) =>
      ClientContactRequest(
        fullName: contact.fullName,
        email: contact.email,
        phone: contact.phone,
        jobTitle: contact.jobTitle,
        department: contact.department,
        notes: contact.notes,
      );

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'fullName': fullName.trim(),
      // Explicit nulls: these are assigned without a guard, so an absent key
      // clears them just the same and saying so is honest.
      'email': clean(email),
      'phone': clean(phone),
      'jobTitle': clean(jobTitle),
      'department': clean(department),
      'notes': clean(notes),
      // Only ever sent as true — see the class comment.
      if (primaryContact == true) 'primaryContact': true,
    };
  }
}

/// POST and PATCH /crm/tags
///
/// The shared vocabulary tags are drawn from, rather than free text per record.
/// Both fields are required by the DTO.
class TagRequest {
  const TagRequest({required this.name, required this.color});

  final String name;

  /// A hex colour as the backend stores it, with or without the leading hash —
  /// `Tag.fromJson` parses either.
  final String color;

  Map<String, dynamic> toJson() => {
        'name': name.trim(),
        'color': color.trim(),
      };
}

/// POST /crm/activities
///
/// A fuller activity than [LogActivityRequest], which only ever logs something
/// already done against a lead. This one can also schedule a follow-up, and
/// attaches to a client or an opportunity rather than a lead.
///
/// `type` and `subject` are required; the subject is capped at 200.
class CrmActivityRequest {
  const CrmActivityRequest({
    required this.type,
    required this.subject,
    this.description,
    this.scheduledAt,
    this.completed,
    this.clientId,
    this.opportunityId,
  });

  final String type;
  final String subject;
  final String? description;

  /// ISO date-time. Set for something still to happen.
  final String? scheduledAt;

  /// False for a follow-up that has been booked but not done.
  final bool? completed;

  final int? clientId;
  final int? opportunityId;

  Map<String, dynamic> toJson() {
    final trimmed = description?.trim();
    return {
      'type': type,
      'subject': subject.trim(),
      if (trimmed != null && trimmed.isNotEmpty) 'description': trimmed,
      if (scheduledAt != null) 'scheduledAt': scheduledAt,
      if (completed != null) 'completed': completed,
      if (clientId != null) 'clientId': clientId,
      if (opportunityId != null) 'opportunityId': opportunityId,
    };
  }
}
