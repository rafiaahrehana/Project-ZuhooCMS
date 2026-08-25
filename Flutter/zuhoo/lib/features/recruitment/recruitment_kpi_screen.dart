import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/stat_card.dart';
import 'recruitment_models.dart';
import 'recruitment_repository.dart';

/// How hiring is going.
///
/// The per-job and per-recruiter breakdowns the web shows are deliberately not
/// here: they are wide comparison tables, and half a comparison on a phone
/// says less than none. What is here is the shape of the funnel and the rates
/// that describe it.
final recruitmentKpisProvider = FutureProvider.autoDispose<RecruitmentKpis>(
  (ref) => ref.read(recruitmentRepositoryProvider).kpis(),
);

class RecruitmentKpiScreen extends ConsumerWidget {
  const RecruitmentKpiScreen({super.key});

  static void open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const RecruitmentKpiScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(recruitmentKpisProvider);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Hiring')),
      body: RefreshIndicator(
        color: bos.brand,
        backgroundColor: bos.bgCard,
        onRefresh: () async => ref.invalidate(recruitmentKpisProvider),
        child: async.when(
          loading: () => const Loader(),
          error: (error, _) => ErrorState(
            message: error is ApiException
                ? error.message
                : 'Could not load the hiring figures.',
            onRetry: () => ref.invalidate(recruitmentKpisProvider),
          ),
          data: (kpis) => _Body(kpis: kpis),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.kpis});

  final RecruitmentKpis kpis;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'Open positions',
                value: '${kpis.openPositions}',
                icon: Icons.work_outline_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                label: 'Hired this month',
                value: '${kpis.hiresThisMonth}',
                suffix: '${kpis.hiresTotal} all told',
                icon: Icons.how_to_reg_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'Candidates',
                value: '${kpis.totalCandidates}',
                icon: Icons.groups_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                label: 'Applications',
                value: '${kpis.totalApplications}',
                icon: Icons.description_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SectionHeader('How long it takes', icon: Icons.timelapse_rounded),
        const SizedBox(height: 10),
        AppCard(
          child: Column(
            children: [
              _Metric(
                label: 'Offer to start',
                // Every rate here is nullable, and a null renders as a dash
                // rather than a zero — no offers made is not a nought-day
                // time to hire.
                value: kpis.avgTimeToHireDays == null
                    ? null
                    : '${kpis.avgTimeToHireDays!.toStringAsFixed(1)} days',
              ),
              _Metric(
                label: 'Vacancy to filled',
                value: kpis.avgTimeToFillDays == null
                    ? null
                    : '${kpis.avgTimeToFillDays!.toStringAsFixed(1)} days',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionHeader('Conversion', icon: Icons.filter_alt_outlined),
        const SizedBox(height: 10),
        AppCard(
          child: Column(
            children: [
              _Metric(
                label: 'Application to interview',
                value: _rate(kpis.applicationToInterviewRate),
              ),
              _Metric(
                label: 'Interview to hire',
                value: _rate(kpis.interviewToHireRate),
              ),
              _Metric(
                label: 'Offers accepted',
                value: _rate(kpis.offerAcceptanceRate),
              ),
              if (kpis.avgAtsMatchScore != null)
                _Metric(
                  label: 'Average match score',
                  value: kpis.avgAtsMatchScore!.toStringAsFixed(1),
                ),
            ],
          ),
        ),
        if (kpis.funnel.isNotEmpty) ...[
          const SizedBox(height: 16),
          SectionHeader('The funnel', icon: Icons.stacked_bar_chart_rounded),
          const SizedBox(height: 10),
          _Bars(counts: kpis.funnel, colour: bos.brand),
        ],
        if (kpis.sourceBreakdown.isNotEmpty) ...[
          const SizedBox(height: 16),
          SectionHeader('Where they came from', icon: Icons.share_outlined),
          const SizedBox(height: 10),
          _Bars(counts: kpis.sourceBreakdown, colour: bos.brandInk),
        ],
      ],
    );
  }

  /// The backend sends these as percentages already, not fractions.
  static String? _rate(double? value) =>
      value == null ? null : Fmt.percent(value);
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;

  /// Null renders as a dash — the figure is unknown, not zero.
  final String? value;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: bos.muted, fontSize: 13),
            ),
          ),
          Text(
            value ?? '—',
            style: TextStyle(
              color: value == null ? bos.muted : bos.text,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal bars, each against the largest — the comparison between stages
/// is what a funnel is for, not the absolute numbers.
class _Bars extends StatelessWidget {
  const _Bars({required this.counts, required this.colour});

  final List<KpiCount> counts;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final peak = counts.fold<int>(0, (a, b) => a > b.count ? a : b.count);

    return AppCard(
      child: Column(
        children: [
          for (final row in counts)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          Fmt.label(row.label),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: bos.text, fontSize: 12.5),
                        ),
                      ),
                      Text(
                        '${row.count}',
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: peak <= 0 ? 0 : row.count / peak,
                      minHeight: 4,
                      backgroundColor: bos.borderLight,
                      color: colour,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
