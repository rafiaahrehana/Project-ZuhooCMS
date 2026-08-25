import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/config_list.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import 'accounting_models.dart';
import 'accounting_repository.dart';
import 'accounting_sheets.dart';

/// The books: accounts, entries, and the ledger they land in.
///
/// Three tabs in the order things move through them. Nothing in the ledger tab
/// can be edited — that is the point of a ledger — so it reads rather than
/// acts, apart from ticking a line off against a bank statement.
class AccountingScreen extends ConsumerWidget {
  const AccountingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final permissions = ref.watch(permissionControllerProvider);

    if (!permissions.loaded && permissions.codes.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Books')),
        body: const Loader(),
      );
    }

    final tabs = <({String label, Widget view, VoidCallback? create})>[
      if (permissions.has(AccountingPermissions.accountView))
        (
          label: 'Accounts',
          view: const _AccountsTab(),
          create: permissions.has(AccountingPermissions.accountCreate)
              ? () => showAccountSheet(context)
              : null,
        ),
      if (permissions.has(AccountingPermissions.entryView))
        (
          label: 'Entries',
          view: const _EntriesTab(),
          create: permissions.has(AccountingPermissions.entryCreate)
              ? () => showJournalEntrySheet(context)
              : null,
        ),
      if (permissions.has(AccountingPermissions.ledgerView))
        (label: 'Ledger', view: const _LedgerTab(), create: null),
    ];

    if (tabs.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Books')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Not available to you',
          message:
              'The books need the accounting permissions. Expenses and invoices '
              'are on the Finance screen.',
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
                  title: const Text('Books'),
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

// ── Chart of accounts ─────────────────────────────────────────

class _AccountsTab extends ConsumerStatefulWidget {
  const _AccountsTab();

  @override
  ConsumerState<_AccountsTab> createState() => _AccountsTabState();
}

class _AccountsTabState extends ConsumerState<_AccountsTab> {
  int? _busyId;

  Future<void> _delete(Account account) async {
    final confirmed = await confirmAction(
      context,
      title: 'Remove ${account.accountName}?',
      message:
          'Only possible while nothing has ever been posted to it. Once the '
          'ledger has an entry against an account, it stays for good.',
      action: 'Remove',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyId = account.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(accountingRepositoryProvider).deleteAccount(account.id);
      ref.read(accountsProvider.notifier).remove(account.id);
      ref.invalidate(postableAccountsProvider);
      messenger.showSnackBar(
        SnackBar(content: Text('${account.accountName} removed.')),
      );
    } on ApiException catch (e) {
      // "Cannot delete account with existing ledger entries" is exactly what
      // somebody needs to read here.
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not remove that account.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(permissionControllerProvider);
    final canEdit = permissions.has(AccountingPermissions.accountUpdate);
    final canDelete = permissions.has(AccountingPermissions.accountDelete);
    final filter = ref.watch(accountTypeFilterProvider);

    return ConfigList<Account>(
      async: ref.watch(accountsProvider),
      onRefresh: ref.read(accountsProvider.notifier).refresh,
      emptyIcon: Icons.account_tree_outlined,
      emptyTitle: filter == null ? 'No accounts yet' : 'None of that type',
      emptyMessage:
          'The chart of accounts is the list of buckets everything is posted '
          'to. Nothing can be recorded until there is one.',
      errorMessage: 'Could not load the chart of accounts.',
      header: FilterBar(
        selected: filter,
        onSelected: ref.read(accountTypeFilterProvider.notifier).set,
        options: [
          (value: null, label: 'All'),
          for (final type in accountTypes)
            (value: type, label: Fmt.label(type)),
        ],
      ),
      itemBuilder: (context, account) => ConfigRow(
        title: '${account.accountCode}  ${account.accountName}',
        active: account.active,
        subtitle: [
          Fmt.label(account.type),
          if (account.isHeaderAccount)
            'heading'
          else if (!account.allowDirectPosting)
            'no direct posting',
          if (account.isBankAccount) 'bank',
        ].join(' · '),
        trailingLabel:
            account.balance == null ? null : Fmt.money(account.balance),
        busy: _busyId == account.id,
        onEdit:
            canEdit ? () => showAccountSheet(context, existing: account) : null,
        actions: [
          // Offered only when the ledger tab exists — it is always the last
          // one, so jumping to it is safe once we know it is there.
          if (permissions.has(AccountingPermissions.ledgerView))
            RowAction(
              label: 'Ledger for this account',
              onSelected: () {
                ref.read(ledgerAccountFilterProvider.notifier).set(account.id);
                final controller = DefaultTabController.of(context);
                controller.animateTo(controller.length - 1);
              },
            ),
          if (canDelete)
            RowAction(
              label: 'Remove',
              destructive: true,
              onSelected: () => _delete(account),
            ),
        ],
      ),
    );
  }
}

// ── Journal entries ───────────────────────────────────────────

class _EntriesTab extends ConsumerWidget {
  const _EntriesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ConfigList<JournalEntry>(
      async: ref.watch(journalEntriesProvider),
      onRefresh: ref.read(journalEntriesProvider.notifier).refresh,
      emptyIcon: Icons.receipt_long_outlined,
      emptyTitle: 'No entries yet',
      emptyMessage:
          'A journal entry proposes a set of debits and credits. It is drafted, '
          'approved by somebody else, and only then posted to the ledger.',
      errorMessage: 'Could not load the journal entries.',
      itemBuilder: (context, entry) => _EntryRow(entry: entry),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final JournalEntry entry;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        onTap: () => JournalEntryScreen.open(context, id: entry.id),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.journalEntryNumber,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: bos.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (entry.isReversal) ...[
                        const SizedBox(width: 6),
                        Text(
                          'reversal',
                          style: TextStyle(color: bos.muted, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                  if (entry.description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.description!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: bos.muted, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    Fmt.date(entry.entryDate),
                    style: TextStyle(color: bos.muted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  Fmt.money(entry.amount),
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                StatusChip(entry.status, dense: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One entry, its legs, and what can still be done to it.
class JournalEntryScreen extends ConsumerStatefulWidget {
  const JournalEntryScreen({super.key, required this.id});

  final int id;

  static void open(BuildContext context, {required int id}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => JournalEntryScreen(id: id)),
    );
  }

  @override
  ConsumerState<JournalEntryScreen> createState() => _JournalEntryScreenState();
}

class _JournalEntryScreenState extends ConsumerState<JournalEntryScreen> {
  bool _busy = false;

  Future<void> _act(
    Future<void> Function(AccountingRepository repo) action,
    String success,
    String failure, {
    bool pop = false,
  }) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await action(ref.read(accountingRepositoryProvider));
      ref.invalidate(journalEntryProvider(widget.id));
      await ref.read(journalEntriesProvider.notifier).refresh();
      // Posting and reversing both move the ledger and every account balance.
      ref.invalidate(ledgerProvider);
      await ref.read(accountsProvider.notifier).refresh();
      messenger.showSnackBar(SnackBar(content: Text(success)));
      if (pop && mounted) navigator.pop();
    } on ApiException catch (e) {
      // Every guard on this endpoint has a written message — "a different user
      // must approve it", "must be approved before posting", "only posted
      // entries can be reversed" — and each is worth showing verbatim.
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failure)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(journalEntryProvider(widget.id));
    final permissions = ref.watch(permissionControllerProvider);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: Text(async.value?.journalEntryNumber ?? 'Entry')),
      body: async.when(
        loading: () => const Loader(),
        error: (error, _) => ErrorState(
          message: error is ApiException
              ? error.message
              : 'Could not load that entry.',
          onRetry: () => ref.invalidate(journalEntryProvider(widget.id)),
        ),
        data: (entry) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.description ?? 'No description',
                          style: TextStyle(
                            color: bos.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      StatusChip(entry.status, dense: true),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    [
                      Fmt.date(entry.entryDate),
                      if (entry.createdBy != null) 'by ${entry.createdBy}',
                      if (entry.approvedBy != null)
                        'approved by ${entry.approvedBy}',
                    ].join(' · '),
                    style: TextStyle(color: bos.muted, fontSize: 12),
                  ),
                  if (entry.reversed && entry.reversalEntryId != null) ...[
                    const SizedBox(height: 10),
                    MessageBanner.warning(
                      'Reversed by entry ${entry.reversalEntryId}.',
                    ),
                  ],
                  if (entry.isReversal) ...[
                    const SizedBox(height: 10),
                    MessageBanner.info(
                      'This entry reverses '
                      'entry ${entry.reversedFromEntryId}.',
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionHeader('Lines', icon: Icons.list_alt_rounded),
            const SizedBox(height: 10),
            AppCard(
              child: Column(
                children: [
                  for (final line in entry.lines) _LineRow(line: line),
                  const Divider(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Totals',
                          style: TextStyle(
                            color: bos.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 90,
                        child: Text(
                          Fmt.money(entry.totalDebits),
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: bos.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 90,
                        child: Text(
                          Fmt.money(entry.totalCredits),
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
                ],
              ),
            ),
            if (entry.notes != null && entry.notes!.isNotEmpty) ...[
              const SizedBox(height: 14),
              AppCard(
                child: Text(
                  entry.notes!,
                  style: TextStyle(color: bos.text, fontSize: 13, height: 1.5),
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (_busy)
              const Center(child: Loader())
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (entry.canApprove &&
                      permissions.has(AccountingPermissions.entryApprove))
                    _Action(
                      label: 'Approve',
                      icon: Icons.check_rounded,
                      onPressed: () => _act(
                        (repo) => repo.approveEntry(entry.id),
                        'Approved.',
                        'Could not approve that entry.',
                      ),
                    ),
                  if (entry.canPost &&
                      permissions.has(AccountingPermissions.entryPost))
                    _Action(
                      label: 'Post to the ledger',
                      icon: Icons.publish_rounded,
                      onPressed: () async {
                        final confirmed = await confirmAction(
                          context,
                          title: 'Post ${entry.journalEntryNumber}?',
                          message:
                              'It moves the ledger and the account balances. '
                              'After this it can only be reversed, never '
                              'edited or deleted.',
                          action: 'Post it',
                          destructive: false,
                        );
                        if (!confirmed || !mounted) return;
                        await _act(
                          (repo) => repo.postEntry(entry.id),
                          'Posted.',
                          'Could not post that entry.',
                        );
                      },
                    ),
                  if (entry.canReverse &&
                      permissions.has(AccountingPermissions.entryPost))
                    _Action(
                      label: 'Reverse',
                      icon: Icons.undo_rounded,
                      destructive: true,
                      onPressed: () async {
                        final confirmed = await confirmAction(
                          context,
                          title: 'Reverse ${entry.journalEntryNumber}?',
                          message:
                              'This posts an opposite entry against the same '
                              'accounts. Both stay on the record — that is how '
                              'a correction is made.',
                          action: 'Reverse it',
                        );
                        if (!confirmed || !mounted) return;
                        await _act(
                          (repo) => repo.reverseEntry(entry.id),
                          'Reversed.',
                          'Could not reverse that entry.',
                        );
                      },
                    ),
                  if (entry.canDelete &&
                      permissions.has(AccountingPermissions.entryDelete))
                    _Action(
                      label: 'Delete',
                      icon: Icons.delete_outline_rounded,
                      destructive: true,
                      onPressed: () async {
                        final confirmed = await confirmAction(
                          context,
                          title: 'Delete ${entry.journalEntryNumber}?',
                          message:
                              'Nothing has been posted from it yet, so it can '
                              'go without a trace.',
                          action: 'Delete',
                        );
                        if (!confirmed || !mounted) return;
                        await _act(
                          (repo) => repo.deleteEntry(entry.id),
                          'Deleted.',
                          'Could not delete that entry.',
                          pop: true,
                        );
                      },
                    ),
                ],
              ),
            if (entry.canApprove) ...[
              const SizedBox(height: 14),
              Text(
                'Whoever drafted an entry cannot approve it — that has to be a '
                'different person.',
                style: TextStyle(color: bos.muted, fontSize: 12, height: 1.45),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line});

  final JournalLine line;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    if (line.accountCode != null) line.accountCode!,
                    line.accountName ?? 'Account ${line.accountId}',
                  ].join('  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: bos.text, fontSize: 13),
                ),
                if (line.lineDescription != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    line.lineDescription!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: bos.muted, fontSize: 11.5),
                  ),
                ],
              ],
            ),
          ),
          // Two fixed columns rather than one — debits and credits line up the
          // way they do on paper, which is how the eye checks a balance.
          SizedBox(
            width: 90,
            child: Text(
              line.debitAmount > 0 ? Fmt.money(line.debitAmount) : '',
              textAlign: TextAlign.end,
              style: TextStyle(color: bos.text, fontSize: 12.5),
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              line.creditAmount > 0 ? Fmt.money(line.creditAmount) : '',
              textAlign: TextAlign.end,
              style: TextStyle(color: bos.text, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: destructive ? bos.danger : bos.brand,
        side: BorderSide(
          color: (destructive ? bos.danger : bos.brand).withValues(alpha: 0.4),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
    );
  }
}

// ── General ledger ────────────────────────────────────────────

class _LedgerTab extends ConsumerStatefulWidget {
  const _LedgerTab();

  @override
  ConsumerState<_LedgerTab> createState() => _LedgerTabState();
}

class _LedgerTabState extends ConsumerState<_LedgerTab> {
  int? _busyId;

  Future<void> _reconcile(LedgerLine line) async {
    final notes = await askForText(
      context,
      title: 'Mark as reconciled?',
      message:
          'Says this line has been matched against a bank statement. It does '
          'not change the amount or the account.',
      label: 'Note (optional)',
      action: 'Reconcile',
    );
    if (notes == null || !mounted) return;

    setState(() => _busyId = line.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(accountingRepositoryProvider).reconcileLine(line.id, notes);
      // No response body, so the row is rebuilt from what was asked for.
      ref.read(ledgerProvider.notifier).apply(
            LedgerLine(
              id: line.id,
              debitAmount: line.debitAmount,
              creditAmount: line.creditAmount,
              isReconciled: true,
              posted: line.posted,
              transactionDate: line.transactionDate,
              accountId: line.accountId,
              accountName: line.accountName,
              accountCode: line.accountCode,
              accountType: line.accountType,
              description: line.description,
              referenceType: line.referenceType,
              referenceNumber: line.referenceNumber,
              reconciliationNotes: notes.trim().isEmpty ? null : notes.trim(),
            ),
          );
      messenger.showSnackBar(const SnackBar(content: Text('Reconciled.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not reconcile that line.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final accountId = ref.watch(ledgerAccountFilterProvider);
    final canReconcile = ref
        .watch(permissionControllerProvider)
        .has(AccountingPermissions.ledgerReconcile);

    // The name of whatever the ledger is narrowed to, taken from the chart
    // rather than fetched again.
    String? accountName;
    if (accountId != null) {
      for (final account in ref.watch(accountsProvider).value ?? const <Account>[]) {
        if (account.id == accountId) {
          accountName = '${account.accountCode}  ${account.accountName}';
          break;
        }
      }
    }

    return ConfigList<LedgerLine>(
      async: ref.watch(ledgerProvider),
      onRefresh: ref.read(ledgerProvider.notifier).refresh,
      emptyIcon: Icons.menu_book_outlined,
      emptyTitle: accountId == null ? 'Nothing posted yet' : 'Nothing on this account',
      emptyMessage:
          'The ledger fills up as journal entries are posted, and as invoices, '
          'expenses and payroll post their own entries automatically.',
      errorMessage: 'Could not load the ledger.',
      header: accountId == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      accountName ?? 'One account',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: bos.muted, fontSize: 12.5),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        ref.read(ledgerAccountFilterProvider.notifier).set(null),
                    icon: const Icon(Icons.clear_rounded, size: 16),
                    label: const Text('Everything'),
                  ),
                ],
              ),
            ),
      itemBuilder: (context, line) => _LedgerRow(
        line: line,
        busy: _busyId == line.id,
        onReconcile:
            canReconcile && !line.isReconciled ? () => _reconcile(line) : null,
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    required this.line,
    required this.busy,
    this.onReconcile,
  });

  final LedgerLine line;
  final bool busy;
  final VoidCallback? onReconcile;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.accountName ?? 'Account ${line.accountId}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (line.description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      line.description!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: bos.muted, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        [
                          Fmt.date(line.transactionDate),
                          if (line.referenceNumber != null)
                            line.referenceNumber!,
                        ].join(' · '),
                        style: TextStyle(color: bos.muted, fontSize: 11.5),
                      ),
                      if (line.isReconciled) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.check_circle_outline_rounded,
                            size: 13, color: bos.brandInk),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  Fmt.money(line.amount),
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  // Which side it fell on is the whole meaning of the figure.
                  line.isDebit ? 'debit' : 'credit',
                  style: TextStyle(color: bos.muted, fontSize: 11),
                ),
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
            else if (onReconcile != null)
              IconButton(
                onPressed: onReconcile,
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                tooltip: 'Mark as reconciled',
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }
}
