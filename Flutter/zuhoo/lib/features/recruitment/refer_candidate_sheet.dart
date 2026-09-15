import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/attachment_picker.dart';
import '../../shared/widgets/form_sheet.dart';
import '../../shared/widgets/primitives.dart';
import 'recruitment_models.dart';
import 'recruitment_repository.dart';

/// Putting somebody forward for a job.
///
/// The staff-side counterpart of the public careers form: a referral, or a CV
/// that arrived by email and needs to be in the pipeline rather than in
/// somebody's inbox.
Future<void> showReferCandidateSheet(
  BuildContext context, {
  required JobPosting job,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReferSheet(job: job),
    );

class _ReferSheet extends ConsumerStatefulWidget {
  const _ReferSheet({required this.job});

  final JobPosting job;

  @override
  ConsumerState<_ReferSheet> createState() => _ReferSheetState();
}

class _ReferSheetState extends ConsumerState<_ReferSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _linkedIn = TextEditingController();
  final _notes = TextEditingController();

  String _source = 'EMPLOYEE_REFERRAL';
  String? _resumeUrl;
  String? _resumeName;

  String? _error;
  bool _busy = false;
  bool _uploading = false;

  @override
  void dispose() {
    for (final controller in [_name, _email, _phone, _linkedIn, _notes]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _attachResume() async {
    final picked = await pickAttachment(context);
    if (picked == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      // The application carries a URL, not the file. Uploading first means a
      // failed upload costs nothing — no half-made application is left behind.
      final uploaded = await ref
          .read(apiClientProvider)
          .uploadDocument(picked.path, picked.name);
      setState(() {
        _resumeUrl = uploaded.fileUrl;
        _resumeName = uploaded.fileName;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not attach that file.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_email.text.trim().isEmpty && _phone.text.trim().isEmpty) {
      setState(() => _error = 'An email or a phone number, so somebody can '
          'get back to them.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(recruitmentRepositoryProvider).apply(
            widget.job.id,
            JobApplicationRequest(
              applicantName: _name.text,
              applicantEmail: _email.text,
              applicantPhone: _phone.text,
              linkedInUrl: _linkedIn.text,
              coverLetter: _notes.text,
              resumeUrl: _resumeUrl,
              source: _source,
            ),
          );
      ref.invalidate(openJobsProvider);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not record that application.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: 'Put somebody forward',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'Add to the pipeline',
      submitting: _busy,
      onSubmit: _submit,
      children: [
        Text(
          widget.job.title,
          style: TextStyle(
            color: bos.text,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Their name'),
          validator: (value) =>
              (value?.trim().isEmpty ?? true) ? 'A name, please.' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Phone'),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _linkedIn,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'LinkedIn'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _source,
          decoration: const InputDecoration(labelText: 'Where they came from'),
          items: [
            for (final value in applicationSources)
              DropdownMenuItem(value: value, child: Text(Fmt.label(value))),
          ],
          onChanged: (value) => setState(() => _source = value ?? _source),
        ),
        const SizedBox(height: 12),
        if (_uploading)
          const Loader(padding: 10)
        else
          OutlinedButton.icon(
            onPressed: _attachResume,
            icon: const Icon(Icons.attach_file_rounded, size: 17),
            label: Text(_resumeName ?? 'Attach a CV'),
          ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _notes,
          maxLines: 4,
          minLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Why them',
            hintText: 'What the recruiter should know.',
          ),
        ),
        const SizedBox(height: 10),
        Text(
          // Worth saying plainly: the backend attributes a referral to
          // whoever is signed in and offers no way to credit somebody else.
          'A referral is recorded against you. It cannot be attributed to '
          'anybody else.',
          style: TextStyle(color: bos.muted, fontSize: 11.5, height: 1.5),
        ),
      ],
    );
  }
}
