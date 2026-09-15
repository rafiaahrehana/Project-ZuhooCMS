/// The workflow behind a request: its tasks, its stages and the quotation.
///
/// Its own file rather than more of `request_models.dart`, which is already
/// long and is about the request as a client sees it. Everything here is
/// staff-side — the machinery that moves a request, not the request itself.
library;

abstract final class TaskStatus {
  static const pending = 'PENDING';
  static const inProgress = 'IN_PROGRESS';
  static const completed = 'COMPLETED';
  static const blocked = 'BLOCKED';
  static const cancelled = 'CANCELLED';

  static const all = [pending, inProgress, completed, blocked, cancelled];

  /// Nothing further happens to a task in one of these.
  static const settled = {completed, cancelled};

  static String label(String status) => switch (status) {
        pending => 'Not started',
        inProgress => 'In progress',
        completed => 'Done',
        blocked => 'Blocked',
        cancelled => 'Cancelled',
        _ => status,
      };
}

abstract final class QuotationStatus {
  static const pending = 'PENDING';
  static const accepted = 'ACCEPTED';
  static const rejected = 'REJECTED';
  static const expired = 'EXPIRED';

  static String label(String status) => switch (status) {
        pending => 'Awaiting a decision',
        accepted => 'Accepted',
        rejected => 'Rejected',
        expired => 'Expired',
        _ => status,
      };
}

/// A piece of work under a request. Mirrors `TaskResponse`.
class RequestTask {
  const RequestTask({
    required this.id,
    required this.title,
    required this.status,
    required this.priority,
    this.description,
    this.dueDate,
    this.slaDeadline,
    this.completedAt,
    this.assignedEmployeeId,
    this.assignedEmployeeName,
    this.assignedEmployeeRole,
    this.estimatedHours,
    this.createdByName,
    this.workflowStageId,
    this.workflowStageName,
    this.createdAt,
  });

  final int id;
  final String title;
  final String status;
  final String priority;
  final String? description;

  /// A plain date, not a moment — the backend field was changed from
  /// `LocalDateTime` to `LocalDate` and the comment recording that is still in
  /// the DTO. [slaDeadline] beside it really is a moment.
  final String? dueDate;
  final String? slaDeadline;
  final String? completedAt;
  final int? assignedEmployeeId;
  final String? assignedEmployeeName;
  final String? assignedEmployeeRole;
  final double? estimatedHours;
  final String? createdByName;
  final int? workflowStageId;
  final String? workflowStageName;
  final String? createdAt;

  bool get isSettled => TaskStatus.settled.contains(status);

  factory RequestTask.fromJson(Map<String, dynamic> json) => RequestTask(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        status: json['status'] as String? ?? TaskStatus.pending,
        priority: json['priority'] as String? ?? 'NORMAL',
        description: json['description'] as String?,
        dueDate: json['dueDate'] as String?,
        slaDeadline: json['slaDeadline'] as String?,
        completedAt: json['completedAt'] as String?,
        assignedEmployeeId: (json['assignedEmployeeId'] as num?)?.toInt(),
        assignedEmployeeName: json['assignedEmployeeName'] as String?,
        assignedEmployeeRole: json['assignedEmployeeRole'] as String?,
        estimatedHours: (json['estimatedHours'] as num?)?.toDouble(),
        createdByName: json['createdByName'] as String?,
        workflowStageId: (json['workflowStageId'] as num?)?.toInt(),
        workflowStageName: json['workflowStageName'] as String?,
        createdAt: json['createdAt'] as String?,
      );
}

/// Creating or changing a task.
///
/// An unusually well-behaved endpoint: `TaskServiceImpl.updateTask` guards
/// every field with a null check, so a partial payload really does patch
/// rather than wipe. That is the exception in this backend rather than the
/// rule, and it is why this request model may omit keys freely.
///
/// One thing it cannot do is unassign. `assignedEmployeeId: null` is read as
/// "leave it alone", so there is no way to take a task off somebody — moving
/// it to another person is the only option the sheet offers.
class TaskRequest {
  const TaskRequest({
    this.title,
    this.description,
    this.status,
    this.priority,
    this.dueDate,
    this.assignedEmployeeId,
    this.estimatedHours,
    this.workflowStageId,
  });

