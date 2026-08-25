import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/config_list.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import '../crm/crm_controllers.dart' show clientsProvider;
import '../crm/crm_models.dart' show Client;
import '../requests/new_package_sheet.dart' show showNewPackageSheet;
import '../requests/request_models.dart' show RequestPermissions;
import 'catalogue_form_sheets.dart';
import 'catalogue_models.dart';
import 'catalogue_repository.dart';

/// What the company sells.
///
/// Four tabs that describe one thing from four angles: the services on offer,
/// the templates they are built from, the packages that bundle them, and the
/// clients subscribed to those packages.
///
/// Each tab is gated on the permission its own endpoints check, so somebody
/// sees only what they could actually load.
class CatalogueScreen extends ConsumerWidget {
  const CatalogueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final permissions = ref.watch(permissionControllerProvider);

    if (!permissions.loaded && permissions.codes.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Catalogue')),
        body: const Loader(),
      );
    }

    final tabs = <({String label, Widget view, VoidCallback? create})>[
      if (permissions.has(CataloguePermissions.serviceView))
        (
          label: 'Services',
          view: const _ServicesTab(),
          create: permissions.has(CataloguePermissions.serviceCreate)
              ? () => showServiceSheet(context)
              : null,
        ),
      if (permissions.has(CataloguePermissions.templateView))
        (
          label: 'Templates',
          view: const _TemplatesTab(),
          create: permissions.has(CataloguePermissions.templateCreate)
              ? () => showTemplateSheet(context)
              : null,
        ),
      if (permissions.has(CataloguePermissions.packageView)) ...[
        (
          label: 'Packages',
          view: const _PackagesTab(),
          // Creating a package is the sheet already built on the requests
          // screen — same endpoint, same DTO, no reason to have two.
          create: () => showNewPackageSheet(context),
        ),
        (
          label: 'Subscriptions',
          view: const _SubscriptionsTab(),
          create: null,
        ),
      ],
    ];

    if (tabs.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Catalogue')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Not available to you',
          message:
              'The service catalogue needs administrator permissions. Your '
              'owner can grant them.',
        ),
      );
    }

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
                  title: const Text('Catalogue'),
                  bottom: TabBar(
                    isScrollable: tabs.length > 3,
                    tabAlignment: tabs.length > 3 ? TabAlignment.start : null,
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

// ── Services ──────────────────────────────────────────────────

class _ServicesTab extends ConsumerStatefulWidget {
  const _ServicesTab();

  @override
  ConsumerState<_ServicesTab> createState() => _ServicesTabState();
}

class _ServicesTabState extends ConsumerState<_ServicesTab> {
  int? _busyId;

  Future<void> _toggle(ServiceListing row) async {
    setState(() => _busyId = row.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated =
          await ref.read(catalogueRepositoryProvider).toggleService(row.id);
      ref.read(servicesProvider.notifier).apply(updated);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not change that service.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _delete(ServiceListing row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${row.name}?'),
        content: const Text(
          'It stops appearing in the catalogue. Requests already raised '
          'against it are unaffected. Retiring it instead keeps it where you '
          'can bring it back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Never mind'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).bos.danger,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyId = row.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(catalogueRepositoryProvider).deleteService(row.id);
      ref.read(servicesProvider.notifier).remove(row.id);
      messenger.showSnackBar(
        SnackBar(content: Text('${row.name} removed.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not remove that service.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(permissionControllerProvider);
    final canEdit = permissions.has(CataloguePermissions.serviceUpdate);
    final canDelete = permissions.has(CataloguePermissions.serviceDelete);

    return ConfigList<ServiceListing>(
      async: ref.watch(servicesProvider),
      onRefresh: ref.read(servicesProvider.notifier).refresh,
      emptyIcon: Icons.design_services_outlined,
      emptyTitle: 'Nothing on offer yet',
      emptyMessage:
          'Add the services clients can ask for. Each one carries its own '
          'price, turnaround and delivery options.',
      errorMessage: 'Could not load the services.',
      itemBuilder: (context, row) => ConfigRow(
        title: row.name,
        active: row.active,
        subtitle: [
          if (row.categoryName != null) row.categoryName!,
          row.deliveryLabel,
        ].join(' · '),
        trailingLabel: row.price == null
            ? null
            : '${Fmt.money(row.price)}'
                '${row.priceType == null || row.priceType == 'FIXED' ? '' : ' / ${Fmt.label(row.priceType!).toLowerCase()}'}',
        busy: _busyId == row.id,
        onEdit: canEdit ? () => showServiceSheet(context, existing: row) : null,
        onToggle: canEdit ? () => _toggle(row) : null,
        actions: [
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

// ── Templates ─────────────────────────────────────────────────

class _TemplatesTab extends ConsumerStatefulWidget {
  const _TemplatesTab();

  @override
  ConsumerState<_TemplatesTab> createState() => _TemplatesTabState();
}

class _TemplatesTabState extends ConsumerState<_TemplatesTab> {
  int? _busyId;

  Future<void> _delete(ServiceTemplate row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${row.name}?'),
        content: const Text(
          'Services already built from it keep everything they took. Only the '
          'template itself goes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Never mind'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).bos.danger,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyId = row.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(catalogueRepositoryProvider).deleteTemplate(row.id);
      ref.read(templatesProvider.notifier).remove(row.id);
      messenger.showSnackBar(SnackBar(content: Text('${row.name} removed.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not remove that template.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(permissionControllerProvider);
    final canEdit = permissions.has(CataloguePermissions.templateUpdate);
    final canDelete = permissions.has(CataloguePermissions.templateDelete);

    return ConfigList<ServiceTemplate>(
      async: ref.watch(templatesProvider),
      onRefresh: ref.read(templatesProvider.notifier).refresh,
      emptyIcon: Icons.dashboard_customize_outlined,
      emptyTitle: 'No templates yet',
      emptyMessage:
          'A template is a service definition you can reuse — its form fields, '
          'the documents it asks for, and the stages it runs through.',
      errorMessage: 'Could not load the templates.',
      itemBuilder: (context, row) => ConfigRow(
        title: row.name,
        active: row.active,
        subtitle: [
          if (row.categoryName != null) row.categoryName!,
          '${row.formFieldCount} fields',
          '${row.workflowStageCount} stages',
        ].join(' · '),
        trailingLabel:
            row.defaultPrice == null ? null : Fmt.money(row.defaultPrice),
        busy: _busyId == row.id,
        onEdit: canEdit ? () => showTemplateSheet(context, existing: row) : null,
        actions: [
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

// ── Packages ──────────────────────────────────────────────────

class _PackagesTab extends ConsumerStatefulWidget {
  const _PackagesTab();

  @override
  ConsumerState<_PackagesTab> createState() => _PackagesTabState();
}

class _PackagesTabState extends ConsumerState<_PackagesTab> {
  int? _busyId;

  Future<void> _toggle(ServicePackage row) async {
    setState(() => _busyId = row.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated =
          await ref.read(catalogueRepositoryProvider).togglePackage(row.id);
      ref.read(packagesProvider.notifier).apply(updated);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not change that package.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// Puts a client onto this package. Staff pass the client explicitly; there
  /// is no "current client" to fall back on.
  Future<void> _subscribe(ServicePackage row) async {
    final client = await _pickClient(context, ref);
    if (client == null || !mounted) return;

    setState(() => _busyId = row.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(catalogueRepositoryProvider)
          .subscribe(packageId: row.id, clientId: client.id);
      // The new subscription starts PENDING_PAYMENT, so the other tab is now
      // stale whether or not anybody is looking at it.
      await ref.read(subscriptionsProvider.notifier).refresh();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${client.headline} is on ${row.name}, awaiting payment.',
          ),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not start that subscription.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Packages are role-gated rather than permission-gated on the write side —
    // reaching this tab at all already means COMPANY_OWNER or EMPLOYEE.
    final canSubscribe =
        ref.watch(permissionControllerProvider).has(RequestPermissions.view);

    return ConfigList<ServicePackage>(
      async: ref.watch(packagesProvider),
      onRefresh: ref.read(packagesProvider.notifier).refresh,
      emptyIcon: Icons.inventory_2_outlined,
      emptyTitle: 'No packages yet',
      emptyMessage:
          'A package bundles services and sells them on a cycle, with an '
          'allowance of requests included.',
      errorMessage: 'Could not load the packages.',
      itemBuilder: (context, row) => ConfigRow(
        title: row.name,
        active: row.active,
        subtitle: [
          if (row.billingCycle != null) Fmt.label(row.billingCycle!),
          if (row.requestQuota != null)
            '${row.requestQuota} requests'
          else
            'Unlimited requests',
          if ((row.discountPercent ?? 0) > 0)
            '${Fmt.percent(row.discountPercent)} off',
        ].join(' · '),
        trailingLabel: Fmt.money(row.effectivePrice ?? row.packagePrice),
        busy: _busyId == row.id,
        onEdit: () => showPackageEditSheet(context, existing: row),
        onToggle: () => _toggle(row),
        actions: [
          if (canSubscribe && row.active)
            RowAction(
              label: 'Subscribe a client',
              onSelected: () => _subscribe(row),
            ),
        ],
      ),
    );
  }
}

// ── Subscriptions ─────────────────────────────────────────────

class _SubscriptionsTab extends ConsumerStatefulWidget {
  const _SubscriptionsTab();

  @override
  ConsumerState<_SubscriptionsTab> createState() => _SubscriptionsTabState();
}

class _SubscriptionsTabState extends ConsumerState<_SubscriptionsTab> {
  int? _busyId;

  /// Runs one of the four state changes and swaps the row with what comes back.
  Future<void> _act(
    PackageSubscription row,
    Future<PackageSubscription> Function() action,
    String failure,
  ) async {
    setState(() => _busyId = row.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await action();
      ref.read(subscriptionsProvider.notifier).apply(updated);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failure)));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _suspend(PackageSubscription row) async {
    final reason = await askForText(
      context,
      title: 'Pause this subscription?',
      message:
          'It stops counting down and the client cannot draw on it until you '
          'resume it.',
      label: 'Reason (optional)',
      action: 'Pause',
    );
    if (reason == null || !mounted) return;
    final repo = ref.read(catalogueRepositoryProvider);
    await _act(
      row,
      () => repo.suspendSubscription(row.id, reason),
      'Could not pause that subscription.',
    );
  }

  Future<void> _cancel(PackageSubscription row) async {
    final reason = await askForText(
      context,
      title: 'End this subscription?',
      message:
          'This is final — it cannot be resumed afterwards. The client would '
          'need a new subscription.',
      label: 'Reason (optional)',
      action: 'End it',
      destructive: true,
    );
    if (reason == null || !mounted) return;
    final repo = ref.read(catalogueRepositoryProvider);
    await _act(
      row,
      () => repo.cancelSubscription(row.id, reason),
      'Could not end that subscription.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final repo = ref.read(catalogueRepositoryProvider);

    return ConfigList<PackageSubscription>(
      async: ref.watch(subscriptionsProvider),
      onRefresh: ref.read(subscriptionsProvider.notifier).refresh,
      emptyIcon: Icons.card_membership_outlined,
      emptyTitle: 'Nobody is subscribed',
      emptyMessage:
          'Put a client on a package from the Packages tab and it appears '
          'here.',
      errorMessage: 'Could not load the subscriptions.',
      itemBuilder: (context, row) => _SubscriptionRow(
        subscription: row,
        busy: _busyId == row.id,
        onActivate: () => _act(
          row,
          () => repo.activateSubscription(row.id),
          'Could not confirm that payment.',
        ),
        onSuspend: () => _suspend(row),
        onReactivate: () => _act(
          row,
          () => repo.reactivateSubscription(row.id),
          'Could not resume that subscription.',
        ),
        onCancel: () => _cancel(row),
        muted: bos.muted,
      ),
    );
  }
}

/// A subscription reads differently from the configuration rows above — the
/// status and the allowance are the point, not the name — so it gets its own
/// row rather than being forced into [ConfigRow].
class _SubscriptionRow extends StatelessWidget {
  const _SubscriptionRow({
    required this.subscription,
    required this.busy,
    required this.onActivate,
    required this.onSuspend,
    required this.onReactivate,
    required this.onCancel,
    required this.muted,
  });

  final PackageSubscription subscription;
  final bool busy;
  final VoidCallback onActivate;
  final VoidCallback onSuspend;
  final VoidCallback onReactivate;
  final VoidCallback onCancel;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final usage = subscription.usage;

    // What can be done depends entirely on where it is. A settled subscription
    // offers nothing at all rather than actions that would be refused.
    final actions = <RowAction>[
      if (subscription.status == SubscriptionStatus.pendingPayment)
        RowAction(label: 'Confirm payment', onSelected: onActivate),
      if (subscription.isActive)
        RowAction(label: 'Pause', onSelected: onSuspend),
      if (subscription.isSuspended)
        RowAction(label: 'Resume', onSelected: onReactivate),
      if (!subscription.isSettled)
        RowAction(label: 'End it', destructive: true, onSelected: onCancel),
    ];

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
                        subscription.clientName ?? 'Unnamed client',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subscription.packageName ?? 'Package',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusChip(subscription.status, dense: true),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (actions.isNotEmpty)
                  PopupMenuButton<int>(
                    onSelected: (index) => actions[index].onSelected(),
                    itemBuilder: (context) => [
                      for (var i = 0; i < actions.length; i++)
                        PopupMenuItem(
                          value: i,
                          child: Text(
                            actions[i].label,
                            style: actions[i].destructive
                                ? TextStyle(color: bos.danger)
                                : null,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (usage != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: usage,
                  minHeight: 5,
                  backgroundColor: bos.borderLight,
                  color: usage >= 1 ? bos.danger : bos.brand,
                ),
              ),
              const SizedBox(height: 6),
            ],
            Text(
              [
                if (usage == null)
                  '${subscription.requestsUsed} requests used'
                else
                  '${subscription.requestsUsed} of '
                      '${subscription.requestQuota} used',
                if (subscription.nextBillingDate != null)
                  'renews ${Fmt.date(subscription.nextBillingDate)}'
                else if (subscription.endDate != null)
                  'ends ${Fmt.date(subscription.endDate)}',
              ].join(' · '),
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Picks a client for a subscription.
///
/// Reads the CRM clients list, which loads its own first page. Deliberately
/// simple — a company has a manageable number of clients and the list is
/// already sorted; anything larger belongs on the web.
Future<Client?> _pickClient(BuildContext context, WidgetRef ref) {
  // Nudges the list into loading if nothing has read it yet this session.
  ref.read(clientsProvider.notifier);

  return showModalBottomSheet<Client>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      final bos = Theme.of(sheetContext).bos;
      return Consumer(
        builder: (context, ref, _) {
          final clients = ref.watch(clientsProvider);
          return SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Which client?',
                          style: TextStyle(
                            color: bos.text,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: clients.when(
                    loading: () => const Loader(),
                    error: (error, _) => ErrorState(
                      message: error is ApiException
                          ? error.message
                          : 'Could not load the clients.',
                      onRetry: ref.read(clientsProvider.notifier).refresh,
                    ),
                    data: (state) {
                      if (state.items.isEmpty) {
                        return const EmptyState(
                          icon: Icons.people_outline_rounded,
                          title: 'No clients yet',
                          message:
                              'Add a client in CRM before subscribing them to '
                              'a package.',
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: state.items.length,
                        itemBuilder: (context, index) {
                          final client = state.items[index];
                          return ListTile(
                            title: Text(
                              client.headline,
                              style: TextStyle(color: bos.text, fontSize: 14),
                            ),
                            subtitle: client.email == null
                                ? null
                                : Text(
                                    client.email!,
                                    style: TextStyle(
                                      color: bos.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                            onTap: () => Navigator.pop(sheetContext, client),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
