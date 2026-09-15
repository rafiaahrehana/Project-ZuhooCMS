import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/stat_card.dart';
import 'dashboard_models.dart';
import 'dashboard_repository.dart';

/// How the company is doing, in one screen.
///
/// The web dashboard is fifteen configurable widgets; this is the same figures
/// in a fixed order that reads top to bottom on a phone. What needs attention
/// comes first, and the totals follow.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(dashboardSummaryProvider);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('How things stand')),
      body: RefreshIndicator(
        color: bos.brand,
        backgroundColor: bos.bgCard,
        onRefresh: () async {
          ref.invalidate(dashboardSummaryProvider);
          ref.invalidate(recommendationsProvider);
        },
        child: async.when(
          loading: () => const Loader(),
          error: (error, _) => ErrorState(
            message: error is ApiException
                ? error.message
                : 'Could not load the figures.',
            onRetry: () => ref.invalidate(dashboardSummaryProvider),
          ),
          data: (summary) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              const _Recommendations(),
              _NeedsAttention(summary: summary),
              const SizedBox(height: 20),
              _Sales(summary: summary),
              const SizedBox(height: 20),
              _Work(summary: summary),
              const SizedBox(height: 20),
              _People(summary: summary),
              if (summary.overdueInvoices.isNotEmpty) ...[
                const SizedBox(height: 20),
                _Overdue(invoices: summary.overdueInvoices),
              ],
              if (summary.announcements.isNotEmpty) ...[
                const SizedBox(height: 20),
                _Announcements(announcements: summary.announcements),
              ],
              const SizedBox(height: 20),
              const _Insights(),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the system thinks is worth doing, worst first.
class _Recommendations extends ConsumerWidget {
  const _Recommendations();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recommendations = ref.watch(recommendationsProvider).value;
    if (recommendations == null || recommendations.isEmpty) {
      return const SizedBox.shrink();
    }

    final sorted = [...recommendations]..sort((a, b) {
        int rank(Recommendation r) =>
            r.isCritical ? 0 : (r.isWarning ? 1 : 2);
        return rank(a).compareTo(rank(b));
      });

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final recommendation in sorted)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              // The link each one carries is an Angular route, so there is
              // nothing to open — the message stands on its own.
              child: recommendation.isCritical
                  ? MessageBanner.error(recommendation.message)
                  : recommendation.isWarning
                      ? MessageBanner.warning(recommendation.message)
                      : MessageBanner.info(recommendation.message),
            ),
        ],
      ),
    );
  }
}

class _NeedsAttention extends StatelessWidget {
  const _NeedsAttention({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    final cards = <Widget>[
      if (summary.slaBreachedOpen > 0)
        StatCard(
          label: 'Past their SLA',
          value: summary.slaBreachedOpen.toString(),
          icon: Icons.running_with_errors_outlined,
          tone: bos.danger,
        ),
      if (summary.pendingLeaveApprovals > 0)
        StatCard(
          label: 'Leave to approve',
          value: summary.pendingLeaveApprovals.toString(),
          icon: Icons.event_available_outlined,
          tone: bos.warning,
        ),
      if (summary.newTickets > 0)
        StatCard(
          label: 'New tickets',
          value: summary.newTickets.toString(),
          icon: Icons.confirmation_number_outlined,
          tone: bos.warning,
        ),
      if (summary.outstandingInvoiceAmount > 0)
        StatCard(
          label: 'Owed to you',
          value: Fmt.money(summary.outstandingInvoiceAmount),
          icon: Icons.receipt_long_outlined,
          tone: bos.warning,
        ),
    ];

    if (cards.isEmpty) {
      return AppCard(
        child: Row(
          children: [
            Icon(Icons.check_circle_outline_rounded, color: bos.success),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Nothing is overdue, breached or waiting on you.',
                style: TextStyle(color: bos.text, fontSize: 13.5),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          'Needs attention',
          icon: Icons.priority_high_rounded,
        ),
        _Grid(children: cards),
      ],
    );
  }
}

class _Sales extends StatelessWidget {
  const _Sales({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Sales', icon: Icons.trending_up_rounded),
        _Grid(
          children: [
            StatCard(
              label: 'Leads',
              value: summary.totalLeads.toString(),
              icon: Icons.person_search_outlined,
              suffix: _trend(summary.leadsTrend),
            ),
            StatCard(
              label: 'Qualified',
              value: summary.qualifiedLeads.toString(),
              icon: Icons.verified_outlined,
            ),
            StatCard(
              label: 'Clients',
              value: summary.totalClients.toString(),
              icon: Icons.apartment_outlined,
              suffix: _trend(summary.clientsTrend),
            ),
            StatCard(
              label: 'Open deals',
              value: summary.openOpportunities.toString(),
              icon: Icons.handshake_outlined,
              suffix: _trend(summary.opportunitiesTrend),
            ),
            StatCard(
              label: 'Pipeline',
              value: Fmt.money(summary.pipelineValue),
              icon: Icons.stacked_line_chart_rounded,
            ),
            StatCard(
              label: 'Forecast',
              value: Fmt.money(summary.weightedForecast),
              icon: Icons.query_stats_rounded,
            ),
          ],
        ),
      ],
    );
  }
}

class _Work extends StatelessWidget {
  const _Work({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Work in hand', icon: Icons.assignment_outlined),
        _Grid(
          children: [
            StatCard(
              label: 'Waiting to start',
              value: summary.pendingRequests.toString(),
              icon: Icons.hourglass_empty_rounded,
            ),
            StatCard(
              label: 'Under way',
              value: summary.inProgressRequests.toString(),
              icon: Icons.play_circle_outline_rounded,
            ),
            StatCard(
              label: 'Open tickets',
              value: summary.openTickets.toString(),
              icon: Icons.support_agent_outlined,
            ),
            StatCard(
              label: 'Wallet',
              value: Fmt.money(summary.walletBalance),
              icon: Icons.account_balance_wallet_outlined,
            ),
          ],
        ),
      ],
    );
  }
}

