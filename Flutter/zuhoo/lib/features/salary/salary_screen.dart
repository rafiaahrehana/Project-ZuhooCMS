import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/config_list.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import 'salary_models.dart';
import 'salary_repository.dart';
import 'salary_sheets.dart';

/// What people are paid, what they owe, and the pieces pay is built from.
///
/// Three tabs because they are three different questions about the same money,
/// asked by the same person on the same day: who is on what, who owes what, and
/// what the line items are called.
class SalaryScreen extends ConsumerWidget {
  const SalaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final permissions = ref.watch(permissionControllerProvider);

    if (!permissions.loaded && permissions.codes.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Pay')),
        body: const Loader(),
      );
    }

    if (!permissions.hasAny(const [
      SalaryPermissions.view,
      SalaryPermissions.create,
    ])) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Pay')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Not available to you',
          message:
              'Salary structures need the salary permissions. Your own payslips '
              'are on the Payslips screen.',
        ),
      );
    }

    final canWrite = permissions.has(SalaryPermissions.create);

    final tabs = <({String label, Widget view, VoidCallback? create})>[
      (
        label: 'Structures',
        view: const _StructuresTab(),
        create: canWrite ? () => showStructureSheet(context) : null,
      ),
      (
        label: 'Loans',
        view: const _LoansTab(),
        create: canWrite ? () => showLoanSheet(context) : null,
      ),
      (
        label: 'Components',
        view: const _ComponentsTab(),
        create: canWrite ? () => showComponentSheet(context) : null,
      ),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Builder(
        builder: (context) {
          final tabController = DefaultTabController.of(context);
          return AnimatedBuilder(
            animation: tabController,
            builder: (context, _) {
              final create = tabs[tabController.index].create;
              return Scaffold(
                backgroundColor: bos.bgPage,
                appBar: AppBar(
                  title: const Text('Pay'),
                  bottom: TabBar(
                    tabs: [for (final tab in tabs) Tab(text: tab.label)],
                  ),
                ),
                floatingActionButton: create == null
                    ? null
                    : FloatingActionButton.extended(
                        onPressed: create,
                        backgroundColor: bos.brand,
                        foregroundColor: Colors.white,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('New'),
                      ),
                body: TabBarView(children: [for (final tab in tabs) tab.view]),
              );
            },
          );
        },
      ),
    );
  }
}

// ── Structures ────────────────────────────────────────────────

class _StructuresTab extends ConsumerStatefulWidget {
  const _StructuresTab();

  @override
  ConsumerState<_StructuresTab> createState() => _StructuresTabState();
}

class _StructuresTabState extends ConsumerState<_StructuresTab> {
  int? _busyId;

