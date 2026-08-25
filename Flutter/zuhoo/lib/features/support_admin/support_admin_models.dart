/// Running the support desk: who staffs it, what tickets are filed under, what
/// response times are promised, and who did what.
///
/// Unlike most of the app, none of this is permission-gated. Every endpoint
/// here checks a **role** instead, and the roles differ per surface — an SLA
/// policy can only be written by a platform administrator, while a support
/// manager can staff the desk. Each list below is the exact set from the
/// controller's `@PreAuthorize`.

/// Agents: create, list, edit, set status.
const supportAgentAdminRoles = <String>['SUPER_ADMIN', 'SUPPORT_MANAGER'];

/// An agent flips their own availability, and so can their manager.
const acceptingTicketsRoles = <String>['SUPPORT_AGENT', 'SUPPORT_MANAGER'];

/// Ticket categories: anyone on the desk reads them, three roles write them.
const supportCategoryAdminRoles = <String>[
  'SUPER_ADMIN',
  'SYSTEM_ADMIN',
  'SUPPORT_MANAGER',
];

const supportCategoryViewRoles = <String>[
  'COMPANY_OWNER',
  'EMPLOYEE',
  'SUPPORT_AGENT',
  'SUPPORT_MANAGER',
  'SUPER_ADMIN',
  'SYSTEM_ADMIN',
];

/// SLA policies are read widely and written only by the platform.
const slaAdminRoles = <String>['SUPER_ADMIN', 'SYSTEM_ADMIN'];

const slaViewRoles = <String>[
  'SUPPORT_AGENT',
  'SUPPORT_MANAGER',
  'COMPANY_OWNER',
  'SUPER_ADMIN',
  'SYSTEM_ADMIN',
];

/// The audit trail. Note it is *not* open to SUPER_ADMIN — only the support
/// manager and the company owner.
const supportAuditRoles = <String>['SUPPORT_MANAGER', 'COMPANY_OWNER'];

/// Not a `SupportAgentStatus` — a pseudo-status the agent filter uses to reach
/// `/available`, which answers "who could take a ticket right now" rather than
/// "who is in this state". Kept distinct so it can never be sent as a status.
const availableAgentsFilter = 'AVAILABLE';

/// Mirrors `SupportAgentStatus`.
const agentStatuses = <String>[
  'ACTIVE',
  'ON_BREAK',
  'OFFLINE',
  'VACATION',
  'INACTIVE',
];

/// Somebody staffing the support desk.
class SupportAgent {
  const SupportAgent({
    required this.id,
    required this.status,
    required this.acceptingTickets,
    required this.maxConcurrentTickets,
    required this.totalTicketsHandled,
    this.userId,
    this.fullName,
    this.email,
    this.department,
    this.specialization,
    this.notes,
    this.avgResponseTimeMinutes,
    this.avgResolutionTimeMinutes,
    this.satisfactionScore,
    this.lastActiveTime,
  });

  final int id;
  final String status;
  final bool acceptingTickets;
  final int maxConcurrentTickets;
  final int totalTicketsHandled;
  final int? userId;
  final String? fullName;
  final String? email;
  final String? department;
  final String? specialization;
  final String? notes;
  final double? avgResponseTimeMinutes;
  final double? avgResolutionTimeMinutes;
  final double? satisfactionScore;
  final String? lastActiveTime;

  String get displayName => fullName?.trim().isNotEmpty == true
      ? fullName!
      : (email ?? 'Agent $id');

  /// Taking work right now. Both conditions matter: an agent can be marked
  /// ACTIVE and still have turned new tickets off.
  bool get isTakingWork => status == 'ACTIVE' && acceptingTickets;