class _People extends StatelessWidget {
  const _People({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('People', icon: Icons.groups_outlined),
        _Grid(
          children: [
            StatCard(
              label: 'On the books',
              value: summary.totalEmployees.toString(),
              icon: Icons.badge_outlined,
            ),
            StatCard(
              label: 'In today',
              value: summary.employeesPresentToday.toString(),
              icon: Icons.how_to_reg_outlined,
            ),
            StatCard(
              label: 'On leave',
              value: summary.employeesOnLeave.toString(),
              icon: Icons.beach_access_outlined,
            ),
          ],
        ),
      ],
    );
  }
}

class _Overdue extends StatelessWidget {
  const _Overdue({required this.invoices});

  final List<OverdueInvoice> invoices;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          'Overdue invoices',
          icon: Icons.receipt_long_outlined,
        ),
        AppCard(
          child: Column(
            children: [
              for (final invoice in invoices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              invoice.clientName ?? 'A client',
                              style: TextStyle(color: bos.text, fontSize: 13.5),
                            ),
                            Text(
                              '${invoice.invoiceNumber} · '
                              '${invoice.daysOverdue} days late',
                              style:
                                  TextStyle(color: bos.muted, fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        Fmt.money(invoice.amount),
                        style: TextStyle(
                          color: bos.danger,
                          fontSize: 13.5,
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
    );
  }
}

class _Announcements extends StatelessWidget {
  const _Announcements({required this.announcements});

  final List<DashboardAnnouncement> announcements;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Notices', icon: Icons.campaign_outlined),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final announcement in announcements)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        announcement.title,
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (announcement.content != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            announcement.content!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: bos.text,
                              fontSize: 12.5,
                              height: 1.5,
                            ),
                          ),
                        ),
                      if (announcement.timeAgo != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            announcement.timeAgo!,
                            style:
                                TextStyle(color: bos.muted, fontSize: 11.5),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The assistant's read on the figures.
///
/// Asked for on a press rather than loaded with the screen: it costs a call to
/// whichever provider the company has configured, and most visits to a
/// dashboard are a glance at the numbers.
class _Insights extends ConsumerStatefulWidget {
  const _Insights();

  @override
  ConsumerState<_Insights> createState() => _InsightsState();
}

class _InsightsState extends ConsumerState<_Insights> {
  bool _asked = false;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    if (!_asked) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Want the assistant to read these figures back to you?',
              style: TextStyle(color: bos.text, fontSize: 13.5),
            ),
            const SizedBox(height: 10),
            LoadingButton(
              label: 'Ask it',
              icon: Icons.auto_awesome_rounded,
              loading: false,
              onPressed: () => setState(() => _asked = true),
            ),
          ],
        ),
      );
    }

    final async = ref.watch(dashboardInsightsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          'What it makes of this',
          icon: Icons.auto_awesome_rounded,
        ),
        AppCard(
          child: async.when(
            loading: () => const Loader(padding: 16, message: 'Reading it'),
            error: (error, _) => MessageBanner.error(
              error is ApiException
                  ? error.message
                  : 'Could not get a read on the figures.',
            ),
            data: (insights) => SelectableText(
              insights.insights,
              style: TextStyle(color: bos.text, fontSize: 13.5, height: 1.6),
            ),
          ),
        ),
      ],
    );
  }
}

/// Two stat cards to a row, wrapping.
class _Grid extends StatelessWidget {
  const _Grid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final width = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children)
              SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

String? _trend(double value) {
  if (value == 0) return null;
  final sign = value > 0 ? '+' : '';
  return '$sign${value.toStringAsFixed(0)}%';
}
