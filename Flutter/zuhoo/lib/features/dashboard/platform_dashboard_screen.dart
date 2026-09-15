import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/stat_card.dart';
import 'dashboard_repository.dart';

/// Every tenant, seen from the outside.
///
/// The platform's own dashboard rather than a company's. Gated on the platform
/// staff roles — a tenant user calling these endpoints gets a 403, which is
/// why this screen is reached only from the platform area.
class PlatformDashboardScreen extends ConsumerWidget {
  const PlatformDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(platformSummaryProvider);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('The platform')),
      body: RefreshIndicator(
        color: bos.brand,
        backgroundColor: bos.bgCard,
        onRefresh: () async {
          ref.invalidate(platformSummaryProvider);
          ref.invalidate(platformHistoryProvider);
        },
        child: async.when(
          loading: () => const Loader(),
          error: (error, _) => ErrorState(
            message: error is ApiException
                ? error.message
                : 'Could not load the platform figures.',
            onRetry: () => ref.invalidate(platformSummaryProvider),
          ),
          data: (summary) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              if (summary.trialsExpiringWithin7Days > 0) ...[
                MessageBanner.warning(
                  '${summary.trialsExpiringWithin7Days} '
                  '${summary.trialsExpiringWithin7Days == 1 ? "trial ends" : "trials end"}'
                  ' within the week.',
                ),
                const SizedBox(height: 12),
              ],
              if (summary.pendingVerificationCompanies > 0) ...[
                MessageBanner.info(
                  '${summary.pendingVerificationCompanies} waiting to be '
                  'verified.',
                ),
                const SizedBox(height: 12),
              ],
              const SectionHeader('Companies', icon: Icons.domain_outlined),
              _Grid(
                children: [
                  StatCard(
                    label: 'All of them',
                    value: summary.totalCompanies.toString(),
                    icon: Icons.apartment_outlined,
                  ),
                  StatCard(
                    label: 'Active',
                    value: summary.activeCompanies.toString(),
                    icon: Icons.check_circle_outline_rounded,
                    tone: bos.success,
                  ),
                  StatCard(
                    label: 'On trial',
                    value: summary.trialCompanies.toString(),
                    icon: Icons.schedule_rounded,
                  ),
                  StatCard(
                    label: 'Suspended',
                    value: summary.suspendedCompanies.toString(),
                    icon: Icons.block_rounded,
                    tone: summary.suspendedCompanies > 0 ? bos.danger : null,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const SectionHeader('Money', icon: Icons.payments_outlined),
              _Grid(
                children: [
                  StatCard(
                    label: 'This month',
                    value: Fmt.money(summary.revenueThisMonth),
                    icon: Icons.calendar_month_outlined,
                  ),
                  StatCard(
                    label: 'All time',
                    value: Fmt.money(summary.totalRevenue),
                    icon: Icons.savings_outlined,
                  ),
                ],
              ),
              if (summary.companiesByPlan.isNotEmpty) ...[
                const SizedBox(height: 20),
                const SectionHeader('By plan', icon: Icons.layers_outlined),
                AppCard(
                  child: Column(
                    children: [
                      for (final plan in summary.companiesByPlan)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  plan.name.isEmpty ? plan.code : plan.name,
                                  style: TextStyle(
                                    color: bos.text,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              Text(
                                plan.count.toString(),
                                style:
                                    TextStyle(color: bos.text, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              StatCard(
                label: 'Platform staff',
                value: summary.totalPlatformUsers.toString(),
                icon: Icons.admin_panel_settings_outlined,
              ),
              const SizedBox(height: 20),
              const _History(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The last thirty days, from the nightly snapshots.
///
/// Shown as a short table rather than a chart. The snapshots only started at
/// some point, so early days are simply absent — a line drawn through the gap
/// would invent figures that were never taken.
class _History extends ConsumerWidget {
  const _History();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(platformHistoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Recent days', icon: Icons.show_chart_rounded),
        AppCard(
          child: async.when(
            loading: () => const Loader(padding: 16),
            error: (_, _) => Text(
              'The daily figures could not be loaded.',
              style: TextStyle(color: bos.muted, fontSize: 13),
            ),
            data: (points) {
              if (points.isEmpty) {
                return Text(
                  'No daily snapshots have been taken yet.',
                  style: TextStyle(color: bos.muted, fontSize: 13),
                );
              }

              // Newest first, and only as far back as fits on a phone.
              final recent = points.reversed.take(14).toList(growable: false);

              return Column(
                children: [
                  for (final point in recent)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              Fmt.dateShort(point.date),
                              style:
                                  TextStyle(color: bos.muted, fontSize: 12),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              '${point.activeCompanies} active',
                              style: TextStyle(color: bos.text, fontSize: 12),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              Fmt.money(point.revenue),
                              textAlign: TextAlign.right,
                              style: TextStyle(color: bos.text, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

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
