import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/paged_response.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/stat_card.dart';
import 'crm_models.dart';
import 'crm_repository.dart';

/// Everything the report needs, fetched once. Angular's own version pulls
/// each of these with `size: 500`-`1000` and does the same arithmetic
/// client-side — there is no reporting endpoint of its own on the backend, so
/// this mirrors that rather than inventing a leaner one.
typedef _ReportData = ({
  PipelineSummary summary,
  List<Opportunity> won,
  List<Opportunity> lost,
  List<Opportunity> all,
  List<Lead> leads,
});

final _crmReportsProvider = FutureProvider.autoDispose<_ReportData>((ref) async {
  final repo = ref.read(crmRepositoryProvider);
  final results = await Future.wait([
    repo.pipelineSummary(),
    repo.opportunities(stage: Stage.won, size: 500),
    repo.opportunities(stage: Stage.lost, size: 500),
    repo.opportunities(size: 1000),
    repo.leads(LeadView.all, size: 1000),
  ]);
  return (
    summary: results[0] as PipelineSummary,
    won: (results[1] as PagedResponse<Opportunity>).content,
    lost: (results[2] as PagedResponse<Opportunity>).content,
    all: (results[3] as PagedResponse<Opportunity>).content,
    leads: (results[4] as PagedResponse<Lead>).content,
  );
});

/// Stage breakdown and win/loss trends across the sales pipeline — Angular's
/// `pipeline-reports`, minus the charts a phone has no room for. The same
/// numbers, laid out as bars and short lists instead of canvases.
class CrmReportsScreen extends ConsumerWidget {
  const CrmReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(_crmReportsProvider);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('CRM Reports')),
      body: RefreshIndicator(
        color: bos.brand,
        backgroundColor: bos.bgCard,
        onRefresh: () async => ref.invalidate(_crmReportsProvider),
        child: async.when(
          loading: () => const Loader(),
          error: (error, _) => ErrorState(
            message: error is ApiException
                ? error.message
                : 'Could not load the pipeline reports.',
            onRetry: () => ref.invalidate(_crmReportsProvider),
          ),
          data: (data) => _Report(data: data),
        ),
      ),
    );
  }
}

class _Report extends StatelessWidget {
  const _Report({required this.data});

  final _ReportData data;

  double get _wonAmount =>
      data.won.fold(0.0, (sum, o) => sum + (o.amount ?? 0));
  double get _lostAmount =>
      data.lost.fold(0.0, (sum, o) => sum + (o.amount ?? 0));
  int get _winRate {
    final total = data.won.length + data.lost.length;
    return total == 0 ? 0 : ((data.won.length / total) * 100).round();
  }

  /// The last 6 calendar months, oldest first — the window both the trend and
  /// the revenue sections bucket into.
  List<DateTime> get _months {
    final now = DateTime.now();
    return [for (var i = 5; i >= 0; i--) DateTime(now.year, now.month - i)];
  }

  bool _sameMonth(String? isoDate, DateTime month) {
    if (isoDate == null) return false;
    final d = DateTime.tryParse(isoDate);
    return d != null && d.year == month.year && d.month == month.month;
  }

  /// Open pipeline grouped by expected close month: the raw sum and the
  /// probability-weighted sum side by side. Deals with no close date get
  /// their own "No close date" row instead of being dropped — undated deals
  /// are a hygiene problem worth surfacing, not hiding.
  List<({String label, int count, double amount, double weighted, int order})>
      get _forecast {
    final open = data.all.where((o) => o.isOpen);
    final buckets =
        <String, ({String label, int count, double amount, double weighted, int order})>{};

    for (final o in open) {
      String key = 'none';
      String label = 'No close date';
      var order = 1 << 30;
      final close = o.expectedCloseDate == null
          ? null
          : DateTime.tryParse(o.expectedCloseDate!);
      if (close != null) {
        key = '${close.year}-${close.month}';
        label = DateFormat('MMM yyyy').format(close);
        order = close.year * 12 + close.month;
      }
      final existing = buckets[key];
      final amount = o.amount ?? 0;
      final weighted = amount * (o.probability / 100);
      buckets[key] = (
        label: label,
        count: (existing?.count ?? 0) + 1,
        amount: (existing?.amount ?? 0) + amount,
        weighted: (existing?.weighted ?? 0) + weighted,
        order: order,
      );
    }
    return buckets.values.toList()..sort((a, b) => a.order.compareTo(b.order));
  }

