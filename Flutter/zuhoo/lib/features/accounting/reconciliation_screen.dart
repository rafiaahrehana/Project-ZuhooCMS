import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/attachment_launcher.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/attachment_picker.dart';
import '../../shared/widgets/config_list.dart';
import '../../shared/widgets/form_sheet.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import 'accounting_models.dart';
import 'accounting_repository.dart';
import 'reconciliation_models.dart';

/// Whether the list is showing only what is still open.
class ReconciliationScopeController extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool openOnly) => state = openOnly;
}

final reconciliationScopeProvider =
    NotifierProvider<ReconciliationScopeController, bool>(
      ReconciliationScopeController.new,
    );

/// Squaring the books against the bank.
///
/// One reconciliation per bank account per sitting: it records what the
/// statement says, works out what the ledger says, and the gap between them is
/// closed by ticking off the entries the bank has since shown.
class ReconciliationScreen extends ConsumerWidget {
  const ReconciliationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final openOnly = ref.watch(reconciliationScopeProvider);
    final permissions = ref.watch(permissionControllerProvider);
    final canCreate = permissions.has(ReconciliationPermissions.create);

    final async = openOnly
        ? ref.watch(pendingReconciliationsProvider)
        : ref.watch(allReconciliationsProvider);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Bank reconciliation')),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => showOpenReconciliationSheet(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Start one'),
            )
          : null,
      body: ConfigList<BankReconciliation>(
        async: async,
        onRefresh: () async {
          ref.invalidate(pendingReconciliationsProvider);
          ref.invalidate(allReconciliationsProvider);
        },
        emptyIcon: Icons.account_balance_outlined,
        emptyTitle: openOnly ? 'Nothing open' : 'Nothing yet',
        emptyMessage: openOnly
            ? 'Every reconciliation has been signed off.'
            : 'Start one against a bank account with the balance its '
                  'statement shows.',
        errorMessage: 'Could not load the reconciliations.',
        header: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: FilterBar(
            selected: openOnly ? 'open' : null,
            options: const [
              (value: 'open', label: 'Still open'),
              (value: null, label: 'All of them'),
            ],
            onSelected: (value) => ref
                .read(reconciliationScopeProvider.notifier)
                .set(value == 'open'),
          ),
        ),
        itemBuilder: (context, reconciliation) =>
            _ReconciliationRow(reconciliation: reconciliation),
      ),
    );
  }
}

class _ReconciliationRow extends StatelessWidget {
  const _ReconciliationRow({required this.reconciliation});