  Future<void> _delete(SalaryStructure row) async {
    final confirmed = await confirmAction(
      context,
      title: 'Remove this pay structure?',
      message: row.isCurrent
          ? '${row.employeeName ?? 'This employee'} would have no pay on file, '
              'and the monthly run would skip them until a new one is set.'
          : 'This is a superseded record. Removing it loses the history of '
              'what was paid, but not the payslips themselves.',
      action: 'Remove',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyId = row.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(salaryRepositoryProvider).deleteStructure(row.id);
      ref.read(salaryStructuresProvider.notifier).remove(row.id);
      ref.invalidate(structureHistoryProvider(row.employeeId));
      messenger.showSnackBar(const SnackBar(content: Text('Removed.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not remove that.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(permissionControllerProvider);
    final canWrite = permissions.has(SalaryPermissions.create);
    final canDelete = permissions.has(SalaryPermissions.delete);

    return ConfigList<SalaryStructure>(
      async: ref.watch(salaryStructuresProvider),
      onRefresh: ref.read(salaryStructuresProvider.notifier).refresh,
      emptyIcon: Icons.badge_outlined,
      emptyTitle: 'Nobody has pay on file',
      emptyMessage:
          'The monthly run builds a payslip for everybody who has a salary '
          'structure, and silently skips anybody who does not.',
      errorMessage: 'Could not load the pay structures.',
      itemBuilder: (context, row) => ConfigRow(
        title: row.employeeName ?? 'Employee ${row.employeeId}',
        // A superseded structure is drawn muted, because it is history rather
        // than something in force.
        active: row.isCurrent,
        inactiveLabel: 'Superseded',
        subtitle: [
          '${Fmt.money(row.grossSalary)} gross',
          '${Fmt.money(row.basicSalary)} basic',
          if (row.effectiveFrom != null) 'from ${Fmt.date(row.effectiveFrom)}',
        ].join(' · '),
        trailingLabel: row.addsUp ? null : 'figures disagree',
        busy: _busyId == row.id,
        // Only the current structure is editable — the backend refuses the
        // rest outright, so offering it would be a button that always fails.
        onEdit: canWrite && row.isCurrent
            ? () => showStructureSheet(context, existing: row)
            : null,
        actions: [
          RowAction(
            label: 'History',
            onSelected: () => StructureHistoryScreen.open(
              context,
              employeeId: row.employeeId,
              name: row.employeeName ?? 'Employee ${row.employeeId}',
            ),
          ),
          if (canWrite)
            RowAction(
              label: 'Supersede with new pay',
              onSelected: () => showStructureSheet(
                context,
                employeeId: row.employeeId,
                employeeName: row.employeeName,
              ),
            ),
          if (canDelete)
            RowAction(
              label: 'Remove',
              destructive: true,
              onSelected: () => _delete(row),
            ),
        ],
      ),
    );
  }
}

/// Every structure one person has had, newest first.
class StructureHistoryScreen extends ConsumerWidget {
  const StructureHistoryScreen({
    super.key,
    required this.employeeId,
    required this.name,
  });

  final int employeeId;
  final String name;

  static void open(
    BuildContext context, {
    required int employeeId,
    required String name,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            StructureHistoryScreen(employeeId: employeeId, name: name),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: Text(name)),
      body: ConfigList<SalaryStructure>(
        async: ref.watch(structureHistoryProvider(employeeId)),
        onRefresh: () async =>
            ref.invalidate(structureHistoryProvider(employeeId)),
        emptyIcon: Icons.history_rounded,
        emptyTitle: 'No pay on file',
        emptyMessage:
            '$name has never had a salary structure, so payroll has nothing to '
            'work from.',
        errorMessage: 'Could not load that history.',
        itemBuilder: (context, row) => _StructureCard(structure: row),
      ),
    );
  }
}

class _StructureCard extends StatelessWidget {
  const _StructureCard({required this.structure});

  final SalaryStructure structure;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    structure.effectiveTo == null
                        ? 'From ${Fmt.date(structure.effectiveFrom)}'
                        : '${Fmt.date(structure.effectiveFrom)} — '
                            '${Fmt.date(structure.effectiveTo)}',
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (structure.isCurrent)
                  const StatusChip('ACTIVE', label: 'In force', dense: true),
              ],
            ),
            const SizedBox(height: 10),
            _Line('Gross', structure.grossSalary, bold: true),
            _Line('Basic', structure.basicSalary),
            if (structure.allowances > 0)
              _Line('Allowances', structure.allowances),
            if (structure.deductions > 0)
              _Line('Deductions', -structure.deductions),
            if (structure.netSalary != null) ...[
              const Divider(height: 18),
              _Line('Net', structure.netSalary!, bold: true),
            ],
            if (!structure.addsUp) ...[
              const SizedBox(height: 8),
              Text(
                structure.unallocated > 0
                    ? '${Fmt.money(structure.unallocated)} of gross is not '
                        'allocated.'
                    : 'Basic and allowances exceed gross by '
                        '${Fmt.money(-structure.unallocated)}.',
                style: TextStyle(color: bos.warning, fontSize: 11.5),
              ),
            ],
            if (structure.notes != null && structure.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                structure.notes!,
                style: TextStyle(color: bos.muted, fontSize: 12, height: 1.45),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.amount, {this.bold = false});

  final String label;
  final double amount;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: bos.muted, fontSize: 12.5),
            ),
          ),
          Text(
            Fmt.money(amount),
            style: TextStyle(
              color: bos.text,
              fontSize: 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Loans ─────────────────────────────────────────────────────

class _LoansTab extends ConsumerStatefulWidget {
  const _LoansTab();

  @override
  ConsumerState<_LoansTab> createState() => _LoansTabState();
}

class _LoansTabState extends ConsumerState<_LoansTab> {
  int? _busyId;

  Future<void> _cancel(LoanAdvance loan) async {
    final confirmed = await confirmAction(
      context,
      title: 'Stop recovering this?',
      message: loan.remainingBalance > 0
          ? '${Fmt.money(loan.remainingBalance)} is still outstanding. '
              'Cancelling stops payroll taking any more of it — it does not '
              'write the balance off or claim it back.'
          : 'Nothing is outstanding, so this only closes the record.',
      action: 'Stop it',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyId = loan.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated =
          await ref.read(salaryRepositoryProvider).cancelLoan(loan.id);
      ref.read(loansProvider.notifier).apply(updated);
      messenger.showSnackBar(const SnackBar(content: Text('Stopped.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not stop that.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canWrite =
        ref.watch(permissionControllerProvider).has(SalaryPermissions.create);

    return ConfigList<LoanAdvance>(
      async: ref.watch(loansProvider),
      onRefresh: ref.read(loansProvider.notifier).refresh,
      emptyIcon: Icons.account_balance_wallet_outlined,
      emptyTitle: 'Nothing outstanding',
      emptyMessage:
          'Loans and advances are recovered from payroll in instalments. '
          'Recording one starts that from the next run.',
      errorMessage: 'Could not load the loans.',
      itemBuilder: (context, loan) => _LoanCard(
        loan: loan,
        busy: _busyId == loan.id,
        onCancel: canWrite && loan.isActive ? () => _cancel(loan) : null,
      ),
    );
  }
}

class _LoanCard extends ConsumerWidget {
  const _LoanCard({required this.loan, required this.busy, this.onCancel});

  final LoanAdvance loan;
  final bool busy;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final repaid = loan.repaidShare;
    final months = loan.monthsRemaining;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loan.employeeName ?? 'Employee ${loan.employeeId}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          Fmt.label(loan.type),
                          '${Fmt.money(loan.principalAmount)} at '
                              '${Fmt.money(loan.monthlyInstallment)} a month',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: bos.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusChip(loan.status, dense: true),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'history') {
                        RepaymentsScreen.open(context, loan: loan);
                      } else {
                        onCancel?.call();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'history',
                        child: Text('Repayments'),
                      ),
                      if (onCancel != null)
                        PopupMenuItem(
                          value: 'cancel',
                          child: Text(
                            'Stop recovering',
                            style: TextStyle(color: bos.danger),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            if (repaid != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: repaid,
                  minHeight: 5,
                  backgroundColor: bos.borderLight,
                  color: bos.brand,
                ),
              ),
              const SizedBox(height: 6),
            ],
            Text(
              [
                '${Fmt.money(loan.remainingBalance)} left',
                if (months != null)
                  months == 1 ? '1 month to go' : '$months months to go',
                if (loan.disbursedDate != null)
                  'since ${Fmt.date(loan.disbursedDate)}',
              ].join(' · '),
              style: TextStyle(color: bos.muted, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// What payroll has actually recovered, month by month.
class RepaymentsScreen extends ConsumerWidget {
  const RepaymentsScreen({super.key, required this.loan});

  final LoanAdvance loan;

  static void open(BuildContext context, {required LoanAdvance loan}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => RepaymentsScreen(loan: loan)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(
        title: Text(loan.employeeName ?? 'Repayments'),
      ),
      body: ConfigList<LoanRepayment>(
        async: ref.watch(repaymentsProvider(loan.id)),
        onRefresh: () async => ref.invalidate(repaymentsProvider(loan.id)),
        emptyIcon: Icons.history_rounded,
        emptyTitle: 'Nothing recovered yet',
        emptyMessage:
            'The first instalment comes out of the next payroll run that '
            'includes this employee.',
        errorMessage: 'Could not load the repayments.',
        itemBuilder: (context, repayment) => ConfigRow(
          title: repayment.payMonth == null || repayment.payYear == null
              ? Fmt.date(repayment.paidDate)
              : Fmt.monthYear(repayment.payMonth!, repayment.payYear!),
          active: true,
          subtitle: repayment.balanceAfter == null
              ? null
              : '${Fmt.money(repayment.balanceAfter)} left afterwards',
          trailingLabel: Fmt.money(repayment.amount),
        ),
      ),
    );
  }
}

// ── Component catalogue ───────────────────────────────────────

class _ComponentsTab extends ConsumerWidget {
  const _ComponentsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canWrite =
        ref.watch(permissionControllerProvider).has(SalaryPermissions.create);

    return ConfigList<SalaryComponent>(
      async: ref.watch(salaryComponentsProvider),
      onRefresh: ref.read(salaryComponentsProvider.notifier).refresh,
      emptyIcon: Icons.tune_rounded,
      emptyTitle: 'No components yet',
      emptyMessage:
          'Components are the named lines a payslip is built from beyond the '
          'standard allowances — a shift bonus, a union levy, an employer '
          'contribution.',
      errorMessage: 'Could not load the components.',
      itemBuilder: (context, row) => ConfigRow(
        title: row.name,
        active: row.active,
        inactiveLabel: 'Not in use',
        subtitle: [
          Fmt.label(row.type),
          row.calculationType == 'FIXED' ? 'fixed amount' : 'percentage',
          if (!row.taxable) 'not taxable',
        ].join(' · '),
        onEdit:
            canWrite ? () => showComponentSheet(context, existing: row) : null,
      ),
    );
  }
}