  /// Lost value by picklist code, largest first. A deal closed before the
  /// picklist existed carries only free text, and is grouped as "Not
  /// recorded" — shown, not hidden, so the report stays honest about its own
  /// coverage.
  List<({String label, int count, double value, int pct})> get _lossReasons {
    if (data.lost.isEmpty) return const [];
    final labels = {for (final r in lostReasons) r.code: r.label};
    final byCode = <String, ({int count, double value})>{};
    for (final o in data.lost) {
      final key = o.lostReasonCode ?? 'UNRECORDED';
      final existing = byCode[key];
      byCode[key] = (
        count: (existing?.count ?? 0) + 1,
        value: (existing?.value ?? 0) + (o.amount ?? 0),
      );
    }
    final total = data.lost.length;
    final rows = byCode.entries
        .map((e) => (
              label: labels[e.key] ?? 'Not recorded',
              count: e.value.count,
              value: e.value.value,
              pct: ((e.value.count / total) * 100).round(),
            ))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return rows;
  }

  List<
      ({
        String ownerName,
        int total,
        int won,
        int lost,
        double wonValue,
        int winRate
      })> get _salesPerformance {
    final byOwner = <String, ({String ownerName, int total, int won, int lost, double wonValue})>{};
    for (final o in data.all) {
      final key = o.ownerName ?? 'unassigned';
      final existing = byOwner[key];
      byOwner[key] = (
        ownerName: o.ownerName ?? 'Unassigned',
        total: (existing?.total ?? 0) + 1,
        won: (existing?.won ?? 0) + (o.isWon ? 1 : 0),
        lost: (existing?.lost ?? 0) + (o.isLost ? 1 : 0),
        wonValue: (existing?.wonValue ?? 0) + (o.isWon ? (o.amount ?? 0) : 0),
      );
    }
    final rows = byOwner.values
        .map((r) => (
              ownerName: r.ownerName,
              total: r.total,
              won: r.won,
              lost: r.lost,
              wonValue: r.wonValue,
              winRate: (r.won + r.lost) == 0
                  ? 0
                  : ((r.won / (r.won + r.lost)) * 100).round(),
            ))
        .toList()
      ..sort((a, b) => b.wonValue.compareTo(a.wonValue));
    return rows;
  }

  int get _convertedLeads => data.leads.where((l) => l.converted).length;
  int get _leadConversionRate =>
      data.leads.isEmpty ? 0 : ((_convertedLeads / data.leads.length) * 100).round();

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final months = _months;
    final maxStage = data.summary.stages.fold(
      0.0,
      (max, s) => s.totalAmount > max ? s.totalAmount : max,
    );

    final trendByMonth = [
      for (final m in months)
        (
          label: DateFormat('MMM').format(m),
          won: data.won.where((o) => _sameMonth(o.actualCloseDate, m)).length,
          lost: data.lost.where((o) => _sameMonth(o.actualCloseDate, m)).length,
        ),
    ];
    final maxTrend = trendByMonth.fold(
      0,
      (max, r) => [max, r.won, r.lost].reduce((a, b) => a > b ? a : b),
    );

    final revenueByMonth = [
      for (final m in months)
        (
          label: DateFormat('MMM').format(m),
          amount: data.won
              .where((o) => _sameMonth(o.actualCloseDate, m))
              .fold(0.0, (sum, o) => sum + (o.amount ?? 0)),
        ),
    ];
    final maxRevenue = revenueByMonth.fold(
      0.0,
      (max, r) => r.amount > max ? r.amount : max,
    );