  final BankReconciliation reconciliation;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        onTap: () =>
            ReconciliationDetailScreen.open(context, id: reconciliation.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    reconciliation.bankAccountName ?? 'A bank account',
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                StatusChip(
                  reconciliation.reconciled ? 'RECONCILED' : 'OPEN',
                  dense: true,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [
                Fmt.dateShort(reconciliation.reconciliationDate),
                'bank ${Fmt.money(reconciliation.bankStatementBalance)}',
                'books ${Fmt.money(reconciliation.glBalance)}',
              ].join('  ·  '),
              style: TextStyle(color: bos.muted, fontSize: 11.5),
            ),
            if (!reconciliation.reconciled) ...[
              const SizedBox(height: 6),
              Text(
                reconciliation.balances
                    ? 'Squared — ready to sign off'
                    : 'Out by ${Fmt.money(reconciliation.difference.abs())}',
                style: TextStyle(
                  color: reconciliation.balances ? bos.success : bos.warning,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Opening one ───────────────────────────────────────────────

Future<void> showOpenReconciliationSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _OpenSheet(),
    );

class _OpenSheet extends ConsumerStatefulWidget {
  const _OpenSheet();

  @override
  ConsumerState<_OpenSheet> createState() => _OpenSheetState();
}

class _OpenSheetState extends ConsumerState<_OpenSheet> {
  final _formKey = GlobalKey<FormState>();
  final _balance = TextEditingController();
  int? _accountId;

  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _balance.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_accountId == null) {
      setState(() => _error = 'Pick the account it is for.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await ref
          .read(accountingRepositoryProvider)
          .openReconciliation(
            BankReconciliationRequest(
              bankAccountId: _accountId!,
              bankStatementBalance: double.parse(_balance.text.trim()),
            ),
          );
      ref.invalidate(pendingReconciliationsProvider);
      ref.invalidate(allReconciliationsProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ReconciliationDetailScreen.open(context, id: created.id);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not start that reconciliation.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    // Only accounts flagged as bank accounts on the chart. Reconciling a
    // revenue account against a statement is meaningless.
    final bankAccounts = accounts
        .where((account) => account.isBankAccount)
        .toList();

    return FormSheetFrame(
      title: 'Start a reconciliation',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'Start',
      submitting: _busy,
      onSubmit: _submit,
      children: [
        if (bankAccounts.isEmpty)
          MessageBanner.warning(
            'No account on the chart is marked as a bank account, so there is '
            'nothing to reconcile against. That flag is set when the account '
            'is created.',
          )
        else
          DropdownButtonFormField<int>(
            initialValue: _accountId,
            decoration: const InputDecoration(labelText: 'Bank account'),
            items: [
              for (final account in bankAccounts)
                DropdownMenuItem(
                  value: account.id,
                  // Code first, the way the account picker on the journal
                  // sheet reads — two bank accounts often differ only by it.
                  child: Text('${account.accountCode}  ${account.accountName}'),
                ),
            ],
            onChanged: (value) => setState(() => _accountId = value),
          ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _balance,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: const InputDecoration(
            labelText: 'Balance on the statement',
          ),
          validator: (value) => double.tryParse(value?.trim() ?? '') == null
              ? 'The figure from the statement, please.'
              : null,
        ),
        const SizedBox(height: 10),
        Text(
          'What the books say is read from the ledger, and the date is today. '
          'Only the statement figure is yours to enter.',
          style: TextStyle(color: bos.muted, fontSize: 11.5, height: 1.5),
        ),
      ],
    );
  }
}

// ── Working through one ───────────────────────────────────────

class ReconciliationDetailScreen extends ConsumerWidget {
  const ReconciliationDetailScreen({super.key, required this.id});

  final int id;

  static void open(BuildContext context, {required int id}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReconciliationDetailScreen(id: id),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(reconciliationProvider(id));

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Reconciliation')),
      body: async.when(
        loading: () => const Loader(),
        error: (error, _) => ErrorState(
          message: error is ApiException
              ? error.message
              : 'Could not load that reconciliation.',
          onRetry: () => ref.invalidate(reconciliationProvider(id)),
        ),
        data: (reconciliation) => RefreshIndicator(
          color: bos.brand,
          backgroundColor: bos.bgCard,
          onRefresh: () async {
            ref.invalidate(reconciliationProvider(id));
            ref.invalidate(unclearedTransactionsProvider(id));
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _Figures(reconciliation: reconciliation),
              const SizedBox(height: 20),
              _Statement(reconciliation: reconciliation),
              const SizedBox(height: 20),
              _Uncleared(reconciliation: reconciliation),
            ],
          ),
        ),
      ),
    );
  }
}

class _Figures extends ConsumerStatefulWidget {
  const _Figures({required this.reconciliation});

  final BankReconciliation reconciliation;

  @override
  ConsumerState<_Figures> createState() => _FiguresState();
}

class _FiguresState extends ConsumerState<_Figures> {
  bool _busy = false;

  Future<void> _signOff() async {
    final notes = await askForText(
      context,
      title: 'Sign it off?',
      message:
          'Anything worth recording about the reconciliation. You can '
          'leave it blank.',
      label: 'Notes',
      action: 'Sign off',
    );
    if (!mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(accountingRepositoryProvider)
          .markReconciled(widget.reconciliation.id, notes: notes);
      ref.invalidate(reconciliationProvider(widget.reconciliation.id));
      ref.invalidate(pendingReconciliationsProvider);
      ref.invalidate(allReconciliationsProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Signed off.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not sign that off.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final reconciliation = widget.reconciliation;
    final canSignOff = ref
        .watch(permissionControllerProvider)
        .has(ReconciliationPermissions.reconcile);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reconciliation.bankAccountName ?? 'A bank account',
            style: TextStyle(
              color: bos.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          _Line('The bank says', reconciliation.bankStatementBalance),
          _Line(
            'Deposits not shown yet',
            reconciliation.outstandingDepositsTotal,
          ),
          _Line(
            'Cheques not presented',
            -reconciliation.outstandingChecksTotal,
          ),
          Divider(color: bos.border, height: 20),
          _Line('Adjusted bank balance', reconciliation.adjustedBankBalance),
          _Line('The books say', reconciliation.glBalance),
          Divider(color: bos.border, height: 20),
          _Line(
            'Difference',
            reconciliation.difference,
            emphasis: true,
            tone: reconciliation.balances ? bos.success : bos.danger,
          ),
          if (reconciliation.reconciled) ...[
            const SizedBox(height: 12),
            Text(
              'Signed off ${Fmt.dateShort(reconciliation.reconciledDate)}'
              '${reconciliation.reconciledBy != null ? " by ${reconciliation.reconciledBy}" : ""}.',
              style: TextStyle(color: bos.success, fontSize: 12),
            ),
            if (reconciliation.discrepancyNotes != null &&
                reconciliation.discrepancyNotes!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  reconciliation.discrepancyNotes!,
                  style: TextStyle(color: bos.muted, fontSize: 12, height: 1.5),
                ),
              ),
          ] else if (canSignOff) ...[
            const SizedBox(height: 14),
            LoadingButton(
              label: 'Sign it off',
              icon: Icons.verified_outlined,
              loading: _busy,
              // The backend refuses while the two sides differ; the button is
              // held back rather than letting somebody press it and be told.
              onPressed: reconciliation.balances ? _signOff : null,
            ),
            if (!reconciliation.balances)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'It cannot be signed off until the difference is nothing. '
                  'Tick off the entries the bank has since shown.',
                  style: TextStyle(
                    color: bos.muted,
                    fontSize: 11.5,
                    height: 1.5,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.amount, {this.emphasis = false, this.tone});

  final String label;
  final double amount;
  final bool emphasis;
  final Color? tone;

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
              style: TextStyle(
                color: emphasis ? bos.text : bos.muted,
                fontSize: emphasis ? 13.5 : 12.5,
                fontWeight: emphasis ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            Fmt.money(amount),
            style: TextStyle(
              color: tone ?? bos.text,
              fontSize: emphasis ? 14 : 13,
              fontWeight: emphasis ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// The statement file: importing one to tick entries off automatically, and
/// filing one against the reconciliation so it can be found later.
class _Statement extends ConsumerStatefulWidget {
  const _Statement({required this.reconciliation});

  final BankReconciliation reconciliation;

  @override
  ConsumerState<_Statement> createState() => _StatementState();
}

class _StatementState extends ConsumerState<_Statement> {
  bool _busy = false;

  Future<void> _import() async {
    final picked = await pickAttachment(context);
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(accountingRepositoryProvider)
          .importStatement(widget.reconciliation.id, picked.path, picked.name);

      ref.invalidate(reconciliationProvider(widget.reconciliation.id));
      ref.invalidate(unclearedTransactionsProvider(widget.reconciliation.id));

      if (!mounted) return;
      // What it could not match is the useful half of the answer, so it gets
      // a sheet rather than a snackbar that scrolls away.
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _ImportResultSheet(result: result),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not read that statement.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _attach() async {
    final picked = await pickAttachment(context);
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Two steps: the file is stored by the generic upload endpoint, and the
      // URL it answers with is what gets filed against the reconciliation.
      final uploaded = await ref
          .read(accountingRepositoryProvider)
          .attachUploadedStatement(widget.reconciliation.id, picked);
      ref.invalidate(reconciliationProvider(widget.reconciliation.id));
      messenger.showSnackBar(
        SnackBar(content: Text('Filed ${uploaded.statementFileName}.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not file that statement.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final reconciliation = widget.reconciliation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('The statement', icon: Icons.description_outlined),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (reconciliation.statementFileName != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: reconciliation.statementFileUrl == null
                        ? null
                        : () => openAttachmentUrl(
                            context,
                            reconciliation.statementFileUrl,
                          ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.attach_file_rounded,
                          size: 15,
                          color: bos.muted,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            reconciliation.statementFileName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: reconciliation.statementFileUrl == null
                                  ? bos.text
                                  : bos.brandInk,
                              fontSize: 12.5,
                              decoration:
                                  reconciliation.statementFileUrl == null
                                  ? null
                                  : TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_busy)
                const Loader(padding: 10)
              else if (!reconciliation.reconciled) ...[
                OutlinedButton.icon(
                  onPressed: _import,
                  icon: const Icon(Icons.upload_file_outlined, size: 17),
                  label: const Text('Import a CSV'),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _attach,
                  icon: const Icon(Icons.attach_file_rounded, size: 16),
                  label: Text(
                    reconciliation.statementFileName == null
                        ? 'File the statement'
                        : 'Replace the filed statement',
                  ),
                ),
                Text(
                  'Importing reads the file and ticks off what it can match. '
                  'Filing only keeps a copy against this reconciliation.',
                  style: TextStyle(
                    color: bos.muted,
                    fontSize: 11.5,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ImportResultSheet extends StatelessWidget {
  const _ImportResultSheet({required this.result});

  final StatementImportResult result;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${result.matched} of ${result.totalLines} matched',
            style: TextStyle(
              color: bos.text,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            result.unmatchedCount == 0
                ? 'Every line found something in the ledger.'
                : '${result.unmatchedCount} could not be matched. Those are '
                      'below, with what stopped each one.',
            style: TextStyle(color: bos.muted, fontSize: 12.5, height: 1.5),
          ),
          if (result.unmatchedLines.isNotEmpty) ...[
            const SizedBox(height: 14),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final line in result.unmatchedLines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  line.description ?? 'A statement line',
                                  style: TextStyle(
                                    color: bos.text,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  [
                                    if (line.date != null)
                                      Fmt.dateShort(line.date),
                                    if (line.reason != null) line.reason!,
                                  ].join('  ·  '),
                                  style: TextStyle(
                                    color: bos.muted,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            Fmt.money(line.amount),
                            style: TextStyle(color: bos.text, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The ledger entries the bank has not shown yet.
class _Uncleared extends ConsumerStatefulWidget {
  const _Uncleared({required this.reconciliation});

  final BankReconciliation reconciliation;

  @override
  ConsumerState<_Uncleared> createState() => _UnclearedState();
}

class _UnclearedState extends ConsumerState<_Uncleared> {
  int? _busyId;

  Future<void> _toggle(LedgerLine line, bool cleared) async {
    setState(() => _busyId = line.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(accountingRepositoryProvider)
          .toggleTransaction(
            widget.reconciliation.id,
            line.id,
            cleared: cleared,
          );
      ref.invalidate(reconciliationProvider(widget.reconciliation.id));
      ref.invalidate(unclearedTransactionsProvider(widget.reconciliation.id));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not tick that off.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(
      unclearedTransactionsProvider(widget.reconciliation.id),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Not cleared yet', icon: Icons.checklist_rounded),
        AppCard(
          child: async.when(
            loading: () => const Loader(padding: 16),
            error: (error, _) => MessageBanner.error(
              error is ApiException
                  ? error.message
                  : 'Could not load the outstanding entries.',
            ),
            data: (lines) => lines.isEmpty
                ? Text(
                    'Everything on this account has cleared the bank.',
                    style: TextStyle(color: bos.muted, fontSize: 13),
                  )
                : Column(
                    children: [
                      for (final line in lines)
                        _LineRow(
                          line: line,
                          busy: _busyId == line.id,
                          enabled: !widget.reconciliation.reconciled,
                          onChanged: (cleared) => _toggle(line, cleared),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.line,
    required this.busy,
    required this.enabled,
    required this.onChanged,
  });

  final LedgerLine line;
  final bool busy;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    // A debit into a bank account is money in; a credit is money out.
    final amount = line.debitAmount - line.creditAmount;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: busy
                ? const Center(
                    child: SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Checkbox(
                    value: line.isReconciled,
                    onChanged: enabled
                        ? (value) => onChanged(value ?? false)
                        : null,
                  ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.description ?? line.referenceNumber ?? 'A ledger entry',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: bos.text, fontSize: 13),
                ),
                Text(
                  [
                    if (line.transactionDate != null)
                      Fmt.dateShort(line.transactionDate),
                    if (line.referenceNumber != null) line.referenceNumber!,
                  ].join('  ·  '),
                  style: TextStyle(color: bos.muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            Fmt.money(amount),
            style: TextStyle(
              color: amount < 0 ? bos.danger : bos.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
