import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../accounting/accounting_models.dart'
    show AccountingPermissions, JournalEntry;
import '../accounting/accounting_repository.dart';
import '../finance/finance_models.dart' show Expense, FinancePermissions;
import '../finance/finance_repository.dart' show ExpenseView, financeRepositoryProvider;
import '../leave/leave_models.dart'
    show LeavePermissions, LeaveRequest, LeaveStatus, ReviewLeaveRequest;
import '../leave/leave_repository.dart';
import '../payables/payables_models.dart'
    show BillStatus, PayablesPermissions, VendorBill;
import '../payables/payables_repository.dart';
import '../payroll/payroll_models.dart' show PayrollRun, RunStatus;
import '../payroll/payroll_repository.dart';
import '../payslips/payslip_models.dart' show PayrollPermissions;
import '../requests/request_models.dart' show RequestPermissions, StageApproval;
import '../requests/request_repository.dart';
import 'approval_models.dart';

/// Aggregates every "waiting on me" item this account can act on into one
/// list, reusing each module's own repository rather than adding a second
/// path to the same backend endpoints. A category that 403s (no permission)
/// or fails to load does not blank the whole inbox — the other categories
/// still render, and the failure is surfaced only if literally nothing came
/// back.
class ApprovalInboxController extends AsyncNotifier<List<ApprovalItem>> {
  @override
  Future<List<ApprovalItem>> build() => _load();

