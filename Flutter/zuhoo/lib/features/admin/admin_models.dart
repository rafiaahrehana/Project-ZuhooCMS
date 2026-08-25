/// Company configuration: the lists everything else is chosen from.
///
/// Each surface here is the same shape — list, create, edit, toggle active —
/// and each is gated on its own permission, so the screen shows only the tabs
/// a given administrator could actually load.
abstract final class AdminPermissions {
  static const departmentView = 'DEPARTMENT_VIEW';
  static const departmentCreate = 'DEPARTMENT_CREATE';
  static const departmentUpdate = 'DEPARTMENT_UPDATE';

  static const designationView = 'DESIGNATION_VIEW';
  static const designationCreate = 'DESIGNATION_CREATE';
  static const designationUpdate = 'DESIGNATION_UPDATE';

  static const announcementView = 'ANNOUNCEMENT_VIEW';
  static const announcementCreate = 'ANNOUNCEMENT_CREATE';
  static const announcementUpdate = 'ANNOUNCEMENT_UPDATE';

  static const serviceCategoryView = 'SERVICE_CATEGORY_VIEW';
  static const serviceCategoryCreate = 'SERVICE_CATEGORY_CREATE';
  static const serviceCategoryUpdate = 'SERVICE_CATEGORY_UPDATE';
}

/// Who may manage custom roles.
///
/// Roles are gated on **roles**, not permission codes — which is the only
/// arrangement that makes sense for the screen that defines what permission
/// codes mean. Assigning one to somebody is narrower still: owner only, not
/// platform staff.
const customRoleRoles = <String>[
  'COMPANY_OWNER',
  'SUPER_ADMIN',
  'SYSTEM_ADMIN',
];

/// Only the company's own owner may put an employee into a role.
const customRoleAssignRoles = <String>['COMPANY_OWNER'];

/// Who an announcement is for. Mirrors `AnnouncementAudience`.
const announcementAudiences = <String>[
  'ALL',
  'DEPARTMENT',
  'MANAGERS',
  'CLIENTS',
];

// ── Requests ──────────────────────────────────────────────────

/// POST and PUT /departments
///
/// `name` is `@NotBlank` and assigned unconditionally on update, so it always
/// goes. Everything else is null-guarded server-side, so an omitted field is
/// left as it was.
class DepartmentRequest {
  const DepartmentRequest({
    required this.name,
    this.code,
    this.description,
    this.headEmployeeId,
    this.parentDepartmentId,
    this.budget,
  });

  final String name;
  final String? code;
  final String? description;
  final int? headEmployeeId;
  final int? parentDepartmentId;
  final double? budget;

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'name': name.trim(),
      if (clean(code) != null) 'code': clean(code),
      if (clean(description) != null) 'description': clean(description),
      if (headEmployeeId != null) 'headEmployeeId': headEmployeeId,
      if (parentDepartmentId != null)
        'parentDepartmentId': parentDepartmentId,
      if (budget != null) 'budget': budget,
    };
  }
}

/// A job grade.
class Designation {
  const Designation({
    required this.id,
    required this.name,
    required this.code,
    required this.level,
    required this.active,
    this.description,
    this.employmentCategory,
    this.departmentId,
    this.departmentName,
  });

  final int id;
  final String name;
  final String code;

  /// Seniority. Lower is more senior in this codebase's ordering, and the list
  /// is sorted by it, so it is shown rather than hidden as an implementation
  /// detail.
  final int level;

  final bool active;
  final String? description;
  final String? employmentCategory;
  final int? departmentId;
  final String? departmentName;

  factory Designation.fromJson(Map<String, dynamic> json) => Designation(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        code: json['code'] as String? ?? '',
        level: (json['level'] as num?)?.toInt() ?? 0,
        active: json['active'] as bool? ?? true,
        description: json['description'] as String?,
        employmentCategory: json['employmentCategory'] as String?,
        departmentId: (json['departmentId'] as num?)?.toInt(),
        departmentName: json['departmentName'] as String?,
      );
}

/// POST and PUT /hr/designations
///
/// **`employmentCategory` and `departmentId` are sent whether or not they have
/// a value.** `DesignationServiceImpl.update` assigns both unconditionally —
/// `setEmploymentCategory(request.getEmploymentCategory())` and
/// `setDepartment(resolveDepartment(request.getDepartmentId(), …))` — so an
/// omitted key clears them rather than leaving them alone.
///
/// `code` is upper-cased server-side before the uniqueness check, so it is
/// upper-cased here too and the field shows what will actually be stored.
class DesignationRequest {
  const DesignationRequest({
    required this.name,
    required this.code,
    required this.level,
    this.description,
    this.employmentCategory,
    this.departmentId,
    this.active,
  });

  final String name;
  final String code;
  final int level;
  final String? description;
  final String? employmentCategory;
  final int? departmentId;
  final bool? active;

  factory DesignationRequest.from(Designation designation) =>
      DesignationRequest(
        name: designation.name,
        code: designation.code,
        level: designation.level,
        description: designation.description,
        employmentCategory: designation.employmentCategory,
        departmentId: designation.departmentId,
        active: designation.active,
      );

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'name': name.trim(),
      'code': code.trim().toUpperCase(),
      'level': level,
      if (clean(description) != null) 'description': clean(description),
      if (active != null) 'active': active,
      // Unconditional: see the class comment.
      'employmentCategory': clean(employmentCategory),
      'departmentId': departmentId,
    };
  }
}

