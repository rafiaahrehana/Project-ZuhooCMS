import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/config_list.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import '../../shared/widgets/stat_card.dart';
import '../reports/report_models.dart' show Ageing;
import 'payables_models.dart';
import 'payables_repository.dart';
import 'payables_sheets.dart';

/// What the company owes, and to whom.
class PayablesScreen extends ConsumerWidget {
  const PayablesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final permissions = ref.watch(permissionControllerProvider);

    if (!permissions.loaded && permissions.codes.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Payables')),
        body: const Loader(),
      );
    }

    final tabs = <({String label, Widget view, VoidCallback? create})>[
      if (permissions.has(PayablesPermissions.billView)) ...[
        (
          label: 'Bills',
          view: const _BillsTab(),
          create: permissions.has(PayablesPermissions.billCreate)
              ? () => showBillSheet(context)
              : null,
        ),
        (label: 'Ageing', view: const _AgeingTab(), create: null),
      ],
      if (permissions.has(PayablesPermissions.vendorView))
        (
          label: 'Vendors',
          view: const _VendorsTab(),
          create: permissions.has(PayablesPermissions.vendorCreate)
              ? () => showVendorSheet(context)
              : null,
        ),
    ];

    if (tabs.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Payables')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Not available to you',
          message: 'Accounts payable needs the vendor permissions.',
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
                  title: const Text('Payables'),
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

// ── Bills ─────────────────────────────────────────────────────

class _BillsTab extends ConsumerStatefulWidget {
  const _BillsTab();

  @override
  ConsumerState<_BillsTab> createState() => _BillsTabState();
}

class _BillsTabState extends ConsumerState<_BillsTab> {
  int? _busyId;

  Future<void> _act(
    VendorBill bill,
    Future<VendorBill> Function(PayablesRepository repo) action,
    String success,
    String failure,
  ) async {
    setState(() => _busyId = bill.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await action(ref.read(payablesRepositoryProvider));
      ref.read(billsProvider.notifier).apply(updated);
      // Paying and approving both move what is owed.
      ref.invalidate(apAgeingProvider);
      await ref.read(vendorsProvider.notifier).refresh();
      messenger.showSnackBar(SnackBar(content: Text(success)));
    } on ApiException catch (e) {
      // "a different user must approve it", "Payment amount exceeds the
      // outstanding balance (…)" — both worth reading as written.
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failure)));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _pay(VendorBill bill) async {
    final amount = await askForPayment(context, bill: bill);
    if (amount == null || !mounted) return;
    await _act(
      bill,
      (repo) => repo.payBill(bill.id, amount),
      'Payment recorded.',
      'Could not record that payment.',
    );
  }

  Future<void> _cancel(VendorBill bill) async {
    final confirmed = await confirmAction(
      context,
      title: 'Cancel ${bill.billNumber}?',
      message:
          'The bill stops counting towards what is owed. It cannot be brought '
          'back — a real one has to be entered again.',
      action: 'Cancel it',
    );
    if (!confirmed || !mounted) return;
    await _act(
      bill,
      (repo) => repo.cancelBill(bill.id),
      'Cancelled.',
      'Could not cancel that bill.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(permissionControllerProvider);
    final filter = ref.watch(billStatusFilterProvider);

    return ConfigList<VendorBill>(
      async: ref.watch(billsProvider),
      onRefresh: ref.read(billsProvider.notifier).refresh,
      emptyIcon: Icons.receipt_outlined,
      emptyTitle: filter == null ? 'No bills yet' : 'None like that',
      emptyMessage:
          'A bill is one invoice from a vendor. It is entered, approved by '
          'somebody else, and paid down until nothing is left.',
      errorMessage: 'Could not load the bills.',
      header: FilterBar(
        selected: filter,
        onSelected: ref.read(billStatusFilterProvider.notifier).set,
        options: [
          (value: null, label: 'All'),
          for (final status in BillStatus.all)
            (value: status, label: Fmt.label(status)),
        ],
      ),
      itemBuilder: (context, bill) => _BillCard(
        bill: bill,
        busy: _busyId == bill.id,
        onApprove: bill.canApprove &&
                permissions.has(PayablesPermissions.billApprove)
            ? () => _act(
                  bill,
                  (repo) => repo.approveBill(bill.id),
                  'Approved.',
                  'Could not approve that bill.',
                )
            : null,
        onPay: bill.canPay && permissions.has(PayablesPermissions.billPayment)
            ? () => _pay(bill)
            : null,
        onCancel:
            bill.canCancel && permissions.has(PayablesPermissions.billCancel)
                ? () => _cancel(bill)
                : null,
      ),
    );
  }
}

class _BillCard extends StatelessWidget {
  const _BillCard({
    required this.bill,
    required this.busy,
    this.onApprove,
    this.onPay,
    this.onCancel,
  });

  final VendorBill bill;
  final bool busy;
  final VoidCallback? onApprove;
  final VoidCallback? onPay;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final paid = bill.paidShare;

    final actions = <RowAction>[
      if (onApprove != null) RowAction(label: 'Approve', onSelected: onApprove!),
      if (onPay != null) RowAction(label: 'Record a payment', onSelected: onPay!),
      if (onCancel != null)
        RowAction(label: 'Cancel', destructive: true, onSelected: onCancel!),
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
                        bill.vendorName ?? 'Vendor ${bill.vendorId}',
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
                          bill.billNumber,
                          if (bill.vendorReference != null)
                            bill.vendorReference!,
                          if (bill.dueDate != null)
                            'due ${Fmt.date(bill.dueDate)}',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                      Fmt.money(bill.totalAmount),
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    StatusChip(bill.status, dense: true),
                  ],
                ),
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
            if (paid != null && bill.paidAmount > 0) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: paid,
                  minHeight: 5,
                  backgroundColor: bos.borderLight,
                  color: bos.brand,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${Fmt.money(bill.paidAmount)} paid, '
                '${Fmt.money(bill.balanceAmount)} left',
                style: TextStyle(color: bos.muted, fontSize: 11.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── AP ageing ─────────────────────────────────────────────────

class _AgeingTab extends ConsumerWidget {
  const _AgeingTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(apAgeingProvider);

    return RefreshIndicator(
      color: bos.brand,
      backgroundColor: bos.bgCard,
      onRefresh: () async => ref.invalidate(apAgeingProvider),
      child: async.when(
        loading: () => const Loader(),
        error: (error, _) => ErrorState(
          message: error is ApiException
              ? error.message
              : 'Could not load what is owed.',
          onRetry: () => ref.invalidate(apAgeingProvider),
        ),
        data: (report) => _Ageing(report: report),
      ),
    );
  }
}

class _Ageing extends StatelessWidget {
  const _Ageing({required this.report});

  final Ageing report;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final total = report.totalOutstanding;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'Owed out',
                value: Fmt.money(total),
                icon: Icons.outbox_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                label: 'Overdue',
                value: Fmt.money(report.overdue),
                icon: Icons.schedule_rounded,
                tone: report.overdue > 0 ? bos.danger : null,
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
                              style: TextStyle(color: bos.text, fontSize: 12.5),
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
                          value: total <= 0 ? 0 : bucket.amount / total,
                          minHeight: 4,
                          backgroundColor: bos.borderLight,
                          color:
                              bucket.label == 'Current' ? bos.brand : bos.danger,
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
          SectionHeader('Bills', icon: Icons.receipt_outlined),
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
                            line.counterparty ?? 'Vendor',
                            style: TextStyle(
                              color: bos.text,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (line.reference != null) line.reference!,
                              line.isOverdue
                                  ? '${line.daysOverdue} days late'
                                  : 'due ${Fmt.date(line.dueDate)}',
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: line.isOverdue ? bos.danger : bos.muted,
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
        Text(
          'As at ${Fmt.date(report.asOfDate)}',
          style: TextStyle(color: bos.muted, fontSize: 11.5),
        ),
      ],
    );
  }
}