  Future<List<ApprovalItem>> _load() async {
    final perms = ref.read(permissionControllerProvider);
    final items = <ApprovalItem>[];
    Object? lastError;
    var anySucceeded = false;

    Future<void> run(Future<List<ApprovalItem>> Function() fetch) async {
      try {
        items.addAll(await fetch());
        anySucceeded = true;
      } catch (e) {
        lastError = e;
      }
    }

    if (perms.has(LeavePermissions.approve)) {
      await run(() async {
        final page = await ref
            .read(leaveRepositoryProvider)
            .allRequests(status: LeaveStatus.pending, size: 50);
        return page.content.map(_fromLeave).toList();
      });
    }

    if (perms.has(FinancePermissions.expenseApprove) ||
        perms.has(FinancePermissions.expenseReject)) {
      await run(() async {
        final page = await ref
            .read(financeRepositoryProvider)
            .expenses(ExpenseView.pending, size: 50);
        return page.content.map(_fromExpense).toList();
      });
    }

    if (perms.has(PayablesPermissions.billApprove)) {
      await run(() async {
        final page = await ref
            .read(payablesRepositoryProvider)
            .bills(status: BillStatus.draft, size: 50);
        return page.content.map(_fromBill).toList();
      });
    }

    if (perms.has(AccountingPermissions.entryApprove)) {
      await run(() async {
        final page =
            await ref.read(accountingRepositoryProvider).entries(size: 50);
        return page.content
            .where((e) => !e.approved && !e.reversed)
            .map(_fromJournalEntry)
            .toList();
      });
    }

    if (perms.has(PayrollPermissions.approve)) {
      await run(() async {
        final runs = await ref.read(payrollRepositoryProvider).runs();
        return runs
            .where((r) => r.status == RunStatus.pendingApproval)
            .map(_fromPayrollRun)
            .toList();
      });
    }

    if (perms.has(RequestPermissions.approve)) {
      await run(() async {
        final page = await ref
            .read(requestRepositoryProvider)
            .pendingApprovals(size: 50);
        return page.content
            .where((a) => a.isPending)
            .map(_fromStageApproval)
            .toList();
      });
    }

    if (!anySucceeded && lastError != null && items.isEmpty) {
      throw lastError!;
    }

    items.sort((a, b) => (b.date ?? '').compareTo(a.date ?? ''));
    return items;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  /// Approves or rejects one item, then drops it from the in-memory list on
  /// success — no full reload needed, and it can't be actioned twice while a
  /// refresh is still in flight.
  Future<void> decide(
    ApprovalItem item, {
    required bool approve,
    String? reason,
  }) async {
    if (!approve && !kindSupportsReject(item.kind)) {
      throw StateError('${item.kind.label} cannot be rejected from the inbox');
    }
    switch (item.kind) {
      case ApprovalKind.leave:
        await ref.read(leaveRepositoryProvider).review(
              item.rawId,
              approve
                  ? const ReviewLeaveRequest.approve()
                  : ReviewLeaveRequest.reject(reason ?? ''),
            );
      case ApprovalKind.expense:
        final repo = ref.read(financeRepositoryProvider);
        if (approve) {
          await repo.approve(item.rawId, reason ?? '');
        } else {
          await repo.reject(item.rawId, reason ?? '');
        }
      case ApprovalKind.vendorBill:
        await ref.read(payablesRepositoryProvider).approveBill(item.rawId);
      case ApprovalKind.journalEntry:
        await ref.read(accountingRepositoryProvider).approveEntry(item.rawId);
      case ApprovalKind.payrollRun:
        final repo = ref.read(payrollRepositoryProvider);
        if (approve) {
          await repo.approve(item.rawId);
        } else {
          await repo.reject(item.rawId, reason ?? '');
        }
      case ApprovalKind.serviceRequestStage:
        final repo = ref.read(requestRepositoryProvider);
        if (approve) {
          await repo.approve(item.rawId, notes: reason);
        } else {
          await repo.reject(item.rawId, reason ?? '');
        }
    }

    state = AsyncData([
      for (final i in state.value ?? const <ApprovalItem>[])
        if (i.listKey != item.listKey) i,
    ]);
  }
}

final approvalInboxProvider =
    AsyncNotifierProvider<ApprovalInboxController, List<ApprovalItem>>(
  ApprovalInboxController.new,
);

/// Whether this account holds at least one of the approve permissions the
/// inbox aggregates — used to decide whether to show the nav entry/badge at
/// all rather than opening it to an empty screen for everyone.
bool canSeeApprovalInbox(PermissionState perms) =>
    perms.has(LeavePermissions.approve) ||
    perms.has(FinancePermissions.expenseApprove) ||
    perms.has(FinancePermissions.expenseReject) ||
    perms.has(PayablesPermissions.billApprove) ||
    perms.has(AccountingPermissions.entryApprove) ||
    perms.has(PayrollPermissions.approve) ||
    perms.has(RequestPermissions.approve);

ApprovalItem _fromLeave(LeaveRequest r) => ApprovalItem(
      kind: ApprovalKind.leave,
      rawId: r.id,
      title: '${r.leaveType} leave',
      subtitle: '${r.startDate} – ${r.endDate} (${r.totalDays}d)',
      requestedBy: r.employeeName,
      date: r.createdAt,
      status: r.status,
      rejectRequiresReason: true,
    );

ApprovalItem _fromExpense(Expense e) => ApprovalItem(
      kind: ApprovalKind.expense,
      rawId: e.id,
      title: e.title?.trim().isNotEmpty == true ? e.title! : e.description,
      subtitle: e.category,
      requestedBy: e.submittedByName,
      date: e.submittedAt ?? e.createdAt,
      status: e.status,
      amount: e.amount,
      currency: e.currency,
      rejectRequiresReason: true,
    );

ApprovalItem _fromBill(VendorBill b) => ApprovalItem(
      kind: ApprovalKind.vendorBill,
      rawId: b.id,
      title: 'Bill ${b.billNumber}',
      subtitle: b.vendorName,
      date: b.billDate,
      status: b.status,
      amount: b.totalAmount,
    );

ApprovalItem _fromJournalEntry(JournalEntry e) => ApprovalItem(
      kind: ApprovalKind.journalEntry,
      rawId: e.id,
      title: 'Journal ${e.journalEntryNumber}',
      subtitle: e.description,
      requestedBy: e.createdBy,
      date: e.entryDate,
      status: e.approved ? 'APPROVED' : 'PENDING',
      amount: e.amount,
    );

ApprovalItem _fromPayrollRun(PayrollRun r) => ApprovalItem(
      kind: ApprovalKind.payrollRun,
      rawId: r.id,
      title: 'Payroll run ${r.runNumber}',
      subtitle: '${r.totalEmployees} employees',
      date: r.payPeriodStart,
      status: r.status,
      amount: r.totalNet,
      rejectRequiresReason: true,
    );

ApprovalItem _fromStageApproval(StageApproval a) => ApprovalItem(
      kind: ApprovalKind.serviceRequestStage,
      rawId: a.id,
      title: a.serviceRequestTitle?.trim().isNotEmpty == true
          ? a.serviceRequestTitle!
          : 'Request #${a.serviceRequestId}',
      subtitle: a.workflowStageName,
      requestedBy: a.requestedByName,
      date: a.createdAt,
      status: a.status,
      rejectRequiresReason: true,
    );
