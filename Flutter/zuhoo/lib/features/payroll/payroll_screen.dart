import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import '../../shared/widgets/stat_card.dart';
import '../payslips/payslip_models.dart' show PayrollPermissions, Payslip;
import 'payroll_models.dart';
import 'payroll_repository.dart';
import 'payroll_sheets.dart';

/// Running payroll for a month.
///
/// One screen rather than a tab bar, because payroll is a sequence, not a set
/// of parallel views: pick the month, see where it stands, generate the lines,
/// send it for approval, pay it. The month picker at the top drives everything
/// below it.
class PayrollScreen extends ConsumerWidget {
  const PayrollScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final permissions = ref.watch(permissionControllerProvider);

    if (!permissions.loaded && permissions.codes.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Payroll')),
        body: const Loader(),
      );
    }

    if (!permissions.hasAny(const [
      PayrollPermissions.view,
      PayrollPermissions.process,
      PayrollPermissions.approve,
    ])) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Payroll')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Not available to you',
          message:
              'Running payroll needs the payroll permissions. Your own payslips '
              'are on the Payslips screen.',
        ),
      );
    }

    final period = ref.watch(payrollPeriodProvider);
    final dashboard = ref.watch(payrollDashboardProvider);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(
        title: const Text('Payroll'),
        actions: [
          const _ExportMenu(),
          if (permissions.has(PayrollPermissions.process))
            IconButton(
              onPressed: () => showPayrollSettingsSheet(context),
              tooltip: 'How pay is worked out',
              icon: const Icon(Icons.tune_rounded),
            ),
        ],
      ),
      body: RefreshIndicator(
        color: bos.brand,
        backgroundColor: bos.bgCard,
        onRefresh: () async {
          ref.invalidate(payrollDashboardProvider);
          ref.invalidate(payrollLinesProvider);
          await ref.read(payrollRunsProvider.notifier).refresh();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _MonthPicker(period: period),
            const SizedBox(height: 16),
            dashboard.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Loader(),
              ),
              error: (error, _) => ErrorState(
                message: error is ApiException
                    ? error.message
                    : 'Could not load that month.',
                onRetry: () => ref.invalidate(payrollDashboardProvider),
              ),
              data: (data) => _Month(dashboard: data),
            ),
            const SizedBox(height: 20),
            const _RunSection(),
            const SizedBox(height: 20),
            const _LinesSection(),
          ],
        ),
      ),
    );
  }
}

/// The two files payroll produces: a bank disbursement list and the month's
/// salary sheet.
///
/// Both come back as bytes rather than JSON — one CSV, one PDF — so they are
/// written to a temporary file and handed to whatever on the device can open
/// them, the same way a payslip already is.
class _ExportMenu extends ConsumerStatefulWidget {
  const _ExportMenu();

  @override
  ConsumerState<_ExportMenu> createState() => _ExportMenuState();
}

class _ExportMenuState extends ConsumerState<_ExportMenu> {
  bool _busy = false;

  Future<void> _open(
    Future<String> Function(PayrollRepository repo, int month, int year) fetch,
    String failure,
  ) async {
    final period = ref.read(payrollPeriodProvider);
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await fetch(
        ref.read(payrollRepositoryProvider),
        period.month,
        period.year,
      );
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done && mounted) {
        // Almost always means nothing on the device handles that file type.
        messenger.showSnackBar(
          const SnackBar(
            content: Text('No app on this device can open that file.'),
          ),
        );
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failure)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return PopupMenuButton<String>(
      tooltip: 'Export',
      icon: const Icon(Icons.download_outlined),
      onSelected: (value) => value == 'sheet'
          ? _open(
              (repo, month, year) => repo.salarySheetPdf(month, year),
              'Could not produce that salary sheet.',
            )
          : _open(
              (repo, month, year) => repo.disbursementCsv(month, year),
              'Could not produce that disbursement file.',
            ),
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'sheet', child: Text('Salary sheet (PDF)')),
        PopupMenuItem(
          value: 'disbursement',
          child: Text('Bank disbursement (CSV)'),
        ),
      ],
    );
  }
}

/// Which month is in view. Steps a month at a time and refuses to run ahead of
/// the current one — payroll for a month that has not happened is not a thing.
class _MonthPicker extends ConsumerWidget {
  const _MonthPicker({required this.period});