  factory SupportAgent.fromJson(Map<String, dynamic> json) => SupportAgent(
        id: (json['id'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? 'OFFLINE',
        acceptingTickets: json['acceptingTickets'] as bool? ?? false,
        maxConcurrentTickets:
            (json['maxConcurrentTickets'] as num?)?.toInt() ?? 0,
        totalTicketsHandled: (json['totalTicketsHandled'] as num?)?.toInt() ?? 0,
        userId: (json['userId'] as num?)?.toInt(),
        fullName: json['fullName'] as String? ?? json['userName'] as String?,
        email: json['email'] as String?,
        department: json['department'] as String?,
        specialization: json['specialization'] as String?,
        notes: json['notes'] as String?,
        avgResponseTimeMinutes:
            (json['avgResponseTimeMinutes'] as num?)?.toDouble(),
        avgResolutionTimeMinutes:
            (json['avgResolutionTimeMinutes'] as num?)?.toDouble(),
        satisfactionScore: (json['satisfactionScore'] as num?)?.toDouble(),
        lastActiveTime: json['lastActiveTime'] as String?,
      );
}

/// POST and PATCH /v1/support/agents
///
/// The PATCH assigns **every field unconditionally** — department,
/// specialization, maxConcurrentTickets and notes are set from the request with
/// no null check. Worse, `maxConcurrentTickets` is a primitive `int` with a
/// field initialiser of 10, so an omitted key does not arrive as zero: Jackson
/// leaves the Java default and the agent's limit silently becomes 10.
///
/// The edit form therefore seeds every field from the agent and sends all of
/// them back.
///
/// `userId` is only meaningful on create — the PATCH ignores it, since an agent
/// record cannot be moved to a different user.
class SupportAgentRequest {
  const SupportAgentRequest({
    required this.maxConcurrentTickets,
    this.userId,
    this.department,
    this.specialization,
    this.status,
    this.notes,
  });

  final int maxConcurrentTickets;
  final int? userId;
  final String? department;
  final String? specialization;
  final String? status;
  final String? notes;

  factory SupportAgentRequest.from(SupportAgent agent) => SupportAgentRequest(
        maxConcurrentTickets: agent.maxConcurrentTickets,
        department: agent.department,
        specialization: agent.specialization,
        notes: agent.notes,
      );

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      // Always present — see the class comment. @Min(1) server-side.
      'maxConcurrentTickets': maxConcurrentTickets,
      // Null rather than omitted: these are assigned unconditionally, so
      // sending null is the only way to clear one, and omitting the key would
      // do exactly the same thing anyway.
      'department': clean(department),
      'specialization': clean(specialization),
      'notes': clean(notes),
      if (userId != null) 'userId': userId,
      if (status != null) 'status': status,
    };
  }
}

/// What a ticket is filed under.
class SupportCategory {
  const SupportCategory({
    required this.id,
    required this.name,
    required this.active,
    this.description,
    this.icon,
  });

  final int id;
  final String name;
  final bool active;
  final String? description;
  final String? icon;

  factory SupportCategory.fromJson(Map<String, dynamic> json) =>
      SupportCategory(
        id: (json['id'] as num?)?.toInt() ?? 0,
        // The backend calls it categoryName, not name.
        name: json['categoryName'] as String? ?? '',
        active: json['active'] as bool? ?? true,
        description: json['description'] as String?,
        icon: json['icon'] as String?,
      );
}

/// POST and PATCH /support/categories
///
/// The PATCH assigns name, description and icon unconditionally, so all three
/// go every time. It does **not** touch `active` — that has its own endpoint —
/// which is why this request does not carry it.
class SupportCategoryRequest {
  const SupportCategoryRequest({
    required this.name,
    this.description,
    this.icon,
  });

  final String name;
  final String? description;
  final String? icon;

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'categoryName': name.trim(),
      'description': clean(description),
      'icon': clean(icon),
    };
  }
}

/// What the desk promises, per priority.
class SlaPolicy {
  const SlaPolicy({
    required this.id,
    required this.name,
    required this.priority,
    required this.firstResponseTimeHours,
    required this.resolutionTimeHours,
    required this.businessHoursOnly,
    required this.active,
    this.description,
    this.notes,
  });

  final int id;
  final String name;
  final String priority;
  final int firstResponseTimeHours;
  final int resolutionTimeHours;
  final bool businessHoursOnly;
  final bool active;
  final String? description;
  final String? notes;

