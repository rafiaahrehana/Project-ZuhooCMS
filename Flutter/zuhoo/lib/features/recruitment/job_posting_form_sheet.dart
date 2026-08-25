import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/date_field.dart';
import '../../shared/widgets/primitives.dart';
import '../directory/directory_models.dart' show employmentTypes;
import 'recruitment_models.dart';
import 'recruitment_repository.dart';

/// Opens a job posting, or edits one.
///
/// The skills list, the education floor and the recruiter assignment are not
/// here — the first two are wide repeaters that stay on the web, and the
/// recruiter is set from the posting's own row, where a picker belongs. What a
/// phone is for is getting a vacancy written down while it is being agreed,
/// and fixing the wording afterwards.
Future<void> showNewJobPostingSheet(
  BuildContext context, {
  JobPosting? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _JobPostingFormSheet(existing: existing),
  );
}

class _JobPostingFormSheet extends ConsumerStatefulWidget {
  const _JobPostingFormSheet({this.existing});

  final JobPosting? existing;

  @override
  ConsumerState<_JobPostingFormSheet> createState() =>
      _JobPostingFormSheetState();
}

class _JobPostingFormSheetState extends ConsumerState<_JobPostingFormSheet> {
  final _formKey = GlobalKey<FormState>();

  /// A plain number for a money field — `Fmt.money` adds a symbol that would
  /// not parse back out.
  static String _plain(num? value) => value == null
      ? ''
      : (value == value.roundToDouble() ? '${value.round()}' : '$value');

  late final _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final _jobTitle =
      TextEditingController(text: widget.existing?.jobTitle ?? '');
  late final _location =
      TextEditingController(text: widget.existing?.location ?? '');
  late final _vacancies =
      TextEditingController(text: '${widget.existing?.vacancies ?? 1}');
  late final _salaryMin =
      TextEditingController(text: _plain(widget.existing?.salaryMin));
  late final _salaryMax =
      TextEditingController(text: _plain(widget.existing?.salaryMax));
  late final _description =
      TextEditingController(text: widget.existing?.description ?? '');
  late final _requirements =
      TextEditingController(text: widget.existing?.requirements ?? '');
  late final _responsibilities =
      TextEditingController(text: widget.existing?.responsibilities ?? '');

  late String _employmentType =
      employmentTypes.contains(widget.existing?.employmentType)
          ? widget.existing!.employmentType!
          : employmentTypes.first;
  late DateTime? _deadline = Fmt.parse(widget.existing?.deadline);
  late bool _remote = widget.existing?.remote ?? false;

  bool get _isEdit => widget.existing != null;

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _jobTitle.dispose();
    _location.dispose();
    _vacancies.dispose();
    _salaryMin.dispose();
    _salaryMax.dispose();
    _description.dispose();
    _requirements.dispose();
    _responsibilities.dispose();
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

    final messenger = ScaffoldMessenger.of(context);
    final request = JobPostingRequest(
      title: _title.text,
      jobTitle: _jobTitle.text,
      location: _location.text,
      employmentType: _employmentType,
      vacancies: int.tryParse(_vacancies.text.trim()),
      salaryMin: double.tryParse(_salaryMin.text.trim()),
      salaryMax: double.tryParse(_salaryMax.text.trim()),
      deadline: _deadline == null ? null : Fmt.isoDate(_deadline!),
      remote: _remote,
      description: _description.text,
      requirements: _requirements.text,
      responsibilities: _responsibilities.text,
    );

    try {
      if (_isEdit) {
        await ref
            .read(jobsProvider.notifier)
            .update(widget.existing!.id, request);
      } else {
        await ref.read(jobsProvider.notifier).create(request);
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _isEdit
                ? 'Posting updated.'
                : 'Saved as a draft. Publish it when ready.',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save that posting.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final now = DateTime.now();

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
                _isEdit ? 'Edit posting' : 'New job posting',
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
                controller: _title,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Posting title',
                  hintText: 'Senior Flutter Engineer — Dhaka',
                  prefixIcon: Icon(Icons.work_outline_rounded),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Give the posting a title.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _jobTitle,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Job title (optional)',
                  hintText: 'What the role is called internally',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _employmentType,
                decoration: const InputDecoration(
                  labelText: 'Employment type',
                  prefixIcon: Icon(Icons.schedule_rounded),
                ),
                items: [
                  for (final type in employmentTypes)
                    DropdownMenuItem(value: type, child: Text(Fmt.label(type))),
                ],
                onChanged: _submitting
                    ? null
                    : (value) =>
                        setState(() => _employmentType = value ?? _employmentType),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _location,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Location (optional)',
                  prefixIcon: Icon(Icons.place_outlined),
                ),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                value: _remote,
                onChanged:
                    _submitting ? null : (value) => setState(() => _remote = value),
                title: Text(
                  'Remote',
                  style: TextStyle(color: bos.text, fontSize: 14.5),
                ),
                contentPadding: EdgeInsets.zero,
                // Same as every other switch in the app: white thumb, themed
                // track. See `_Switch` in the notification preferences screen.
                activeThumbColor: Colors.white,
              ),
              const SizedBox(height: 4),
              TextFormField(
                controller: _vacancies,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Vacancies',
                  prefixIcon: Icon(Icons.groups_outlined),
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) return null;
                  final parsed = int.tryParse(trimmed);
                  if (parsed == null) return 'Enter a whole number.';
                  return parsed < 1 ? 'At least one.' : null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _salaryMin,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Salary from'),
                      validator: _money,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _salaryMax,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'to'),
                      validator: (value) {
                        final basic = _money(value);
                        if (basic != null) return basic;
                        final min = double.tryParse(_salaryMin.text.trim());
                        final max = double.tryParse(value?.trim() ?? '');
                        if (min != null && max != null && max < min) {
                          return 'Below the minimum.';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DateField(
                label: 'Applications close (optional)',
                value: _deadline,
                enabled: !_submitting,
                // A deadline that has already passed closes the posting to
                // applicants the moment it is published, so this only opens
                // forward.
                firstDate: now,
                lastDate: DateTime(now.year + 3),
                onChanged: (date) => setState(() => _deadline = date),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _description,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _responsibilities,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Responsibilities (optional)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _requirements,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Requirements (optional)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 18),
              LoadingButton(
                label: _isEdit ? 'Save changes' : 'Save draft',
                loading: _submitting,
                icon: Icons.save_outlined,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String? _money(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final parsed = double.tryParse(trimmed);
    if (parsed == null) return 'Enter a number.';
    return parsed < 0 ? 'Cannot be negative.' : null;
  }
}
