/// Workflow templates — the ordered stages a service request moves through.
abstract final class WorkflowPermissions {
  static const view = 'WORKFLOW_VIEW';
  static const create = 'WORKFLOW_CREATE';
  static const update = 'WORKFLOW_UPDATE';
  static const delete = 'WORKFLOW_DELETE';
}

/// One template and the stages it runs.
class WorkflowTemplate {
  const WorkflowTemplate({
    required this.id,
    required this.name,
    required this.version,
    required this.active,
    this.description,
    this.stages = const [],
  });

  final int id;
  final String name;

  /// Bumped by the backend on every edit, to the template or to any of its
  /// stages. Shown because it is the only way to tell two otherwise identical
  /// templates apart after a change.
  final int version;

  final bool active;
  final String? description;
  final List<WorkflowStage> stages;

  /// How long the whole thing takes, when every stage says. Null when any
  /// stage leaves it unset — a partial total would read as the real one.
  int? get totalDays {
    if (stages.isEmpty) return null;
    var total = 0;
    for (final stage in stages) {
      final days = stage.estimatedDays;
      if (days == null) return null;
      total += days;
    }
    return total;
  }

  factory WorkflowTemplate.fromJson(Map<String, dynamic> json) =>
      WorkflowTemplate(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        version: (json['version'] as num?)?.toInt() ?? 1,
        active: json['active'] as bool? ?? true,
        description: json['description'] as String?,
        stages: [
          for (final stage in (json['stages'] as List? ?? const []))
            if (stage is Map<String, dynamic>) WorkflowStage.fromJson(stage),
        ]..sort((a, b) => a.stageOrder.compareTo(b.stageOrder)),
      );
}

/// One step in a template.
class WorkflowStage {
  const WorkflowStage({
    required this.id,
    required this.name,
    required this.stageOrder,
    required this.requiresApproval,
    required this.requiresPayment,
    this.description,
    this.estimatedDays,
    this.slaHours,
    this.assigneeRole,
    this.paymentPercent,
  });

  final int id;
  final String name;
  final int stageOrder;
  final bool requiresApproval;
  final bool requiresPayment;
  final String? description;
  final int? estimatedDays;
  final int? slaHours;
  final String? assigneeRole;
  final int? paymentPercent;

  factory WorkflowStage.fromJson(Map<String, dynamic> json) => WorkflowStage(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        stageOrder: (json['stageOrder'] as num?)?.toInt() ?? 1,
        requiresApproval: json['requiresApproval'] as bool? ?? false,
        requiresPayment: json['requiresPayment'] as bool? ?? false,
        description: json['description'] as String?,
        estimatedDays: (json['estimatedDays'] as num?)?.toInt(),
        slaHours: (json['slaHours'] as num?)?.toInt(),
        assigneeRole: json['assigneeRole'] as String?,
        paymentPercent: (json['paymentPercent'] as num?)?.toInt(),
      );
}

/// POST and PUT /workflows
///
/// `name` is `@NotBlank` and `@Size(max: 150)`; `description` is capped at 500.
/// The update sets the name unconditionally and guards the description, so a
/// cleared description is kept rather than emptied — which the form says.
class WorkflowTemplateRequest {
  const WorkflowTemplateRequest({required this.name, this.description});

  final String name;
  final String? description;

  Map<String, dynamic> toJson() {
    final trimmed = description?.trim();
    return {
      'name': name.trim(),
      if (trimmed != null && trimmed.isNotEmpty) 'description': trimmed,
    };
  }
}

/// POST and PUT /workflows/{templateId}/stages
///
/// The update assigns order, estimated days, SLA hours, both flags, the
/// assignee role and the payment percent **unconditionally** — only the
/// description is null-guarded. Everything is therefore sent on every save,
/// seeded from the stage being edited.
///
/// Validation to match: `name` `@NotBlank` and at most 100 characters,
/// `stageOrder` `@NotNull` and `@Min(1)`, and `estimatedDays`, `slaHours` and
/// `paymentPercent` each `@Min(1)` when given — so any of the three is either a
/// real number or absent, never zero.
///
/// Stage order is unique within a template: reusing one is refused with
/// "Stage order N is already taken".
class WorkflowStageRequest {
  const WorkflowStageRequest({
    required this.name,
    required this.stageOrder,
    required this.requiresApproval,
    required this.requiresPayment,
    this.description,
    this.estimatedDays,
    this.slaHours,
    this.assigneeRole,
    this.paymentPercent,
  });

  final String name;
  final int stageOrder;
  final bool requiresApproval;
  final bool requiresPayment;
  final String? description;
  final int? estimatedDays;
  final int? slaHours;
  final String? assigneeRole;
  final int? paymentPercent;

  factory WorkflowStageRequest.from(WorkflowStage stage) =>
      WorkflowStageRequest(
        name: stage.name,
        stageOrder: stage.stageOrder,
        requiresApproval: stage.requiresApproval,
        requiresPayment: stage.requiresPayment,
        description: stage.description,
        estimatedDays: stage.estimatedDays,
        slaHours: stage.slaHours,
        assigneeRole: stage.assigneeRole,
        paymentPercent: stage.paymentPercent,
      );

  Map<String, dynamic> toJson() {
    final trimmedDescription = description?.trim();
    final trimmedRole = assigneeRole?.trim();
    return {
      'name': name.trim(),
      'stageOrder': stageOrder,
      // Unconditional on the server: always sent, even when false or null.
      'requiresApproval': requiresApproval,
      'requiresPayment': requiresPayment,
      'estimatedDays': estimatedDays,
      'slaHours': slaHours,
      'assigneeRole':
          (trimmedRole == null || trimmedRole.isEmpty) ? null : trimmedRole,
      // Only meaningful when payment is required, and @Min(1) besides.
      'paymentPercent': requiresPayment ? paymentPercent : null,
      if (trimmedDescription != null && trimmedDescription.isNotEmpty)
        'description': trimmedDescription,
    };
  }
}

/// What the assistant proposes for a stated goal.
///
/// Nothing is saved — the suggestion comes back for somebody to build from,
/// which is why the screen offers to create the template and then leaves the
/// stages to be added deliberately.
class WorkflowSuggestion {
  const WorkflowSuggestion({
    required this.name,
    required this.stages,
    this.suggestion,
  });

  final String name;
  final List<SuggestedStage> stages;

  /// A sentence of reasoning, when the model offers one.
  final String? suggestion;

  factory WorkflowSuggestion.fromJson(Map<String, dynamic> json) =>
      WorkflowSuggestion(
        name: json['name'] as String? ?? '',
        suggestion: json['suggestion'] as String?,
        stages: [
          for (final stage in (json['stages'] as List? ?? const []))
            if (stage is Map<String, dynamic>) SuggestedStage.fromJson(stage),
        ],
      );
}

class SuggestedStage {
  const SuggestedStage({
    required this.name,
    required this.needsApproval,
    this.purpose,
  });

  final String name;
  final bool needsApproval;
  final String? purpose;

  factory SuggestedStage.fromJson(Map<String, dynamic> json) => SuggestedStage(
        name: json['name'] as String? ?? '',
        needsApproval: json['needsApproval'] as bool? ?? false,
        purpose: json['purpose'] as String?,
      );
}