    final forecast = _forecast;
    final forecastTotals = forecast.fold(
      (amount: 0.0, weighted: 0.0),
      (acc, r) => (amount: acc.amount + r.amount, weighted: acc.weighted + r.weighted),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'Won',
                value: Fmt.money(_wonAmount),
                icon: Icons.emoji_events_outlined,
                tone: bos.success,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                label: 'Lost',
                value: Fmt.money(_lostAmount),
                icon: Icons.cancel_outlined,
                tone: bos.danger,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                label: 'Win rate',
                value: '$_winRate',
                suffix: '%',
                icon: Icons.percent_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SectionHeader('Pipeline value by stage', icon: Icons.bar_chart_rounded),
        const SizedBox(height: 10),
        AppCard(
          child: data.summary.stages.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No open pipeline.'),
                )
              : Column(
                  children: [
                    for (final stage in data.summary.stages)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _BarRow(
                          label: Fmt.label(stage.stage),
                          valueText: Fmt.money(stage.totalAmount),
                          fraction: maxStage <= 0 ? 0 : stage.totalAmount / maxStage,
                          color: bos.brand,
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 18),
        SectionHeader('Won vs lost, last 6 months',
            icon: Icons.stacked_line_chart_rounded),
        const SizedBox(height: 10),
        AppCard(
          child: Column(
            children: [
              for (final row in trendByMonth)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(row.label,
                          style: TextStyle(color: bos.text, fontSize: 12.5)),
                      const SizedBox(height: 4),
                      _BarRow(
                        label: 'Won',
                        valueText: '${row.won}',
                        fraction: maxTrend == 0 ? 0 : row.won / maxTrend,
                        color: bos.success,
                        dense: true,
                      ),
                      const SizedBox(height: 4),
                      _BarRow(
                        label: 'Lost',
                        valueText: '${row.lost}',
                        fraction: maxTrend == 0 ? 0 : row.lost / maxTrend,
                        color: bos.danger,
                        dense: true,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SectionHeader('Lead conversion', icon: Icons.filter_alt_outlined),
        const SizedBox(height: 10),
        AppCard(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _MiniStat(value: '${data.leads.length}', label: 'Total leads'),
                  _MiniStat(
                    value: '$_convertedLeads',
                    label: 'Converted',
                    color: bos.success,
                  ),
                  _MiniStat(
                    value: '$_leadConversionRate%',
                    label: 'Conversion rate',
                    color: bos.brand,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              for (final status in LeadStatus.all)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _BarRow(
                    label: Fmt.label(status),
                    valueText:
                        '${data.leads.where((l) => l.status == status).length}',
                    fraction: data.leads.isEmpty
                        ? 0
                        : data.leads.where((l) => l.status == status).length /
                            data.leads.length,
                    color: bos.statusColors(status).fg,
                    dense: true,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SectionHeader('Revenue by month', icon: Icons.trending_up_rounded),
        const SizedBox(height: 10),
        AppCard(
          child: Column(
            children: [
              for (final row in revenueByMonth)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _BarRow(
                    label: row.label,
                    valueText: Fmt.money(row.amount),
                    fraction: maxRevenue <= 0 ? 0 : row.amount / maxRevenue,
                    color: bos.success,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SectionHeader('Forecast', icon: Icons.calendar_month_outlined),
        const SizedBox(height: 2),
        Text(
          'Open pipeline by expected close month',
          style: TextStyle(color: bos.muted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        AppCard(
          child: forecast.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No open opportunities.'),
                )
              : Column(
                  children: [
                    for (final row in forecast)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text(row.label,
                                  style: TextStyle(color: bos.text, fontSize: 13)),
                            ),
                            Expanded(
                              child: Text(
                                '${row.count} deals',
                                textAlign: TextAlign.end,
                                style: TextStyle(color: bos.muted, fontSize: 12),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                Fmt.money(row.weighted),
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                  color: bos.text,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Divider(height: 18),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text('Total',
                              style: TextStyle(
                                  color: bos.text,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                        ),
                        Expanded(
                          child: Text(
                            Fmt.money(forecastTotals.amount),
                            textAlign: TextAlign.end,
                            style: TextStyle(color: bos.muted, fontSize: 12),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            Fmt.money(forecastTotals.weighted),
                            textAlign: TextAlign.end,
                            style: TextStyle(
                                color: bos.text,
                                fontSize: 13,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 18),
        SectionHeader('Why deals are lost', icon: Icons.thumb_down_outlined),
        const SizedBox(height: 10),
        AppCard(
          child: _lossReasons.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No lost deals — nothing to explain yet.'),
                )
              : Column(
                  children: [
                    for (final row in _lossReasons)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _BarRow(
                          label: row.label,
                          valueText: '${row.count} (${row.pct}%)',
                          fraction: row.pct / 100,
                          color: bos.danger,
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 18),
        SectionHeader('Sales performance', icon: Icons.leaderboard_outlined),
        const SizedBox(height: 10),
        if (_salesPerformance.isEmpty)
          const AppCard(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No opportunities yet.'),
            ),
          )
        else
          for (final row in _salesPerformance)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            row.ownerName,
                            style: TextStyle(
                              color: bos.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          Fmt.money(row.wonValue),
                          style: TextStyle(
                            color: bos.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${row.total} opportunities · '
                      '${row.won} won · ${row.lost} lost · ${row.winRate}% win rate',
                      style: TextStyle(color: bos.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.value, required this.label, this.color});

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color ?? bos.text,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: bos.muted, fontSize: 11.5)),
      ],
    );
  }
}

/// A label, a value, and a bar whose length is the fraction of some maximum.
/// The same visual language as the accounts-payable ageing buckets — this
/// codebase's one hand-rolled chart primitive, reused rather than reinvented.
class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.valueText,
    required this.fraction,
    required this.color,
    this.dense = false,
  });

  final String label;
  final String valueText;
  final double fraction;
  final Color color;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: bos.text,
                  fontSize: dense ? 11.5 : 12.5,
                ),
              ),
            ),
            Text(
              valueText,
              style: TextStyle(
                color: bos.text,
                fontSize: dense ? 11.5 : 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: fraction.clamp(0, 1).toDouble(),
            minHeight: dense ? 4 : 5,
            backgroundColor: bos.borderLight,
            color: color,
          ),
        ),
      ],
    );
  }
}