/// A company announcement, as the admin list shows it.
///
/// Distinct from the read-only `Announcement` the home screen renders: that one
/// only ever sees published notices, and this one has to show drafts, who they
/// are for, and when they go out.
class AdminAnnouncement {
  const AdminAnnouncement({
    required this.id,
    required this.title,
    required this.body,
    required this.published,
    this.audience,
    this.priority,
    this.scheduledAt,
    this.expiresAt,
    this.publishedAt,
    this.createdByName,
    this.targetDepartmentName,
  });

  final int id;
  final String title;
  final String body;
  final bool published;
  final String? audience;
  final int? priority;
  final String? scheduledAt;
  final String? expiresAt;
  final String? publishedAt;
  final String? createdByName;
  final String? targetDepartmentName;

  /// Published announcements cannot be edited — "Cannot edit a published
  /// announcement" — so the action is hidden rather than offered.
  bool get isEditable => !published;

  factory AdminAnnouncement.fromJson(Map<String, dynamic> json) =>
      AdminAnnouncement(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        // The response exposes it either as a flag or as the timestamp; either
        // one being set means it has gone out.
        published: json['published'] as bool? ?? json['publishedAt'] != null,
        audience: json['audience'] as String?,
        priority: (json['priority'] as num?)?.toInt(),
        scheduledAt: json['scheduledAt'] as String?,
        expiresAt: json['expiresAt'] as String?,
        publishedAt: json['publishedAt'] as String?,
        createdByName: json['createdByName'] as String?,
        targetDepartmentName: json['targetDepartmentName'] as String?,
      );
}

/// POST and PUT /announcements
///
/// **`expiresAt`, `scheduledAt` and `notifyAll` are always sent.**
/// `AnnouncementServiceImpl.update` assigns all three unconditionally, so
/// leaving one out clears it — an edit that only fixed a typo would silently
/// drop the expiry date and un-schedule the notice.
class AnnouncementRequest {
  const AnnouncementRequest({
    required this.title,
    required this.body,
    this.audience,
    this.targetDepartmentId,
    this.priority,
    this.scheduledAt,
    this.expiresAt,
    this.notifyAll = false,
  });

  final String title;
  final String body;
  final String? audience;
  final int? targetDepartmentId;
  final int? priority;

  /// `LocalDateTime` on the wire — a wall clock with no zone.
  final String? scheduledAt;
  final String? expiresAt;

  final bool notifyAll;

  factory AnnouncementRequest.from(AdminAnnouncement announcement) =>
      AnnouncementRequest(
        title: announcement.title,
        body: announcement.body,
        audience: announcement.audience,
        priority: announcement.priority,
        scheduledAt: announcement.scheduledAt,
        expiresAt: announcement.expiresAt,
      );

  Map<String, dynamic> toJson() => {
        'title': title.trim(),
        'body': body.trim(),
        if (audience != null) 'audience': audience,
        if (targetDepartmentId != null)
          'targetDepartmentId': targetDepartmentId,
        if (priority != null) 'priority': priority,
        // Unconditional: see the class comment.
        'scheduledAt': scheduledAt,
        'expiresAt': expiresAt,
        'notifyAll': notifyAll,
      };
}

/// A service-desk category.
class ServiceCategory {
  const ServiceCategory({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.active,
    this.description,
  });

  final int id;
  final String name;
  final int sortOrder;
  final bool active;
  final String? description;

  factory ServiceCategory.fromJson(Map<String, dynamic> json) =>
      ServiceCategory(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
        active: json['active'] as bool? ?? true,
        description: json['description'] as String?,
      );
}

/// POST and PUT /service-categories
///
/// `sortOrder` is a primitive `int` server-side, so it always has a value —
/// sending it absent would land as 0 and quietly move the category to the top.
class ServiceCategoryRequest {
  const ServiceCategoryRequest({
    required this.name,
    required this.sortOrder,
    this.description,
  });

  final String name;
  final int sortOrder;
  final String? description;

  Map<String, dynamic> toJson() {
    final trimmedDescription = description?.trim();
    return {
      'name': name.trim(),
      'sortOrder': sortOrder,
      if (trimmedDescription != null && trimmedDescription.isNotEmpty)
        'description': trimmedDescription,
    };
  }
}

/// A role the company defined for itself.
class CustomRole {
  const CustomRole({
    required this.id,
    required this.name,
    required this.active,
    required this.systemRole,
    this.description,
  });

  final int id;
  final String name;
  final bool active;

  /// Built in rather than defined by this company. Shown, never edited: the
  /// screen offers no action on one, because changing what a system role means
  /// would change it for everybody.
  final bool systemRole;

  final String? description;

  factory CustomRole.fromJson(Map<String, dynamic> json) => CustomRole(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        active: json['active'] as bool? ?? true,
        systemRole: json['systemRole'] as bool? ?? false,
        description: json['description'] as String?,
      );
}

/// POST and PUT /custom-roles
class CustomRoleRequest {
  const CustomRoleRequest({required this.name, this.description});

  final String name;
  final String? description;

  Map<String, dynamic> toJson() {
    final trimmedDescription = description?.trim();
    return {
      'name': name.trim(),
      if (trimmedDescription != null && trimmedDescription.isNotEmpty)
        'description': trimmedDescription,
    };
  }
}

/// One permission the company can grant, as `GET /permissions` returns it.
class PermissionOption {
  const PermissionOption({
    required this.code,
    required this.name,
    this.module,
    this.description,
  });

  final String code;
  final String name;
  final String? module;
  final String? description;

  /// What to group it under. The backend supplies a module for most codes;
  /// anything without one is collected together rather than dropped.
  String get group => module?.trim().isNotEmpty == true ? module!.trim() : 'Other';

  factory PermissionOption.fromJson(Map<String, dynamic> json) =>
      PermissionOption(
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? json['code'] as String? ?? '',
        module: json['module'] as String?,
        description: json['description'] as String?,
      );
}