  final ({int month, int year}) period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final now = DateTime.now();
    final atLatest =
        period.year == now.year && period.month == now.month;

    return AppCard(
      child: Row(
        children: [
          IconButton(
            onPressed: () => ref.read(payrollPeriodProvider.notifier).shift(-1),
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Previous month',
          ),
          Expanded(
            child: Center(
              child: Text(
                Fmt.monthYear(period.month, period.year),
                style: TextStyle(
                  color: bos.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: atLatest
                ? null
                : () => ref.read(payrollPeriodProvider.notifier).shift(1),
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Next month',
          ),
        ],
      ),
    );
  }
}

class _Month extends StatelessWidget {
  const _Month({required this.dashboard});

  final PayrollDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final paid = dashboard.paidShare;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'Net to pay',
                value: Fmt.money(dashboard.totalNet),
                icon: Icons.payments_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                label: 'On the run',
                value: '${dashboard.payrollCount}',
                suffix: 'of ${dashboard.totalEmployees}',
                icon: Icons.groups_outlined,
                // Somebody with no line will not be paid, which is the one
                // thing on this screen worth flagging before payday.
                tone: dashboard.missing > 0 ? bos.warning : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'Gross',
                value: Fmt.money(dashboard.totalGross),
                icon: Icons.trending_up_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                label: 'Deductions',
                value: Fmt.money(dashboard.totalDeductions),
                icon: Icons.trending_down_rounded,
              ),
            ),
          ],
        ),
        if (paid != null) ...[
          const SizedBox(height: 14),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${dashboard.employeesPaid} of ${dashboard.payrollCount} paid',
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (dashboard.nextPayDate != null)
                      Text(
                        'due ${Fmt.date(dashboard.nextPayDate)}',
                        style: TextStyle(color: bos.muted, fontSize: 12),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: paid,
                    minHeight: 6,
                    backgroundColor: bos.borderLight,
                    color: bos.brand,
                  ),
                ),
                if (dashboard.missing > 0) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 15, color: bos.warning),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          dashboard.missing == 1
                              ? '1 employee has no payroll line this month.'
                              : '${dashboard.missing} employees have no payroll '
                                  'line this month.',
                          style:
                              TextStyle(color: bos.warning, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
        if (dashboard.trend.length > 1) ...[
          const SizedBox(height: 14),
          _Trend(points: dashboard.trend),
        ],
      ],
    );
  }
}

/// Net paid over the last few months, as bars.
///
/// Deliberately not a line chart: the points are monthly totals, a handful of
/// them, and bars read correctly on a narrow screen where a line would be
/// mostly axis.
class _Trend extends StatelessWidget {
  const _Trend({required this.points});

