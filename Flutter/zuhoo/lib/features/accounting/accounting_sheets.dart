import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/date_field.dart';
import '../../shared/widgets/form_sheet.dart';
import '../../shared/widgets/primitives.dart';
import 'accounting_models.dart';
import 'accounting_repository.dart';

// ── Accounts ──────────────────────────────────────────────────

Future<void> showAccountSheet(
  BuildContext context, {
  Account? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AccountSheet(existing: existing),
  );
}

class _AccountSheet extends ConsumerStatefulWidget {
  const _AccountSheet({this.existing});

  final Account? existing;

  @override
  ConsumerState<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends ConsumerState<_AccountSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _code =
      TextEditingController(text: widget.existing?.accountCode ?? '');
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.accountName ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.existing?.description ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.existing?.notes ?? '');
  final _openingBalance = TextEditingController();

  late String _type = widget.existing?.type ?? accountTypes.first;
  late bool _isHeader = widget.existing?.isHeaderAccount ?? false;
  late bool _isBank = widget.existing?.isBankAccount ?? false;
  late bool _allowDirectPosting = widget.existing?.allowDirectPosting ?? true;
  late bool _active = widget.existing?.active ?? true;
  DateTime? _openingBalanceDate;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _description.dispose();
    _notes.dispose();
    _openingBalance.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final opening = double.tryParse(_openingBalance.text.trim());
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(accountingRepositoryProvider);
    final request = AccountRequest(
      accountCode: _code.text,
      accountName: _name.text,
      type: _type,
      isHeaderAccount: _isHeader,
      isBankAccount: _isBank,
      // A header account cannot be posted to whatever the switch says, and the
      // backend would refuse the first entry against it — so the two are kept
      // consistent here rather than sent contradicting each other.
      allowDirectPosting: _isHeader ? false : _allowDirectPosting,
      active: _active,
      description: _description.text,
      notes: _notes.text,
      // Only on create, and only when there is one — it posts a real balancing
      // entry rather than setting a number.
      openingBalance: _isEdit ? null : opening,
      openingBalanceDate: _isEdit || opening == null || _openingBalanceDate == null
          ? null
          : Fmt.isoDate(_openingBalanceDate!),
    );

    try {
      if (_isEdit) {
        final updated = await repo.updateAccount(widget.existing!.id, request);
        ref.read(accountsProvider.notifier).apply(updated);
      } else {
        await repo.createAccount(request);
        await ref.read(accountsProvider.notifier).refresh();
      }
      ref.invalidate(postableAccountsProvider);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text(_isEdit ? 'Account updated.' : 'Account added.')),
      );
    } on ApiException catch (e) {
      // A duplicate code comes back naming the code.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save that account.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: _isEdit ? 'Edit account' : 'New account',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: _isEdit ? 'Save changes' : 'Add account',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: TextFormField(
                controller: _code,
                autofocus: !_isEdit,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Code'),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) return 'Required.';
                  // Matches @Size(min = 3, max = 10).
                  if (trimmed.length < 3) return 'Three or more.';
                  return trimmed.length > 10 ? 'Ten at most.' : null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (value) =>
                    (value?.trim().isEmpty ?? true) ? 'A name is required.' : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _type,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Type',
            prefixIcon: Icon(Icons.account_tree_outlined),
          ),
          items: [
            for (final type in accountTypes)
              DropdownMenuItem(
                value: type,
                child: Text('${Fmt.label(type)} · ${accountGroup(type)}'),
              ),
          ],
          onChanged: (value) => setState(() => _type = value ?? _type),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _description,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'What belongs here (optional)',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          value: _isHeader,
          onChanged: (value) => setState(() => _isHeader = value),
          title: Text(
            'A heading, not a real account',
            style: TextStyle(color: bos.text, fontSize: 14),
          ),
          subtitle: Text(
            'Totals its children. Nothing can be posted to it.',
            style: TextStyle(color: bos.muted, fontSize: 11.5),
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        if (!_isHeader)
          SwitchListTile(
            value: _allowDirectPosting,
            onChanged: (value) =>
                setState(() => _allowDirectPosting = value),
            title: Text(
              'Allow direct posting',
              style: TextStyle(color: bos.text, fontSize: 14),
            ),
            subtitle: Text(
              'Off means only automatic entries can touch it',
              style: TextStyle(color: bos.muted, fontSize: 11.5),
            ),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        SwitchListTile(
          value: _isBank,
          onChanged: (value) => setState(() => _isBank = value),
          title: Text(
            'A bank account',
            style: TextStyle(color: bos.text, fontSize: 14),
          ),
          subtitle: Text(
            'Appears where a statement can be reconciled against it',
            style: TextStyle(color: bos.muted, fontSize: 11.5),
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        SwitchListTile(
          value: _active,
          onChanged: (value) => setState(() => _active = value),
          title: Text('In use', style: TextStyle(color: bos.text, fontSize: 14)),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        if (!_isEdit) ...[
          const SizedBox(height: 16),
          TextFormField(
            controller: _openingBalance,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Opening balance (optional)',
              helperText: 'Only when migrating from another system',
              prefixIcon: Icon(Icons.history_rounded),
            ),
            onChanged: (_) => setState(() {}),
            validator: (value) {
              final trimmed = value?.trim() ?? '';
              if (trimmed.isEmpty) return null;
              final parsed = double.tryParse(trimmed);
              if (parsed == null) return 'A number.';
              return parsed < 0 ? 'Zero or more.' : null;
            },
          ),
          if (_openingBalance.text.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            DateField(
              label: 'As at',
              value: _openingBalanceDate,
              onChanged: (value) =>
                  setState(() => _openingBalanceDate = value),
            ),
            const SizedBox(height: 10),
            MessageBanner.info(
              'This posts a real balancing entry against Opening Balance '
              'Equity. It is not just a number on the account.',
            ),
          ],
        ],
        const SizedBox(height: 16),
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

// ── Journal entries ───────────────────────────────────────────

/// Composes a journal entry.
///
/// The one genuinely wide form in the app: a repeating list of lines, each an
/// account and an amount on one side. It refuses to submit until the entry
/// balances, and says by how much it is out while you type — finding that out
/// from a 400 after the fact is a poor way to learn you fat-fingered a digit.
Future<void> showJournalEntrySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _JournalEntrySheet(),
  );
}

class _JournalEntrySheet extends ConsumerStatefulWidget {
  const _JournalEntrySheet();

  @override
  ConsumerState<_JournalEntrySheet> createState() => _JournalEntrySheetState();
}

class _JournalEntrySheetState extends ConsumerState<_JournalEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();

  DateTime? _entryDate = DateTime.now();

  /// Starts at two, which is the minimum a balanced entry can have.
  final List<JournalLineRequest> _lines = [
    const JournalLineRequest(),
    const JournalLineRequest(),
  ];

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  JournalEntryRequest get _request => JournalEntryRequest(
        entryDate:
            Fmt.isoDate(_entryDate ?? DateTime.now()),
        lines: _lines,
        description: _description.text,
      );

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final request = _request;
    final problem = request.problem;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(accountingRepositoryProvider).createEntry(request);
      await ref.read(journalEntriesProvider.notifier).refresh();
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Entry drafted. Somebody else has to approve it.'),
        ),
      );
    } on ApiException catch (e) {
      // Header-account and balance failures both come back written out.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save that entry.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final accounts = ref.watch(postableAccountsProvider);
    final request = _request;
    final difference = request.totalDebits - request.totalCredits;

    return FormSheetFrame(
      title: 'New journal entry',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'Save as draft',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        DateField(
          label: 'Entry date',
          value: _entryDate,
          clearable: false,
          onChanged: (value) => setState(() => _entryDate = value),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _description,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'What it is for',
            prefixIcon: Icon(Icons.notes_rounded),
          ),
        ),
        const SizedBox(height: 20),
        accounts.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Loader(),
          ),
          error: (error, _) => MessageBanner.error(
            error is ApiException
                ? error.message
                : 'Could not load the chart of accounts.',
          ),
          data: (options) {
            if (options.isEmpty) {
              return MessageBanner.warning(
                'There are no accounts that allow direct posting. Add one, or '
                'turn direct posting on for an existing account.',
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < _lines.length; i++)
                  _LineEditor(
                    key: ValueKey(i),
                    line: _lines[i],
                    accounts: options,
                    // Two lines is the minimum, so neither can be removed.
                    onRemove: _lines.length > 2
                        ? () => setState(() => _lines.removeAt(i))
                        : null,
                    onChanged: (line) => setState(() => _lines[i] = line),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(
                      () => _lines.add(const JournalLineRequest()),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Another line'),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        // The running total, always visible. An entry that does not balance is
        // refused, and knowing by how much is the whole job of fixing it.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: request.balances ? bos.brandSoft : bos.dangerSoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                request.balances
                    ? Icons.check_circle_outline_rounded
                    : Icons.error_outline_rounded,
                size: 18,
                color: request.balances ? bos.brandInk : bos.danger,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  request.balances
                      ? 'Balanced at ${Fmt.money(request.totalDebits)}.'
                      : 'Debits ${Fmt.money(request.totalDebits)}, credits '
                          '${Fmt.money(request.totalCredits)} — out by '
                          '${Fmt.money(difference.abs())}.',
                  style: TextStyle(
                    color: request.balances ? bos.brandInk : bos.danger,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One leg: an account, a side, and an amount.
///
/// Debit and credit are one control rather than two fields, because a line can
/// be one or the other and never both — the backend refuses it, and two fields
/// invite exactly that mistake.
class _LineEditor extends StatefulWidget {
  const _LineEditor({
    super.key,
    required this.line,
    required this.accounts,
    required this.onChanged,
    this.onRemove,
  });

  final JournalLineRequest line;
  final List<Account> accounts;
  final ValueChanged<JournalLineRequest> onChanged;
  final VoidCallback? onRemove;

  @override
  State<_LineEditor> createState() => _LineEditorState();
}

class _LineEditorState extends State<_LineEditor> {
  late final TextEditingController _amount = TextEditingController(
    text: _plain(widget.line.debitAmount > 0
        ? widget.line.debitAmount
        : widget.line.creditAmount),
  );

  late bool _isDebit = widget.line.creditAmount == 0;

  static String _plain(double value) => value == 0
      ? ''
      : (value == value.roundToDouble() ? '${value.round()}' : '$value');

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _emit() {
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    widget.onChanged(
      JournalLineRequest(
        accountId: widget.line.accountId,
        debitAmount: _isDebit ? amount : 0,
        creditAmount: _isDebit ? 0 : amount,
        lineDescription: widget.line.lineDescription,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          border: Border.all(color: bos.borderLight),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: widget.line.accountId,
                    isExpanded: true,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'Account',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    items: [
                      for (final account in widget.accounts)
                        DropdownMenuItem(
                          value: account.id,
                          child: Text(
                            '${account.accountCode}  ${account.accountName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13.5),
                          ),
                        ),
                    ],
                    onChanged: (value) => widget.onChanged(
                      JournalLineRequest(
                        accountId: value,
                        debitAmount: widget.line.debitAmount,
                        creditAmount: widget.line.creditAmount,
                        lineDescription: widget.line.lineDescription,
                      ),
                    ),
                  ),
                ),
                if (widget.onRemove != null)
                  IconButton(
                    onPressed: widget.onRemove,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Remove this line',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Debit')),
                    ButtonSegment(value: false, label: Text('Credit')),
                  ],
                  selected: {_isDebit},
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onSelectionChanged: (selection) {
                    setState(() => _isDebit = selection.first);
                    _emit();
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _amount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.end,
                    decoration: const InputDecoration(
                      hintText: '0.00',
                      isDense: true,
                    ),
                    onChanged: (_) => _emit(),
                    validator: (value) {
                      final trimmed = value?.trim() ?? '';
                      if (trimmed.isEmpty) return null;
                      final parsed = double.tryParse(trimmed);
                      if (parsed == null) return 'A number.';
                      return parsed < 0 ? 'Not negative.' : null;
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
