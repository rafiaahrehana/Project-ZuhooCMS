import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import '../platform/platform_models.dart' show SubscriptionPlanOption;
import '../platform/platform_repository.dart' show subscriptionPlansProvider;
import 'company_models.dart';
import 'company_repository.dart';

/// What the company is paying for, and what else is on offer.
///
/// Upgrading is a real payment, so this hands off to it rather than taking
/// it: SSLCommerz's hosted checkout is a web page, and the backend's own
/// success/failure callbacks redirect back to the *web* app
/// (`app.frontend-url`), not anywhere this app could intercept. Opening it in
/// the system browser is therefore not a shortcut — it is the only place this
/// flow actually completes today. The company owner pays there, then comes
/// back and pulls to refresh.
class SubscriptionPlanScreen extends ConsumerWidget {
  const SubscriptionPlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final company = ref.watch(myCompanyProvider);
    final plans = ref.watch(subscriptionPlansProvider);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Plans & Upgrade')),
      body: RefreshIndicator(
        color: bos.brand,
        backgroundColor: bos.bgCard,
        onRefresh: () async {
          ref.invalidate(myCompanyProvider);
          ref.invalidate(subscriptionPlansProvider);
        },
        child: company.when(
          loading: () => const Loader(),
          error: (error, _) => ErrorState(
            message: error is ApiException
                ? error.message
                : 'Could not load your subscription.',
            onRetry: () => ref.invalidate(myCompanyProvider),
          ),
          data: (profile) => plans.when(
            loading: () => const Loader(),
            error: (error, _) => ErrorState(
              message: error is ApiException
                  ? error.message
                  : 'Could not load the available plans.',
              onRetry: () => ref.invalidate(subscriptionPlansProvider),
            ),
            data: (options) => _Body(profile: profile, plans: options),
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.profile, required this.plans});

  final CompanyProfile profile;
  final List<SubscriptionPlanOption> plans;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  int? _startingCheckoutFor;

  double get _currentPrice {
    final code = widget.profile.subscriptionPlan;
    final matching = widget.plans.where((p) => p.key == code);
    return matching.isEmpty ? 0 : (matching.first.price ?? 0);
  }

  Future<void> _upgrade(SubscriptionPlanOption plan) async {
    if (plan.id == null || plan.price == null) return;
    setState(() => _startingCheckoutFor = plan.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await ref.read(companyRepositoryProvider).initiateSubscriptionUpgrade(
            SubscriptionUpgradeRequest(planId: plan.id!, amount: plan.price!),
          );
      final uri = Uri.tryParse(url);
      final launched = uri == null
          ? false
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not open the payment page.')),
        );
        return;
      }
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Finish paying in the browser, then come back and pull to '
              'refresh.',
            ),
            duration: Duration(seconds: 6),
          ),
        );
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not start the payment.')),
      );
    } finally {
      if (mounted) setState(() => _startingCheckoutFor = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final currentCode = widget.profile.subscriptionPlan;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.workspace_premium_outlined, color: bos.brandInk),
                  const SizedBox(width: 8),
                  Text(
                    'Current plan',
                    style: TextStyle(
                      color: bos.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                currentCode == null || currentCode.isEmpty
                    ? 'No plan on record'
                    : Fmt.label(currentCode),
                style: TextStyle(
                  color: bos.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (widget.profile.subscriptionEnd != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Renews or expires ${Fmt.date(widget.profile.subscriptionEnd)}',
                  style: TextStyle(color: bos.muted, fontSize: 12.5),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        SectionHeader('Available plans', icon: Icons.view_list_outlined),
        const SizedBox(height: 10),
        if (widget.plans.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: EmptyState(
              icon: Icons.workspace_premium_outlined,
              title: 'No plans to show',
              message: 'Nothing is on offer right now.',
            ),
          )
        else
          for (final plan in widget.plans)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PlanCard(
                plan: plan,
                isCurrent: plan.key == currentCode,
                // Matches the backend's own rule (SslCommerzServiceImpl):
                // only a strictly higher-priced plan than the one already
                // paid for can be bought through this flow.
                canUpgradeTo: plan.key != currentCode &&
                    (plan.price ?? 0) > _currentPrice,
                busy: _startingCheckoutFor == plan.id,
                onUpgrade: () => _upgrade(plan),
              ),
            ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.isCurrent,
    required this.canUpgradeTo,
    required this.busy,
    required this.onUpgrade,
  });

  final SubscriptionPlanOption plan;
  final bool isCurrent;
  final bool canUpgradeTo;
  final bool busy;
  final VoidCallback onUpgrade;

  /// The seeded description is comma-separated phrases ("Email support, up to
  /// 10 users, standard integrations.") — split into a feature checklist, the
  /// same way the web app reads it.
  List<String> get _features {
    final description = plan.description;
    if (description == null || description.trim().isEmpty) return const [];
    return description
        .replaceFirst(RegExp(r'\.$'), '')
        .split(',')
        .map((f) => f.trim())
        .where((f) => f.isNotEmpty)
        .map((f) => f[0].toUpperCase() + f.substring(1))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.name,
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (isCurrent)
                const StatusChip('APPROVED', label: 'Current plan', dense: true)
              else if (!plan.active)
                StatusChip('CANCELLED', label: 'Not on offer', dense: true),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                Fmt.money(plan.price),
                style: TextStyle(
                  color: bos.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              if (plan.billingCycle != null) ...[
                const SizedBox(width: 4),
                Text(
                  '/ ${Fmt.label(plan.billingCycle!).toLowerCase()}',
                  style: TextStyle(color: bos.muted, fontSize: 12.5),
                ),
              ],
            ],
          ),
          if (_features.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final feature in _features)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_rounded, size: 16, color: bos.success),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        feature,
                        style: TextStyle(color: bos.textSecondary, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (canUpgradeTo) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: LoadingButton(
                label: 'Upgrade',
                loading: busy,
                icon: Icons.arrow_upward_rounded,
                onPressed: onUpgrade,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
