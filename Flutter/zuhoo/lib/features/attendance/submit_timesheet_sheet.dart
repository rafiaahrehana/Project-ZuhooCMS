import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'attendance_controller.dart';
import 'attendance_models.dart';

Future<void> showLogTimesheetSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _LogTimesheetSheet(),
  );
}

/// Corrects an entry that has not gone for review yet.
///
/// Only offered while `Timesheet.isEditable` — the backend refuses once an
/// entry is submitted or approved, and says which.
Future<void> showEditTimesheetSheet(
  BuildContext context,
  Timesheet timesheet,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _LogTimesheetSheet(existing: timesheet),
  );
}

/// Logging a day's hours — one entry per work date, which is also all the
/// backend allows (`workDate` is unique per employee).
class _LogTimesheetSheet extends ConsumerStatefulWidget {
  const _LogTimesheetSheet({this.existing});

  final Timesheet? existing;

  @override
  ConsumerState<_LogTimesheetSheet> createState() =>
      _LogTimesheetSheetState();
}

class _LogTimesheetSheetState extends ConsumerState<_LogTimesheetSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _hours;
  late final TextEditingController _billable;
  late final TextEditingController _project;
  late final TextEditingController _description;

  late DateTime _date;
  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  /// A number as somebody would type it: "8", not "8.0", and "7.5" kept.
  static String _plain(double value) =>
      value == value.roundToDouble() ? value.round().toString() : '$value';

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    // Seeded as a plain number, not via Fmt.hours — that renders "8h", which
    // is right for reading and unparseable when the field is submitted again.
    _hours = TextEditingController(
      text: existing == null ? '' : _plain(existing.hoursWorked),
    );
    _billable = TextEditingController(
      text: existing == null || existing.billableHours == 0
          ? ''
          : _plain(existing.billableHours),
    );
    _project = TextEditingController(text: existing?.projectName ?? '');
    _description = TextEditingController(text: existing?.description ?? '');
    _date = Fmt.parse(existing?.workDate) ?? DateTime.now();
  }

  @override
  void dispose() {
    _hours.dispose();
    _billable.dispose();
    _project.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(timesheetsProvider.notifier);
    try {
      if (_isEdit) {
        await controller.updateItem(
          widget.existing!.id,
          workDate: _date,
          hoursWorked: double.parse(_hours.text.trim()),
          billableHours: double.tryParse(_billable.text.trim()),
          projectName: _project.text,
          description: _description.text,
        );
      } else {
        await controller.log(
          workDate: _date,
          hoursWorked: double.parse(_hours.text.trim()),
          billableHours: double.tryParse(_billable.text.trim()),
          projectName: _project.text,
          description: _description.text,
        );
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _isEdit
                ? 'Entry updated.'
                : 'Logged. Submit it for review when ready.',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = _isEdit
            ? 'Could not update that entry.'
            : 'Could not log that entry.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

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
                'Log today\'s hours',
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
                controller: _hours,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Hours worked',
                  prefixIcon: Icon(Icons.schedule_outlined),
                ),
                validator: (value) {
                  final parsed = double.tryParse(value?.trim() ?? '');
                  if (parsed == null) return 'Enter the hours worked.';
                  if (parsed < 0) return 'Cannot be negative.';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _billable,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Billable hours (optional)',
                  prefixIcon: Icon(Icons.receipt_long_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return null;
                  return double.tryParse(value.trim()) == null
                      ? 'Enter a number.'
                      : null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _project,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Project (optional)',
                  prefixIcon: Icon(Icons.folder_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _description,
                textCapitalization: TextCapitalization.sentences,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'What did you work on (optional)',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
              const SizedBox(height: 18),
              LoadingButton(
                label: 'Log entry',
                loading: _submitting,
                icon: Icons.check_rounded,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