// ── Vendors ───────────────────────────────────────────────────

class _VendorsTab extends ConsumerStatefulWidget {
  const _VendorsTab();

  @override
  ConsumerState<_VendorsTab> createState() => _VendorsTabState();
}

class _VendorsTabState extends ConsumerState<_VendorsTab> {
  int? _busyId;

  Future<void> _toggle(Vendor vendor) async {
    setState(() => _busyId = vendor.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated =
          await ref.read(payablesRepositoryProvider).toggleVendor(vendor.id);
      ref.read(vendorsProvider.notifier).apply(updated);
      ref.invalidate(activeVendorsProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not change that vendor.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _delete(Vendor vendor) async {
    final confirmed = await confirmAction(
      context,
      title: 'Remove ${vendor.name}?',
      message: vendor.owesMoney
          ? '${Fmt.money(vendor.outstandingBalance)} is still owed to them. '
              'Retiring them instead keeps the bills where they are.'
          : 'Bills already entered against them stay on the record.',
      action: 'Remove',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyId = vendor.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(payablesRepositoryProvider).deleteVendor(vendor.id);
      ref.read(vendorsProvider.notifier).remove(vendor.id);
      ref.invalidate(activeVendorsProvider);
      messenger.showSnackBar(SnackBar(content: Text('${vendor.name} removed.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not remove that vendor.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(permissionControllerProvider);
    final canEdit = permissions.has(PayablesPermissions.vendorUpdate);
    final canDelete = permissions.has(PayablesPermissions.vendorDelete);

    return ConfigList<Vendor>(
      async: ref.watch(vendorsProvider),
      onRefresh: ref.read(vendorsProvider.notifier).refresh,
      emptyIcon: Icons.storefront_outlined,
      emptyTitle: 'No vendors yet',
      emptyMessage:
          'A vendor is somebody the company buys from. Bills are entered '
          'against them and paid down over time.',
      errorMessage: 'Could not load the vendors.',
      itemBuilder: (context, vendor) => ConfigRow(
        title: vendor.name,
        active: vendor.active,
        subtitle: [
          if (vendor.contactPerson != null) vendor.contactPerson!,
          if (vendor.paymentTerms != null) vendor.paymentTerms!,
          if (vendor.email != null) vendor.email!,
        ].join(' · '),
        trailingLabel:
            vendor.owesMoney ? Fmt.money(vendor.outstandingBalance) : null,
        busy: _busyId == vendor.id,
        onEdit:
            canEdit ? () => showVendorSheet(context, existing: vendor) : null,
        onToggle: canEdit ? () => _toggle(vendor) : null,
        actions: [
          if (canDelete)
            RowAction(
              label: 'Remove',
              destructive: true,
              onSelected: () => _delete(vendor),
            ),
        ],
      ),
    );
  }
}
