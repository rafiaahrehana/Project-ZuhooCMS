import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/widgets/employee_picker.dart';
import '../../shared/widgets/primitives.dart';
import '../directory/directory_models.dart';
import 'itam_models.dart';
import 'itam_repository.dart';

/// Opens a leaver's checklist.
///
/// Short by design: only the employee is required. The five steps — hardware
/// back, licences revoked, access revoked, data handed over, exit interview —
/// start unticked and are worked through afterwards, which is what the
/// offboarding tab is for.
Future<void> showStartOffboardingSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _StartOffboardingSheet(),
  );
}

class _StartOffboardingSheet extends ConsumerStatefulWidget {
  const _StartOffboardingSheet();

  @override
  ConsumerState<_StartOffboardingSheet> createState() =>
      _StartOffboardingSheetState();
}

class _StartOffboardingSheetState
    extends ConsumerState<_StartOffboardingSheet> {
  final _notes = TextEditingController();
  Person? _employee;

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickEmployee() async {
    final person = await EmployeePicker.show(context, title: 'Who is leaving?');
    if (person != null) setState(() => _employee = person);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_employee == null) {
      setState(() => _error = 'Choose who is leaving.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(offboardingProvider.notifier).create(
            OffboardingChecklistRequest(
              employeeId: _employee!.id,
              notes: _notes.text,
            ),
          );
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Offboarding started for ${_employee!.fullName}.'),
        ),
      );
    } on ApiException catch (e) {
      // A checklist already open for that person lands here.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not start that offboarding.');
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Start offboarding',
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
              onTap: _submitting ? null : _pickEmployee,
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Employee',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                child: Text(
                  _employee?.fullName ?? 'Choose a colleague',
                  style: TextStyle(
                    color: _employee == null ? bos.muted : bos.text,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notes,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'Last day, handover arrangements…',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 18),
            LoadingButton(
              label: 'Start offboarding',
              loading: _submitting,
              icon: Icons.logout_rounded,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
