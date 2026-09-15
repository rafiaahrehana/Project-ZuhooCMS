import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/primitives.dart';
import '../catalogue/catalogue_models.dart' show ServicePackage;
import '../catalogue/catalogue_repository.dart' show activePackagesProvider;
import 'portal_home_screen.dart' show SubscriptionCard;
import 'portal_models.dart';
import 'portal_repository.dart';

/// Plans: what the client already has, and what else is on offer.
///
/// Angular's `client-packages` component in one screen — its own tabs for
/// "my subscriptions" and "browse the catalog", reached from the "Browse
/// plans" action on the client dashboard rather than a sixth bottom-nav tab,
/// which a phone width does not have room for on top of the five it already
/// carries.
class PortalPackagesScreen extends StatelessWidget {
  const PortalPackagesScreen({super.key});

  static void open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PortalPackagesScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(
          title: const Text('Plans'),
          bottom: const TabBar(
            tabs: [Tab(text: 'My plans'), Tab(text: 'Browse')],
          ),
        ),
        body: const TabBarView(children: [_MyPlansTab(), _BrowseTab()]),
      ),
    );
  }
}

class _MyPlansTab extends ConsumerWidget {
  const _MyPlansTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(clientPackageSubscriptionsProvider.notifier);

    return PagedListView<PackageSubscription>(
      async: ref.watch(clientPackageSubscriptionsProvider),
      onRefresh: controller.refresh,
      onLoadMore: () => guardListAction(context, controller.loadMore),
      emptyIcon: Icons.card_membership_outlined,
      emptyTitle: 'No plans yet',
      emptyMessage: 'Subscribe to a plan from the Browse tab to see it here.',
      errorMessage: 'Could not load your plans.',
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      itemBuilder: (context, subscription) =>
          SubscriptionCard(subscription: subscription),
    );
  }
}

class _BrowseTab extends ConsumerWidget {
  const _BrowseTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(activePackagesProvider);
    final subscriptions = ref.watch(clientSubscriptionsProvider).value;

    return RefreshIndicator(
      color: bos.brand,
      backgroundColor: bos.bgCard,
      onRefresh: () async {
        ref.invalidate(activePackagesProvider);
        ref.invalidate(clientSubscriptionsProvider);
      },
      child: async.when(
        loading: () => const Loader(),
        error: (error, _) => ErrorState(
          message: error is ApiException
              ? error.message
              : 'Could not load the plans on offer.',
          onRetry: () => ref.invalidate(activePackagesProvider),
        ),
        data: (packages) => packages.isEmpty
            ? const EmptyState(
                icon: Icons.card_membership_outlined,
                title: 'Nothing on offer',
                message: 'There are no plans to subscribe to right now.',
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                itemCount: packages.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PackageCard(
                    package: packages[i],
                    alreadyActive: subscriptions?.any(
                          (s) => s.packageId == packages[i].id && s.isActive,
                        ) ??
                        false,
                  ),
                ),
              ),
      ),
    );
  }
}

class _PackageCard extends ConsumerStatefulWidget {
  const _PackageCard({required this.package, required this.alreadyActive});

  final ServicePackage package;
  final bool alreadyActive;

  @override
  ConsumerState<_PackageCard> createState() => _PackageCardState();
}

class _PackageCardState extends ConsumerState<_PackageCard> {
  bool _subscribing = false;

  Future<void> _subscribe() async {
    setState(() => _subscribing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = ref.read(portalRepositoryProvider);
      final subscription = await repo.subscribeToPackage(widget.package.id);
      final url = await repo.initiatePackagePayment(subscription);
      final uri = Uri.tryParse(url);
      final launched = uri == null
          ? false
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
      ref.invalidate(clientSubscriptionsProvider);
      ref.invalidate(clientPackageSubscriptionsProvider);
      if (!launched) {
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Could not open the payment page.')),
          );
        }
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
        const SnackBar(content: Text('Could not start the subscription.')),
      );
    } finally {
      if (mounted) setState(() => _subscribing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final pkg = widget.package;
    final price = pkg.effectivePrice ?? pkg.packagePrice;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  pkg.name,
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (widget.alreadyActive)
                const StatusChip('APPROVED', label: 'Current plan', dense: true)
              else if (pkg.popular)
                StatusChip('SENT', label: 'Popular', dense: true),
            ],
          ),
          if (pkg.description != null && pkg.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              pkg.description!,
              style: TextStyle(color: bos.textSecondary, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                Fmt.money(price),
                style: TextStyle(
                  color: bos.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              if (pkg.billingCycle != null) ...[
                const SizedBox(width: 4),
                Text(
                  '/ ${Fmt.label(pkg.billingCycle!).toLowerCase()}',
                  style: TextStyle(color: bos.muted, fontSize: 12.5),
                ),
              ],
            ],
          ),
          if (pkg.requestQuota != null || pkg.deliveryDays != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (pkg.requestQuota != null)
                  _Meta(
                    icon: Icons.assignment_outlined,
                    text: '${pkg.requestQuota} requests',
                  ),
                if (pkg.requestQuota != null && pkg.deliveryDays != null)
                  const SizedBox(width: 12),
                if (pkg.deliveryDays != null)
                  _Meta(
                    icon: Icons.schedule_outlined,
                    text: '${pkg.deliveryDays}-day delivery',
                  ),
              ],
            ),
          ],
          if (!widget.alreadyActive) ...[
            const SizedBox(height: 12),
            LoadingButton(
              label: 'Subscribe & pay',
              loading: _subscribing,
              icon: Icons.arrow_forward_rounded,
              onPressed: _subscribe,
            ),
          ],
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: bos.muted),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: bos.muted, fontSize: 11.5)),
      ],
    );
  }
}