  final List<PayrollTrendPoint> points;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final peak = points
        .map((p) => p.netPaid)
        .fold<double>(0, (a, b) => a > b ? a : b);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Net paid',
            style: TextStyle(
              color: bos.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 84,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final point in points) ...[
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          // A zero month still gets a sliver, so it reads as a
                          // month with nothing paid rather than as no month.
                          height: peak <= 0
                              ? 2
                              : (2 + (point.netPaid / peak) * 62),
                          decoration: BoxDecoration(
                            color: bos.brand.withValues(alpha: 0.75),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          Fmt.monthName(point.month).substring(0, 3),
                          style: TextStyle(color: bos.muted, fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The run for the month in view, and what can be done to it.
class _RunSection extends ConsumerWidget {
  const _RunSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final period = ref.watch(payrollPeriodProvider);
    final runs = ref.watch(payrollRunsProvider);
    final permissions = ref.watch(permissionControllerProvider);

    // The run for this period, picked out of the list rather than fetched
    // separately — the list is short and already loaded.
    PayrollRun? current;
    for (final run in runs.value ?? const <PayrollRun>[]) {
      if (run.payMonth == period.month && run.payYear == period.year) {
        current = run;
        break;
      }
    }

    if (runs.isLoading && runs.value == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Loader(),
      );
    }

    if (current == null) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader('The run', icon: Icons.play_circle_outline_rounded),
            const SizedBox(height: 10),
            Text(
              'No run has been opened for '
              '${Fmt.monthYear(period.month, period.year)}. Opening one groups '
              "everybody's payroll into a single batch that is approved and "
              'paid together.',
              style: TextStyle(color: bos.muted, fontSize: 13, height: 1.5),
            ),
            if (permissions.has(PayrollPermissions.process)) ...[
              const SizedBox(height: 14),
              LoadingButton(
                label: 'Open a run',
                loading: false,
                icon: Icons.add_rounded,
                onPressed: () => showOpenRunSheet(
                  context,
                  month: period.month,
                  year: period.year,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return _RunCard(run: current);
  }
}

class _RunCard extends ConsumerStatefulWidget {
  const _RunCard({required this.run});

  final PayrollRun run;

  @override
  ConsumerState<_RunCard> createState() => _RunCardState();
}

class _RunCardState extends ConsumerState<_RunCard> {
  bool _busy = false;

  Future<void> _act(
    Future<PayrollRun> Function(PayrollRepository repo) action,
    String success,
    String failure,
  ) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await action(ref.read(payrollRepositoryProvider));
      ref.read(payrollRunsProvider.notifier).apply(updated);
      // Totals and paid counts both move with the run.
      ref.invalidate(payrollDashboardProvider);
      ref.invalidate(payrollLinesProvider);
      messenger.showSnackBar(SnackBar(content: Text(success)));
    } on ApiException catch (e) {
      // "Cannot submit a PAID payroll run" and friends are worth showing as
      // written — they name the status that blocked it.
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failure)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final run = widget.run;
    final permissions = ref.watch(permissionControllerProvider);
    final canProcess = permissions.has(PayrollPermissions.process);
    final canApprove = permissions.has(PayrollPermissions.approve);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  run.runNumber,
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              StatusChip(run.status, dense: true),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              run.totalEmployees == 1
                  ? '1 employee'
                  : '${run.totalEmployees} employees',
              '${Fmt.money(run.totalNet)} net',
              if (run.paymentDate != null) 'paid ${Fmt.date(run.paymentDate)}',
            ].join(' · '),
            style: TextStyle(color: bos.muted, fontSize: 12.5),
          ),
          if (run.remarks != null && run.remarks!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              run.remarks!,
              style: TextStyle(color: bos.text, fontSize: 12.5, height: 1.45),
            ),
          ],
          if (run.status == RunStatus.rejected &&
              run.rejectionReason != null) ...[
            const SizedBox(height: 10),
            MessageBanner.error(run.rejectionReason!),
          ],
          if (!run.hasLines && !run.isSettled) ...[
            const SizedBox(height: 10),
            Text(
              'The run has no lines yet. Generate this month’s payroll '
              'below, then recalculate.',
              style: TextStyle(color: bos.muted, fontSize: 12, height: 1.45),
            ),
          ],
          const SizedBox(height: 14),
          if (_busy)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(6),
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canProcess && run.can(RunStatus.recalculateFrom))
                  _RunAction(
                    label: 'Recalculate',
                    icon: Icons.refresh_rounded,
                    onPressed: () => _act(
                      (repo) => repo.recalculate(run.id),
                      'Recalculated.',
                      'Could not recalculate that run.',
                    ),
                  ),
                if (canProcess && run.can(RunStatus.submitFrom) && run.hasLines)
                  _RunAction(
                    label: 'Send for approval',
                    icon: Icons.send_rounded,
                    onPressed: () => _act(
                      (repo) => repo.submit(run.id),
                      'Sent for approval.',
                      'Could not submit that run.',
                    ),
                  ),
                if (canApprove && run.can(RunStatus.approveFrom))
                  _RunAction(
                    label: 'Approve',
                    icon: Icons.check_rounded,
                    onPressed: () => _act(
                      (repo) => repo.approve(run.id),
                      'Approved.',
                      'Could not approve that run.',
                    ),
                  ),
                if (canApprove && run.can(RunStatus.rejectFrom))
                  _RunAction(
                    label: 'Reject',
                    icon: Icons.close_rounded,
                    destructive: true,
                    onPressed: () async {
                      final reason = await askForText(
                        context,
                        title: 'Reject ${run.runNumber}?',
                        message:
                            'It goes back to whoever prepared it, with your '
                            'reason attached.',
                        label: 'Reason',
                        action: 'Reject',
                        required: true,
                        destructive: true,
                      );
                      if (reason == null || !mounted) return;
                      await _act(
                        (repo) => repo.reject(run.id, reason),
                        'Rejected.',
                        'Could not reject that run.',
                      );
                    },
                  ),
                if (canApprove && run.can(RunStatus.payFrom))
                  _RunAction(
                    label: 'Pay everybody',
                    icon: Icons.account_balance_rounded,
                    onPressed: () => showPayRunSheet(context, run: run),
                  ),
                if (canProcess && run.can(RunStatus.cancelFrom))
                  _RunAction(
                    label: 'Cancel',
                    icon: Icons.block_rounded,
                    destructive: true,
                    onPressed: () async {
                      final confirmed = await confirmAction(
                        context,
                        title: 'Cancel ${run.runNumber}?',
                        message:
                            'The run is abandoned and cannot be reopened. The '
                            'payroll lines it holds stay where they are.',
                        action: 'Cancel the run',
                      );
                      if (!confirmed || !mounted) return;
                      await _act(
                        (repo) => repo.cancel(run.id),
                        'Run cancelled.',
                        'Could not cancel that run.',
                      );
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _RunAction extends StatelessWidget {
  const _RunAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: destructive ? bos.danger : bos.brand,
        side: BorderSide(
          color: (destructive ? bos.danger : bos.brand).withValues(alpha: 0.4),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
    );
  }
}

/// Everybody's lines for the month, and the two bulk operations that produce
/// and export them.
class _LinesSection extends ConsumerStatefulWidget {
  const _LinesSection();

  @override
  ConsumerState<_LinesSection> createState() => _LinesSectionState();
}

class _LinesSectionState extends ConsumerState<_LinesSection> {
  bool _generating = false;

  Future<void> _generate() async {
    final period = ref.read(payrollPeriodProvider);
    setState(() => _generating = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(payrollRepositoryProvider)
          .generate(period.month, period.year);
      ref.invalidate(payrollLinesProvider);
      ref.invalidate(payrollDashboardProvider);
      await ref.read(payrollRunsProvider.notifier).refresh();
      if (!mounted) return;
      // The people without a salary structure are the actionable part, so
      // they get a dialog rather than a snackbar that scrolls away.
      if (result.hasProblems) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => _GenerateResultDialog(result: result),
        );
      } else {
        messenger.showSnackBar(SnackBar(content: Text(result.summary)));
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not generate that payroll.')),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final lines = ref.watch(payrollLinesProvider);
    final permissions = ref.watch(permissionControllerProvider);
    final canProcess = permissions.has(PayrollPermissions.process);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'This month',
          icon: Icons.receipt_long_outlined,
          trailing: canProcess
              ? TextButton.icon(
                  onPressed: _generating ? null : _generate,
                  icon: _generating
                      ? const SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_mode_rounded, size: 18),
                  label: const Text('Generate'),
                )
              : null,
        ),
        const SizedBox(height: 10),
        lines.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Loader(),
          ),
          error: (error, _) => ErrorState(
            message: error is ApiException
                ? error.message
                : 'Could not load this month’s payroll.',
            onRetry: () => ref.invalidate(payrollLinesProvider),
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return const EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Nothing generated yet',
                message:
                    'Generate builds a draft line for everybody who has a '
                    'salary structure. Anyone without one is named so you can '
                    'fix it.',
              );
            }
            return Column(
              children: [
                for (final row in rows) _LineRow(line: row),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line});

  final Payslip line;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.employeeName,
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
                      '${Fmt.money(line.basicSalary)} basic',
                      if (line.absentDays != null && line.absentDays! > 0)
                        '${line.absentDays} absent',
                    ].join(' · '),
                    style: TextStyle(color: bos.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  Fmt.money(line.netSalary),
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                StatusChip(line.status, dense: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Who was skipped, and why it matters.
class _GenerateResultDialog extends StatelessWidget {
  const _GenerateResultDialog({required this.result});

  final BulkPayrollResult result;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return AlertDialog(
      title: const Text('Generated, with gaps'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.summary,
              style: TextStyle(color: bos.text, fontSize: 13.5, height: 1.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No salary structure — these people will not be paid this month '
              'until one is set up for them:',
              style: TextStyle(color: bos.warning, fontSize: 12.5, height: 1.5),
            ),
            const SizedBox(height: 8),
            for (final name in result.noSalaryStructure)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '· $name',
                  style: TextStyle(color: bos.text, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Got it'),
        ),
      ],
    );
  }
}
