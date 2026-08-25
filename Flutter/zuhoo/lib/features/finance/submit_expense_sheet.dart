import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/attachment_picker.dart';
import '../../shared/widgets/primitives.dart';
import '../ai/ai_models.dart' show AiPermissions;
import 'finance_models.dart';
import 'finance_repository.dart';

Future<void> showSubmitExpenseSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _SubmitExpenseSheet(),
  );
}

/// Claiming an expense — the one finance task people genuinely do on a phone,
/// standing next to the thing they just paid for.
class _SubmitExpenseSheet extends ConsumerStatefulWidget {
  const _SubmitExpenseSheet();

  @override
  ConsumerState<_SubmitExpenseSheet> createState() =>
      _SubmitExpenseSheetState();
}

class _SubmitExpenseSheetState extends ConsumerState<_SubmitExpenseSheet> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final _vendor = TextEditingController();
  final _category = TextEditingController();

  /// Defaults to today, because that is when almost every claim is made.
  DateTime _date = DateTime.now();

  bool _submitting = false;
  bool _drafting = false;
  String? _error;

  PickedAttachment? _receipt;
  String? _receiptUrl;
  bool _uploadingReceipt = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _amount.dispose();
    _vendor.dispose();
    _category.dispose();
    super.dispose();
  }

  /// Drafts the wording from rough notes.
  ///
  /// Everything already typed goes along as context, so the draft agrees with
  /// the amount and vendor rather than inventing its own. The result lands in
  /// the fields as text the claimant can edit — nothing is submitted here.
  Future<void> _draftWithAi() async {
    final notes = await showDialog<String>(
      context: context,
      builder: (context) => const _RoughNotesDialog(),
    );
    if (notes == null || notes.trim().isEmpty || !mounted) return;

    setState(() => _drafting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final draft = await ref.read(financeRepositoryProvider).composeExpense(
            ExpenseComposeRequest(
              roughNotes: notes,
              vendorName: _vendor.text,
              amount: _amount.text,
              category: _category.text,
            ),
          );
      if (!mounted) return;
      setState(() {
        if (draft.title.trim().isNotEmpty) _title.text = draft.title.trim();
        if (draft.description.trim().isNotEmpty) {
          _description.text = draft.description.trim();
        }
      });
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not draft that.')),
      );
    } finally {
      if (mounted) setState(() => _drafting = false);
    }
  }

  Future<void> _pickReceipt() async {
    final picked = await pickAttachment(context);
    if (picked == null || !mounted) return;

    setState(() {
      _receipt = picked;
      _uploadingReceipt = true;
      _receiptUrl = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      final uploaded =
          await ref.read(apiClientProvider).uploadDocument(picked.path, picked.name);
      if (mounted) setState(() => _receiptUrl = uploaded.fileUrl);
    } on ApiException catch (e) {
      if (mounted) setState(() => _receipt = null);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) setState(() => _receipt = null);
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not upload that receipt.')),
      );
    } finally {
      if (mounted) setState(() => _uploadingReceipt = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      // A year back covers a late claim; nothing in the future, because you
      // cannot have already spent money you have not spent.
      firstDate: DateTime(now.year - 1),
      lastDate: now,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_uploadingReceipt) {
      setState(() => _error = 'Wait for the receipt to finish uploading.');
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(expensesProvider.notifier).submit(
            CreateExpenseRequest(
              title: _title.text,
              description: _description.text,
              amount: double.parse(_amount.text.trim()),
              expenseDate: Fmt.isoDate(_date),
              vendorName: _vendor.text,
              category: _category.text,
              receiptUrl: _receiptUrl,
            ),
          );
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Claim submitted for approval.')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not submit that claim.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    // The compose endpoint resolves to the same generateRaw the assistant uses,
    // and that checks AI_CHAT — so without it the button is not offered rather
    // than failing on tap.
    final canDraft = ref
        .watch(permissionControllerProvider)
        .has(AiPermissions.chat);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Claim an expense',
                style: TextStyle(
                  color: bos.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              if (_error != null) ...[
                MessageBanner.error(
                  _error!,
                  onDismiss: () => setState(() => _error = null),
                ),
                const SizedBox(height: 14),
              ],
              TextFormField(
                controller: _amount,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: (value) {
                  final parsed = double.tryParse(value?.trim() ?? '');
                  if (parsed == null) return 'Enter the amount.';
                  if (parsed <= 0) return 'Enter an amount above zero.';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _description,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'What was it for',
                  hintText: 'Taxi to the client site',
                  prefixIcon: const Icon(Icons.notes_rounded),
                  alignLabelWithHint: true,
                  suffixIcon: canDraft
                      ? (_drafting
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.auto_awesome_outlined,
                                  size: 19),
                              tooltip: 'Draft from rough notes',
                              onPressed: _submitting ? null : _draftWithAi,
                            ))
                      : null,
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Whoever approves this needs to know what it was.'
                    : null,
              ),
              if (_title.text.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    prefixIcon: Icon(Icons.title_rounded),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              InkWell(
                onTap: _submitting ? null : _pickDate,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    prefixIcon: Icon(Icons.event_outlined),
                  ),
                  child: Text(
                    Fmt.date(Fmt.isoDate(_date)),
                    style: TextStyle(color: bos.text, fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _vendor,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Paid to (optional)',
                  prefixIcon: Icon(Icons.storefront_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _category,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Category (optional)',
                  hintText: 'Travel, Meals, Software...',
                  prefixIcon: Icon(Icons.sell_outlined),
                ),
              ),
              const SizedBox(height: 16),
              _ReceiptField(
                receipt: _receipt,
                uploading: _uploadingReceipt,
                onPick: _submitting ? null : _pickReceipt,
                onRemove: () => setState(() {
                  _receipt = null;
                  _receiptUrl = null;
                }),
              ),
              const SizedBox(height: 18),
              LoadingButton(
                label: 'Submit claim',
                loading: _submitting,
                icon: Icons.send_rounded,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceiptField extends StatelessWidget {
  const _ReceiptField({
    required this.receipt,
    required this.uploading,
    required this.onPick,
    required this.onRemove,
  });

  final PickedAttachment? receipt;
  final bool uploading;
  final VoidCallback? onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    if (receipt == null) {
      return OutlinedButton.icon(
        onPressed: onPick,
        icon: const Icon(Icons.attach_file_rounded, size: 17),
        label: const Text('Attach a receipt (optional)'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bos.bgSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: bos.borderLight),
      ),
      child: Row(
        children: [
          Icon(Icons.description_outlined, size: 18, color: bos.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              receipt!.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: bos.text, fontSize: 13.5),
            ),
          ),
          if (uploading)
            const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              icon: Icon(Icons.close_rounded, size: 18, color: bos.muted),
              onPressed: onRemove,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              tooltip: 'Remove',
            ),
        ],
      ),
    );
  }
}

/// Asks for the rough notes the draft is built from.
///
/// A dialog rather than another field on the form: the notes are input to the
/// assistant, not part of the claim, and leaving them sitting in the sheet
/// afterwards would read as something that gets submitted.
class _RoughNotesDialog extends StatefulWidget {
  const _RoughNotesDialog();

  @override
  State<_RoughNotesDialog> createState() => _RoughNotesDialogState();
}

class _RoughNotesDialogState extends State<_RoughNotesDialog> {
  final _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Draft from notes'),
      content: TextField(
        controller: _notes,
        autofocus: true,
        maxLines: 3,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'cab to airport for the Dhaka pitch, waited 20 min',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _notes.text),
          child: const Text('Draft'),
        ),
      ],
    );
  }
}
