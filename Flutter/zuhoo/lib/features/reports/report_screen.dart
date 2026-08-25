import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/date_field.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/stat_card.dart';
import '../accounting/accounting_models.dart'
    show Account, AccountingPermissions;
import '../accounting/accounting_repository.dart' show accountsProvider;
import 'report_models.dart';
import 'report_repository.dart';

/// Pick a report, pick a period, read the answer.
///
/// Six reports over one screen rather than six screens, because they differ
/// only in what they ask for and what they show — and because somebody
/// checking the books usually wants two of them side by side.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  FinancialReport _report = FinancialReport.profitLoss;
  late ReportQuery _query = defaultQuery(_report);

  /// Null until a report has actually been asked for. Changing the period
  /// should not silently re-run something expensive, so running is explicit.
  ReportQuery? _running;

  void _pick(FinancialReport report) {
    setState(() {
      _report = report;
      // The period carries over — somebody comparing two reports over the same
      // dates should not have to type them twice.
      _query = ReportQuery(
        report: report,
        start: _query.start,
        end: _query.end,
        accountId: _query.accountId,
      );
      _running = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final permissions = ref.watch(permissionControllerProvider);

    if (!permissions.loaded && permissions.codes.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Reports')),
        body: const Loader(),
      );
    }

    // Every report reads the ledger, so that is the gate on all of them.
    if (!permissions.has(AccountingPermissions.ledgerView)) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Reports')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Not available to you',
          message:
              'Financial reports are drawn from the general ledger, which needs '
              'the accounting permissions.',
        ),
      );
    }

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Reports')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: FinancialReport.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final report = FinancialReport.values[index];
                return ChoiceChip(
                  label: Text(report.label),
                  selected: report == _report,
                  onSelected: (_) => _pick(report),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _report.blurb,
            style: TextStyle(color: bos.muted, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 16),
          _Period(
            report: _report,
            query: _query,
            onChanged: (query) => setState(() {
              _query = query;
              _running = null;
            }),
            onRun: () => setState(() => _running = _query),
          ),
          const SizedBox(height: 20),
          if (_running != null) _Result(query: _running!),
        ],
      ),
    );
  }
}

/// What the report is being asked for.
class _Period extends ConsumerWidget {
  const _Period({
    required this.report,
    required this.query,
    required this.onChanged,
    required this.onRun,
  });

  final FinancialReport report;
  final ReportQuery query;
  final ValueChanged<ReportQuery> onChanged;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final asAt = report.periodKind == ReportPeriodKind.asAt;