  final String? title;
  final String? description;
  final String? status;
  final String? priority;
  final String? dueDate;
  final int? assignedEmployeeId;
  final double? estimatedHours;

  /// Only honoured on create. `UpdateTaskRequest` has no such field, so a task
  /// cannot be moved between stages after the fact.
  final int? workflowStageId;

  Map<String, dynamic> toJson() => {
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (status != null) 'status': status,
        if (priority != null) 'priority': priority,
        if (dueDate != null) 'dueDate': dueDate,
        if (assignedEmployeeId != null) 'assignedEmployeeId': assignedEmployeeId,
        if (estimatedHours != null) 'estimatedHours': estimatedHours,
        if (workflowStageId != null) 'workflowStageId': workflowStageId,
      };
}

/// One step of the workflow a request is walking through.
class StageStep {
  const StageStep({
    required this.stageId,
    required this.name,
    required this.stageOrder,
    required this.completed,
    required this.current,
    this.slaHours,
    this.requiresApproval = false,
    this.approvalStatus,
    this.requiresPayment = false,
    this.paymentPercent,
  });

  final int stageId;
  final String name;
  final int stageOrder;
  final bool completed;
  final bool current;
  final int? slaHours;
  final bool requiresApproval;

  /// Only set on a stage that needs signing off, and only once somebody has
  /// asked. Advancing into such a stage raises the approval request as a side
  /// effect and then refuses, so the first attempt always fails by design —
  /// the screen says as much before you press it.
  final String? approvalStatus;
  final bool requiresPayment;
  final int? paymentPercent;

  factory StageStep.fromJson(Map<String, dynamic> json) => StageStep(
        stageId: (json['stageId'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        stageOrder: (json['stageOrder'] as num?)?.toInt() ?? 0,
        completed: json['completed'] as bool? ?? false,
        current: json['current'] as bool? ?? false,
        slaHours: (json['slaHours'] as num?)?.toInt(),
        requiresApproval: json['requiresApproval'] as bool? ?? false,
        approvalStatus: json['approvalStatus'] as String?,
        requiresPayment: json['requiresPayment'] as bool? ?? false,
        paymentPercent: (json['paymentPercent'] as num?)?.toInt(),
      );
}

class StageProgress {
  const StageProgress({
    required this.serviceRequestId,
    required this.currentStage,
    required this.totalStages,
    required this.stages,
  });

  final int serviceRequestId;

  /// A count of completed stages, not an index — the backend says so in its
  /// own comment. With three of five done this is 3, and the stage being
  /// worked on is `stages[3]`.
  final int currentStage;
  final int totalStages;
  final List<StageStep> stages;

  bool get finished => totalStages > 0 && currentStage >= totalStages;

  double get fraction => totalStages == 0 ? 0 : currentStage / totalStages;

  /// The stage being worked on now, or null once they are all done.
  StageStep? get inFlight {
    for (final stage in stages) {
      if (stage.current) return stage;
    }
    return currentStage < stages.length ? stages[currentStage] : null;
  }

  factory StageProgress.fromJson(Map<String, dynamic> json) => StageProgress(
        serviceRequestId: (json['serviceRequestId'] as num?)?.toInt() ?? 0,
        currentStage: (json['currentStage'] as num?)?.toInt() ?? 0,
        totalStages: (json['totalStages'] as num?)?.toInt() ?? 0,
        stages: (json['stages'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(StageStep.fromJson)
            .toList(growable: false),
      );
}

/// Quoting a price for a request.
///
/// Every field is written straight onto the record with no null guard except
/// currency, so an omitted amount, note or expiry is cleared, and the status
/// is forced back to PENDING. Re-quoting is a fresh quote rather than an edit,
/// and the sheet always sends the lot.
class QuotationRequest {
  const QuotationRequest({
    required this.amount,
    required this.currency,
    this.notes,
    this.validUntil,
  });

  final double amount;
  final String currency;
  final String? notes;

  /// A `LocalDateTime`, so a bare `yyyy-MM-dd` is refused. The sheet takes a
  /// date and pins it to the last minute of that day.
  final String? validUntil;

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'currency': currency,
        'notes': notes,
        'validUntil': validUntil,
      };
}
