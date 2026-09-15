/// A single kind of thing that can wait on someone's approval. Each maps to
/// one existing module's own approve/reject call — this screen never
/// invents a workflow, it just aggregates the ones that already exist so a
/// reviewer isn't hunting across seven tabs for what needs their attention.
enum ApprovalKind {
  leave,
  expense,
  vendorBill,
  journalEntry,
  payrollRun,
  serviceRequestStage,
}

/// Vendor bills and journal entries have no "reject" endpoint on the
/// backend — only approve (plus cancel/delete, which live in their own
/// screens under a different permission). The inbox offers approve only for
/// these two kinds rather than inventing a decision the API can't record.
bool kindSupportsReject(ApprovalKind kind) => switch (kind) {
      ApprovalKind.vendorBill || ApprovalKind.journalEntry => false,
      ApprovalKind.leave ||
      ApprovalKind.expense ||
      ApprovalKind.payrollRun ||
      ApprovalKind.serviceRequestStage =>
        true,
    };

extension ApprovalKindLabel on ApprovalKind {
  String get label => switch (this) {
        ApprovalKind.leave => 'Leave request',
        ApprovalKind.expense => 'Expense claim',
        ApprovalKind.vendorBill => 'Vendor bill',
        ApprovalKind.journalEntry => 'Journal entry',
        ApprovalKind.payrollRun => 'Payroll run',
        ApprovalKind.serviceRequestStage => 'Request approval',
      };
}

/// One row in the inbox. Deliberately thin — enough to render the list and
/// the confirm sheet, with [rawId] and [kind] as the only things a caller
/// needs to route the decision back to the owning repository.
class ApprovalItem {
  const ApprovalItem({
    required this.kind,
    required this.rawId,
    required this.title,
    required this.status,
    this.subtitle,
    this.requestedBy,
    this.date,
    this.amount,
    this.currency,
    this.rejectRequiresReason = false,
  });

  final ApprovalKind kind;

  /// The id to send back to the owning module's own approve/reject call —
  /// never shown, never reused as this screen's own identity (two different
  /// kinds can legitimately share the same underlying integer).
  final int rawId;

  final String title;
  final String status;
  final String? subtitle;
  final String? requestedBy;
  final String? date;
  final double? amount;
  final String? currency;

  /// Leave and the service-request stage approval both refuse a rejection
  /// with no reason; the others accept an optional note. Read by the confirm
  /// sheet to decide whether the reason field is required.
  final bool rejectRequiresReason;

  String get listKey => '${kind.name}-$rawId';
}