    // The ledger report needs an account, and only one that can be posted to
    // has anything in it worth reading.
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final ready = !report.needsAccount || query.accountId != null;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (report.needsAccount) ...[
            DropdownButtonFormField<int>(
              initialValue: query.accountId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Account',
                prefixIcon: Icon(Icons.account_tree_outlined),
              ),
              items: [
                for (final account in accounts)
                  DropdownMenuItem(
                    value: account.id,
                    child: Text(
                      '${account.accountCode}  ${account.accountName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => onChanged(
                ReportQuery(
                  report: report,
                  start: query.start,
                  end: query.end,
                  accountId: value,
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (asAt)
            DateField(
              label: 'As at',
              value: Fmt.parse(query.end),
              clearable: false,
              onChanged: (value) {
                if (value == null) return;
                onChanged(
                  ReportQuery(
                    report: report,
                    start: query.start,
                    end: Fmt.isoDate(value),
                    accountId: query.accountId,
                  ),
                );
              },
            )
          else
            Row(
              children: [
                Expanded(
                  child: DateField(
                    label: 'From',
                    value: Fmt.parse(query.start),
                    clearable: false,
                    onChanged: (value) {
                      if (value == null) return;
                      onChanged(
                        ReportQuery(
                          report: report,
                          start: Fmt.isoDate(value),
                          end: query.end,
                          accountId: query.accountId,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DateField(
                    label: 'To',
                    value: Fmt.parse(query.end),
                    clearable: false,
                    onChanged: (value) {
                      if (value == null) return;
                      onChanged(
                        ReportQuery(
                          report: report,
                          start: query.start,
                          end: Fmt.isoDate(value),
                          accountId: query.accountId,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          const SizedBox(height: 14),
          LoadingButton(
            label: 'Run it',
            loading: false,
            icon: Icons.play_arrow_rounded,
            onPressed: ready ? onRun : null,
          ),
          if (report.needsAccount && !ready) ...[
            const SizedBox(height: 8),
            Text(
              'Pick an account first.',
              style: TextStyle(color: bos.muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

/// Whatever came back, drawn the way that report wants to be read.
class _Result extends ConsumerWidget {
  const _Result({required this.query});

  final ReportQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reportProvider(query));

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Loader(),
      ),
      error: (error, _) => ErrorState(
        message: error is ApiException
            ? error.message
            : 'Could not run that report.',
        onRetry: () => ref.invalidate(reportProvider(query)),
      ),
      data: (data) => switch (data) {
        ProfitLoss() => _ProfitLossView(report: data),
        BalanceSheet() => _BalanceSheetView(report: data),
        TrialBalance() => _TrialBalanceView(report: data),
        CashFlow() => _CashFlowView(report: data),
        Ageing() => _AgeingView(report: data),
        AccountLedgerReport() => _AccountLedgerView(report: data),
        // Unreachable — every report maps to one of the six above — but a
        // silent blank would be worse than saying so.
        _ => const EmptyState(
            icon: Icons.help_outline_rounded,
            title: 'Nothing to show',
            message: 'That report came back in a shape the app does not know.',
          ),
      },
    );
  }
}

class _ProfitLossView extends StatelessWidget {
  const _ProfitLossView({required this.report});

  final ProfitLoss report;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final margin = report.margin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'Revenue',
                value: Fmt.money(report.totalRevenue),
                icon: Icons.trending_up_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                label: 'Expense',
                value: Fmt.money(report.totalExpense),
                icon: Icons.trending_down_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        StatCard(
          label: report.isProfit ? 'Net profit' : 'Net loss',
          value: Fmt.money(report.netProfit.abs()),
          suffix: margin == null ? null : '${Fmt.percent(margin * 100)} margin',
          icon: report.isProfit
              ? Icons.savings_outlined
              : Icons.warning_amber_rounded,
          tone: report.isProfit ? null : bos.danger,
        ),
        const SizedBox(height: 12),
        _Footnote(
          '${Fmt.date(report.periodStart)} to ${Fmt.date(report.periodEnd)}',
        ),
      ],
    );
  }
}

class _BalanceSheetView extends StatelessWidget {
  const _BalanceSheetView({required this.report});

  final BalanceSheet report;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!report.balanced) ...[
          MessageBanner.warning(
            'Assets are out by ${Fmt.money(report.outOfBalanceAmount.abs())}. '
            'Either an entry was posted unbalanced, or a fiscal year has not '
            'been closed so net income has not rolled into retained earnings.',
          ),
          const SizedBox(height: 12),
        ],
        AppCard(
          child: Column(
            children: [
              _Row('Assets', report.totalAssets, bold: true),
              const Divider(height: 20),
              _Row('Liabilities', report.totalLiabilities),
              _Row('Equity', report.totalEquity),
              const Divider(height: 20),
              _Row(
                'Liabilities and equity',
                report.totalLiabilities + report.totalEquity,
                bold: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Footnote('As at ${Fmt.date(report.asOfDate)}'),
      ],
    );
  }
}

class _TrialBalanceView extends StatelessWidget {
  const _TrialBalanceView({required this.report});

  final TrialBalance report;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!report.balances) ...[
          MessageBanner.error(
            'The two sides differ by ${Fmt.money(report.difference.abs())}. A '
            'trial balance that does not balance means something was posted '
            'unbalanced.',
          ),
          const SizedBox(height: 12),
        ],
        AppCard(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Account',
                      style: TextStyle(
                        color: bos.muted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 84,
                    child: Text(
                      'Debit',
                      textAlign: TextAlign.end,
                      style: TextStyle(color: bos.muted, fontSize: 11.5),
                    ),
                  ),
                  SizedBox(
                    width: 84,
                    child: Text(
                      'Credit',
                      textAlign: TextAlign.end,
                      style: TextStyle(color: bos.muted, fontSize: 11.5),
                    ),
                  ),
                ],
              ),
              const Divider(height: 16),
              for (final line in report.accounts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          [
                            if (line.accountCode != null) line.accountCode!,
                            line.accountName ?? '',
                          ].join('  ').trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: bos.text, fontSize: 12.5),
                        ),
                      ),
                      SizedBox(
                        width: 84,
                        child: Text(
                          line.debitBalance > 0
                              ? Fmt.money(line.debitBalance)
                              : '',
                          textAlign: TextAlign.end,
                          style: TextStyle(color: bos.text, fontSize: 12),
                        ),
                      ),
                      SizedBox(
                        width: 84,
                        child: Text(
                          line.creditBalance > 0
                              ? Fmt.money(line.creditBalance)
                              : '',
                          textAlign: TextAlign.end,
                          style: TextStyle(color: bos.text, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Totals',
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 84,
                    child: Text(
                      Fmt.money(report.totalDebit),
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 84,
                    child: Text(
                      Fmt.money(report.totalCredit),
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Footnote('As at ${Fmt.date(report.asOfDate)}'),
      ],
    );
  }
}

class _CashFlowView extends StatelessWidget {
  const _CashFlowView({required this.report});

  final CashFlow report;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'In',
                value: Fmt.money(report.totalInflows),
                icon: Icons.south_west_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                label: 'Out',
                value: Fmt.money(report.totalOutflows),
                icon: Icons.north_east_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            children: [
              _Row('Opening balance', report.openingBalance),
              _Row('Net change', report.netChange),
              const Divider(height: 20),
              _Row('Closing balance', report.closingBalance, bold: true),
            ],
          ),
        ),
        if (report.lines.isNotEmpty) ...[
          const SizedBox(height: 14),
          SectionHeader('By category', icon: Icons.category_outlined),
          const SizedBox(height: 10),
          AppCard(
            child: Column(
              children: [
                for (final line in report.lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            Fmt.label(line.category),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: bos.text, fontSize: 12.5),
                          ),
                        ),
                        Text(
                          Fmt.money(line.net),
                          style: TextStyle(
                            color: line.net >= 0 ? bos.text : bos.danger,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        _Footnote(
          '${Fmt.date(report.periodStart)} to ${Fmt.date(report.periodEnd)}',
        ),
      ],
    );
  }
}

class _AgeingView extends StatelessWidget {
  const _AgeingView({required this.report});

  final Ageing report;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final total = report.totalOutstanding;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'Outstanding',
                value: Fmt.money(total),
                icon: Icons.request_quote_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                label: 'Overdue',
                value: Fmt.money(report.overdue),
                icon: Icons.schedule_rounded,
                tone: report.overdue > 0 ? bos.warning : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            children: [
              for (final bucket in report.buckets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              bucket.label,
                              style:
                                  TextStyle(color: bos.text, fontSize: 12.5),
                            ),
                          ),
                          Text(
                            Fmt.money(bucket.amount),
                            style: TextStyle(
                              color: bos.text,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          // Against the total, so the buckets are comparable
                          // with each other rather than each filling its bar.
                          value: total <= 0 ? 0 : bucket.amount / total,
                          minHeight: 4,
                          backgroundColor: bos.borderLight,
                          color: bucket.label == 'Current'
                              ? bos.brand
                              : bos.warning,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (report.lines.isNotEmpty) ...[
          const SizedBox(height: 14),
          SectionHeader('Invoices', icon: Icons.receipt_long_outlined),
          const SizedBox(height: 10),
          for (final line in report.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            line.reference ?? 'Invoice ${line.documentId}',
                            style: TextStyle(
                              color: bos.text,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (line.counterparty != null) line.counterparty!,
                              line.isOverdue
                                  ? '${line.daysOverdue} days late'
                                  : 'due ${Fmt.date(line.dueDate)}',
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: line.isOverdue ? bos.warning : bos.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      Fmt.money(line.balanceAmount),
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 12),
        _Footnote('As at ${Fmt.date(report.asOfDate)}'),
      ],
    );
  }
}

class _AccountLedgerView extends StatelessWidget {
  const _AccountLedgerView({required this.report});

  final AccountLedgerReport report;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  if (report.accountCode != null) report.accountCode!,
                  report.accountName ?? '',
                ].join('  ').trim(),
                style: TextStyle(
                  color: bos.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              _Row('Opening', report.openingBalance),
              _Row('Movement', report.movement),
              const Divider(height: 20),
              _Row('Closing', report.closingBalance, bold: true),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Footnote(
          '${report.entries.length} postings, '
          '${Fmt.date(report.periodStart)} to ${Fmt.date(report.periodEnd)}',
        ),
        const SizedBox(height: 6),
        Text(
          'The postings themselves are on the Books screen, under Ledger, '
          'filtered to this account.',
          style: TextStyle(color: bos.muted, fontSize: 12, height: 1.45),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.amount, {this.bold = false});

  final String label;
  final double amount;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: bold ? bos.text : bos.muted,
                fontSize: 13,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            Fmt.money(amount),
            style: TextStyle(
              color: amount < 0 ? bos.danger : bos.text,
              fontSize: 13.5,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return Text(
      text,
      style: TextStyle(color: bos.muted, fontSize: 11.5),
    );
  }
}
