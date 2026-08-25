import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/config_list.dart';
import '../../shared/widgets/date_field.dart';
import '../../shared/widgets/form_sheet.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import 'assets_periods_models.dart';
import 'assets_periods_repository.dart';

/// Closing the books, and what the company owns.
///
/// Two jobs that only come up at month end, which is why they share a screen
/// rather than each having one.
class ClosingScreen extends ConsumerWidget {
  const ClosingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final permissions = ref.watch(permissionControllerProvider);

    if (!permissions.loaded && permissions.codes.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Month end')),
        body: const Loader(),
      );
    }

    final tabs = <({String label, Widget view, VoidCallback? create})>[
      if (permissions.has(ClosingPermissions.periodView))
        (label: 'Periods', view: const _PeriodsTab(), create: null),
      if (permissions.has(ClosingPermissions.assetView))
        (
          label: 'Fixed assets',
          view: const _AssetsTab(),
          create: permissions.has(ClosingPermissions.assetManage)
              ? () => showFixedAssetSheet(context)
              : null,
        ),
    ];

    if (tabs.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Month end')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Not available to you',
          message:
              'Closing periods and managing fixed assets need the accounting '
              'permissions.',
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
                  title: const Text('Month end'),
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

// ── Periods ───────────────────────────────────────────────────

class _PeriodsTab extends ConsumerStatefulWidget {
  const _PeriodsTab();

  @override
  ConsumerState<_PeriodsTab> createState() => _PeriodsTabState();
}

class _PeriodsTabState extends ConsumerState<_PeriodsTab> {
  int? _busyId;
  bool _closingYear = false;

  Future<void> _toggle(AccountingPeriod period) async {
    final closing = period.isOpen;
    if (closing) {
      final confirmed = await confirmAction(
        context,
        title: 'Close ${period.title}?',
        message:
            'Nothing more can be posted into it afterwards. It can be reopened '
            'if something was missed.',
        action: 'Close it',
        destructive: false,
      );
      if (!confirmed || !mounted) return;
    }

    setState(() => _busyId = period.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = ref.read(closingRepositoryProvider);
      final updated = closing
          ? await repo.closePeriod(period.id)
          : await repo.reopenPeriod(period.id);
      ref.read(periodsProvider.notifier).apply(updated);
      // The year's open and closed counts have moved.
      ref.invalidate(fiscalYearsProvider);
      messenger.showSnackBar(
        SnackBar(content: Text(closing ? 'Closed.' : 'Reopened.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            closing ? 'Could not close that period.' : 'Could not reopen it.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _closeYear(FiscalYear year) async {
    final confirmed = await confirmAction(
      context,
      title: 'Close ${year.title}?',
      message:
          'Net income rolls into retained earnings and the year is shut. Until '
          'this is done a balance sheet for the next year will not balance.',
      action: 'Close the year',
      destructive: false,
    );
    if (!confirmed || !mounted) return;

    setState(() => _closingYear = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(closingRepositoryProvider)
          .closeFiscalYear(year.fiscalYear);
      ref.invalidate(fiscalYearsProvider);
      await ref.read(periodsProvider.notifier).refresh();
      messenger.showSnackBar(SnackBar(content: Text('${year.title} closed.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not close that year.')),
      );
    } finally {
      if (mounted) setState(() => _closingYear = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final canClose = ref
        .watch(permissionControllerProvider)
        .has(ClosingPermissions.periodClose);
    final selected = ref.watch(selectedFiscalYearProvider);
    final years = ref.watch(fiscalYearsProvider).value ?? const <FiscalYear>[];

    final matching = years.where((y) => y.fiscalYear == selected);
    final year = matching.isEmpty ? null : matching.first;

    return ConfigList<AccountingPeriod>(
      async: ref.watch(periodsProvider),
      onRefresh: ref.read(periodsProvider.notifier).refresh,
      emptyIcon: Icons.calendar_month_outlined,
      emptyTitle: 'No periods for $selected',
      emptyMessage:
          'Periods are created with the fiscal year. Pick another year, or set '
          'one up on the web.',
      errorMessage: 'Could not load the periods.',
      header: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (years.isNotEmpty)
              FilterBar(
                selected: '$selected',
                onSelected: (value) {
                  final parsed = int.tryParse(value ?? '');
                  if (parsed != null) {
                    ref.read(selectedFiscalYearProvider.notifier).set(parsed);
                  }
                },
                options: [
                  for (final y in years)
                    (value: '${y.fiscalYear}', label: y.title),
                ],
              ),
            if (year != null) ...[
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${year.closedPeriods} of ${year.totalPeriods} '
                            'periods closed',
                            style: TextStyle(
                              color: bos.text,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (year.startDate != null)
                          Text(
                            '${Fmt.dateShort(year.startDate)} — '
                            '${Fmt.dateShort(year.endDate)}',
                            style: TextStyle(color: bos.muted, fontSize: 11.5),
                          ),
                      ],
                    ),
                    if (year.progress != null) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: year.progress,
                          minHeight: 5,
                          backgroundColor: bos.borderLight,
                          color: bos.brand,
                        ),
                      ),
                    ],
                    if (canClose && year.fullyClosed) ...[
                      const SizedBox(height: 12),
                      LoadingButton(
                        label: 'Close ${year.title}',
                        loading: _closingYear,
                        icon: Icons.lock_outline_rounded,
                        onPressed: () => _closeYear(year),
                      ),
                    ] else if (canClose) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Every period has to be closed before the year can be.',
                        style: TextStyle(color: bos.muted, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
      itemBuilder: (context, period) => ConfigRow(
        title: period.title,
        active: period.isOpen,
        inactiveLabel: 'Closed',
        subtitle: [
          if (period.startDate != null)
            '${Fmt.dateShort(period.startDate)} — '
                '${Fmt.dateShort(period.endDate)}',
          if (period.closedBy != null && !period.isOpen)
            'closed by ${period.closedBy}',
          // A reopened period is worth calling out: figures somebody may have
          // reported on have since been able to move again.
          if (period.wasReopened) 'reopened',
        ].join(' · '),
        busy: _busyId == period.id,
        actions: [
          if (canClose)
            RowAction(
              label: period.isOpen ? 'Close it' : 'Reopen it',
              destructive: !period.isOpen,
              onSelected: () => _toggle(period),
            ),
        ],
      ),
    );
  }
}

// ── Fixed assets ──────────────────────────────────────────────

class _AssetsTab extends ConsumerStatefulWidget {
  const _AssetsTab();

  @override
  ConsumerState<_AssetsTab> createState() => _AssetsTabState();
}

class _AssetsTabState extends ConsumerState<_AssetsTab> {
  int? _busyId;
  bool _running = false;

  Future<void> _dispose(FixedAsset asset) async {
    final confirmed = await confirmAction(
      context,
      title: 'Dispose of ${asset.name}?',
      message: asset.bookValue == null || asset.bookValue! <= 0
          ? 'It is already fully written down, so this only takes it off the '
              'register.'
          : '${Fmt.money(asset.bookValue)} is still on the books against it. '
              'Disposing writes that off. There is no undoing it.',
      action: 'Dispose of it',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyId = asset.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated =
          await ref.read(closingRepositoryProvider).disposeAsset(asset.id);
      ref.read(fixedAssetsProvider.notifier).apply(updated);
      messenger.showSnackBar(SnackBar(content: Text('${asset.name} disposed.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not dispose of that asset.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// Depreciates everything for one month.
  ///
  /// Defaults to last month, because depreciation is run after a month ends
  /// rather than during it.
  Future<void> _runDepreciation() async {
    final lastMonth = DateTime(DateTime.now().year, DateTime.now().month - 1);
    final confirmed = await confirmAction(
      context,
      title: 'Run depreciation for ${Fmt.monthYear(lastMonth.month, lastMonth.year)}?',
      message:
          'Every active asset is written down by one month and a journal entry '
          'is posted. Running the same month twice is refused.',
      action: 'Run it',
      destructive: false,
    );
    if (!confirmed || !mounted) return;

    setState(() => _running = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final run = await ref
          .read(closingRepositoryProvider)
          .runDepreciation(lastMonth.year, lastMonth.month);
      await ref.read(fixedAssetsProvider.notifier).refresh();
      ref.invalidate(depreciationRunsProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${run.assetsDepreciated} assets written down by '
            '${Fmt.money(run.totalAmount)}.',
          ),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not run depreciation.')),
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final canManage = ref
        .watch(permissionControllerProvider)
        .has(ClosingPermissions.assetManage);
    final runs =
        ref.watch(depreciationRunsProvider).value ?? const <DepreciationRun>[];

    return ConfigList<FixedAsset>(
      async: ref.watch(fixedAssetsProvider),
      onRefresh: ref.read(fixedAssetsProvider.notifier).refresh,
      emptyIcon: Icons.inventory_outlined,
      emptyTitle: 'Nothing on the register',
      emptyMessage:
          'A fixed asset is something the company owns that loses value over '
          'time — a vehicle, a machine, a fit-out.',
      errorMessage: 'Could not load the fixed assets.',
      header: !canManage
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (runs.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          'Last run ${Fmt.monthYear(runs.first.month, runs.first.year)} — '
                          '${runs.first.assetsDepreciated} assets, '
                          '${Fmt.money(runs.first.totalAmount)}.',
                          style: TextStyle(color: bos.muted, fontSize: 12.5),
                        ),
                      ),
                    LoadingButton(
                      label: 'Run monthly depreciation',
                      loading: _running,
                      icon: Icons.trending_down_rounded,
                      onPressed: _runDepreciation,
                    ),
                  ],
                ),
              ),
            ),
      itemBuilder: (context, asset) => _AssetCard(
        asset: asset,
        busy: _busyId == asset.id,
        onDispose:
            canManage && asset.canDispose ? () => _dispose(asset) : null,
      ),
    );
  }
}

class _AssetCard extends StatelessWidget {
  const _AssetCard({required this.asset, required this.busy, this.onDispose});

  final FixedAsset asset;
  final bool busy;
  final VoidCallback? onDispose;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final written = asset.depreciated;
    final months = asset.monthsRemaining;

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
                        asset.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: asset.isDisposed ? bos.muted : bos.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (asset.assetTag != null) asset.assetTag!,
                          if (asset.category != null) asset.category!,
                          if (asset.acquisitionDate != null)
                            'from ${Fmt.dateShort(asset.acquisitionDate)}',
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
                      Fmt.money(asset.bookValue ?? asset.cost),
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    StatusChip(asset.status, dense: true),
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
                else if (onDispose != null)
                  PopupMenuButton<String>(
                    onSelected: (_) => onDispose!(),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'dispose',
                        child: Text(
                          'Dispose of it',
                          style: TextStyle(color: bos.danger),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            if (written != null && !asset.isDisposed) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: written,
                  minHeight: 5,
                  backgroundColor: bos.borderLight,
                  color: bos.brand,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                [
                  '${Fmt.money(asset.accumulatedDepreciation)} written off of '
                      '${Fmt.money(asset.cost)}',
                  if (months != null)
                    months == 0
                        ? 'fully written down'
                        : months == 1
                            ? '1 month to go'
                            : '$months months to go',
                ].join(' · '),
                style: TextStyle(color: bos.muted, fontSize: 11.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Adding an asset ───────────────────────────────────────────

Future<void> showFixedAssetSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _FixedAssetSheet(),
  );
}

class _FixedAssetSheet extends ConsumerStatefulWidget {
  const _FixedAssetSheet();

  @override
  ConsumerState<_FixedAssetSheet> createState() => _FixedAssetSheetState();
}

class _FixedAssetSheetState extends ConsumerState<_FixedAssetSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _tag = TextEditingController();
  final _category = TextEditingController();
  final _cost = TextEditingController();
  final _salvage = TextEditingController();
  final _life = TextEditingController(text: '60');
  final _notes = TextEditingController();

  DateTime? _acquired = DateTime.now();
  bool _postToLedger = true;

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _name,
      _tag,
      _category,
      _cost,
      _salvage,
      _life,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  FixedAssetRequest? get _request {
    final cost = double.tryParse(_cost.text.trim());
    final life = int.tryParse(_life.text.trim());
    final acquired = _acquired;
    if (cost == null || life == null || acquired == null) return null;
    return FixedAssetRequest(
      name: _name.text,
      cost: cost,
      usefulLifeMonths: life,
      acquisitionDate: Fmt.isoDate(acquired),
      assetTag: _tag.text,
      category: _category.text,
      salvageValue: double.tryParse(_salvage.text.trim()),
      notes: _notes.text,
      postPurchaseToLedger: _postToLedger,
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final request = _request;
    if (request == null) {
      setState(() => _error = 'Fill in the cost, the life and the date.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(closingRepositoryProvider).createAsset(request);
      await ref.read(fixedAssetsProvider.notifier).refresh();
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Added to the register.')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not add that asset.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final request = _request;

    return FormSheetFrame(
      title: 'New fixed asset',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'Add it',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        TextFormField(
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'What it is',
            prefixIcon: Icon(Icons.inventory_outlined),
          ),
          validator: (value) =>
              (value?.trim().isEmpty ?? true) ? 'A name is required.' : null,
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _tag,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Asset tag'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _category,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Category'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _cost,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Cost'),
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  final parsed = double.tryParse(value?.trim() ?? '');
                  if (parsed == null) return 'A cost is required.';
                  return parsed <= 0 ? 'More than zero.' : null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _salvage,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Scrap value'),
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) return null;
                  final parsed = double.tryParse(trimmed);
                  if (parsed == null) return 'A number.';
                  return parsed < 0 ? 'Zero or more.' : null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _life,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Useful life, in months',
            prefixIcon: Icon(Icons.timelapse_rounded),
          ),
          onChanged: (_) => setState(() {}),
          validator: (value) {
            final parsed = int.tryParse(value?.trim() ?? '');
            if (parsed == null) return 'A number of months is required.';
            return parsed < 1 ? 'At least one month.' : null;
          },
        ),
        if (request != null && request.monthlyDepreciation > 0) ...[
          const SizedBox(height: 8),
          // A life in months is hard to picture; a monthly figure is not.
          Text(
            '${Fmt.money(request.monthlyDepreciation)} written off each month.',
            style: TextStyle(color: bos.muted, fontSize: 12.5),
          ),
        ],
        const SizedBox(height: 16),
        DateField(
          label: 'Acquired',
          value: _acquired,
          clearable: false,
          lastDate: DateTime.now(),
          onChanged: (value) => setState(() => _acquired = value),
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          value: _postToLedger,
          onChanged: (value) => setState(() => _postToLedger = value),
          title: Text(
            'Post the purchase to the ledger',
            style: TextStyle(color: bos.text, fontSize: 14),
          ),
          subtitle: Text(
            'Off if it was already recorded as an expense or a bill',
            style: TextStyle(color: bos.muted, fontSize: 11.5),
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _notes,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }
}