  factory SlaPolicy.fromJson(Map<String, dynamic> json) => SlaPolicy(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['policyName'] as String? ?? '',
        priority: json['applicablePriority'] as String? ?? 'MEDIUM',
        firstResponseTimeHours:
            (json['firstResponseTimeHours'] as num?)?.toInt() ?? 0,
        resolutionTimeHours: (json['resolutionTimeHours'] as num?)?.toInt() ?? 0,
        businessHoursOnly: json['businessHoursOnly'] as bool? ?? false,
        active: json['active'] as bool? ?? true,
        description: json['description'] as String?,
        notes: json['notes'] as String?,
      );
}

/// POST and PATCH /support/sla-policies
///
/// Every field the PATCH touches is assigned unconditionally, and two of them —
/// the hour counts — are primitive `int`s that would arrive as zero if omitted,
/// promising an instant response. All of them are always sent.
///
/// `notes` is the odd one out: the create stores it, the update never reads it.
/// The form does not offer it on an edit rather than pretending otherwise.
class SlaPolicyRequest {
  const SlaPolicyRequest({
    required this.name,
    required this.priority,
    required this.firstResponseTimeHours,
    required this.resolutionTimeHours,
    required this.businessHoursOnly,
    required this.active,
    this.description,
    this.notes,
  });

  final String name;
  final String priority;
  final int firstResponseTimeHours;
  final int resolutionTimeHours;
  final bool businessHoursOnly;
  final bool active;
  final String? description;
  final String? notes;

  Map<String, dynamic> toJson() {
    final trimmedDescription = description?.trim();
    final trimmedNotes = notes?.trim();
    return {
      'policyName': name.trim(),
      'applicablePriority': priority,
      'firstResponseTimeHours': firstResponseTimeHours,
      'resolutionTimeHours': resolutionTimeHours,
      'businessHoursOnly': businessHoursOnly,
      'active': active,
      'description':
          (trimmedDescription?.isEmpty ?? true) ? null : trimmedDescription,
      if (trimmedNotes != null && trimmedNotes.isNotEmpty) 'notes': trimmedNotes,
    };
  }
}

/// One line of the support desk's audit trail.
class SupportAuditEntry {
  const SupportAuditEntry({
    required this.id,
    required this.actionType,
    this.actionByUserName,
    this.description,
    this.resourceType,
    this.resourceId,
    this.contextSwitchToCompanyName,
    this.createdAt,
  });

  final int id;
  final String actionType;
  final String? actionByUserName;
  final String? description;
  final String? resourceType;
  final int? resourceId;

  /// Set when the action was taken while switched into a client's company —
  /// the single most important thing on the row, so it is surfaced.
  final String? contextSwitchToCompanyName;

  final String? createdAt;

  factory SupportAuditEntry.fromJson(Map<String, dynamic> json) =>
      SupportAuditEntry(
        id: (json['id'] as num?)?.toInt() ?? 0,
        actionType: json['actionType'] as String? ?? '',
        actionByUserName: json['actionByUserName'] as String?,
        description: json['description'] as String?,
        resourceType: json['resourceType'] as String?,
        resourceId: (json['resourceId'] as num?)?.toInt(),
        contextSwitchToCompanyName:
            json['contextSwitchToCompanyName'] as String?,
        createdAt: json['createdAt'] as String?,
      );
}

/// How the audit list is narrowed.
///
/// The backend has a separate endpoint per filter rather than one endpoint with
/// optional parameters, so the choice of filter picks the URL. Held as one
/// object so the screen has a single thing to pass around.
class AuditFilter {
  const AuditFilter({this.actionType, this.start, this.end});

  /// Free text — the backend matches an action type string, and the set is not
  /// an enum, so it comes from what the rows themselves show.
  final String? actionType;

  /// Both or neither. `yyyy-MM-dd`, which is what `@DateTimeFormat(ISO.DATE)`
  /// expects.
  final String? start;
  final String? end;

  bool get isEmpty => actionType == null && start == null;
  bool get hasDateRange => start != null && end != null;
}
