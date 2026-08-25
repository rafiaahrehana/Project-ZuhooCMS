import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'recruitment_models.dart';
import 'recruitment_repository.dart';

/// What the sheet is editing.
///
/// The three cases share one form because a person's details are the same
/// details wherever they are filed — but **not** one request body. The backend
/// has two unrelated DTOs both named `CandidateRequest`: a candidate carries a
/// current title, a portfolio link and a source; a pool entry carries a desired
/// role, a rating and a reason, and must have an email. So the form varies by
/// mode and builds whichever body the endpoint actually takes.
enum _Mode { editCandidate, addToPool, editPoolEntry }

extension on _Mode {
  bool get isPool => this != _Mode.editCandidate;
}

/// Edits a candidate's own record. Returns the server's version, or null if
/// dismissed — the detail screen holds its own copy and needs it back.
Future<Candidate?> showEditCandidateSheet(
  BuildContext context,
  Candidate candidate,
) {
  return showModalBottomSheet<Candidate>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CandidateFormSheet(
      mode: _Mode.editCandidate,
      candidateId: candidate.id,
      initial: CandidateRequest.from(candidate),
    ),
  );
}

/// Puts somebody in the talent pool who never applied — a referral, or a name
/// worth keeping from outside the funnel.
Future<void> showAddToTalentPoolSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _CandidateFormSheet(mode: _Mode.addToPool),
  );
}

Future<void> showEditTalentPoolSheet(
  BuildContext context,
  TalentPoolCandidate entry,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CandidateFormSheet(
      mode: _Mode.editPoolEntry,
      candidateId: entry.id,
      pool: TalentPoolRequest.from(entry),
    ),
  );
}

class _CandidateFormSheet extends ConsumerStatefulWidget {
  const _CandidateFormSheet({
    required this.mode,
    this.candidateId,
    this.initial,
    this.pool,
  });

  final _Mode mode;
  final int? candidateId;

  /// Seed for the candidate modes.
  final CandidateRequest? initial;

  /// Seed for the talent-pool modes.
  final TalentPoolRequest? pool;

  @override
  ConsumerState<_CandidateFormSheet> createState() =>
      _CandidateFormSheetState();
}

class _CandidateFormSheetState extends ConsumerState<_CandidateFormSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _currentTitle;
  late final TextEditingController _skills;
  late final TextEditingController _resumeUrl;
  late final TextEditingController _linkedIn;
  late final TextEditingController _portfolio;
  late final TextEditingController _notes;

  String? _source;
  String? _reason;
  int? _rating;

  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Only one of the two seeds is ever set, and which one depends on which
    // endpoint this sheet is going to call.
    final initial = widget.initial;
    final pool = widget.pool;

    _name = TextEditingController(text: pool?.name ?? initial?.name ?? '');
    _email = TextEditingController(text: pool?.email ?? initial?.email ?? '');
    _phone = TextEditingController(text: pool?.phone ?? initial?.phone ?? '');
    _currentTitle = TextEditingController(
      text: pool?.desiredRole ?? initial?.currentTitle ?? '',
    );
    _skills = TextEditingController(text: pool?.skills ?? initial?.skills ?? '');
    _resumeUrl =
        TextEditingController(text: pool?.resumeUrl ?? initial?.resumeUrl ?? '');
    _linkedIn = TextEditingController(
      text: pool?.linkedInUrl ?? initial?.linkedInUrl ?? '',
    );
    _portfolio = TextEditingController(text: initial?.portfolioUrl ?? '');
    _notes = TextEditingController(text: pool?.notes ?? initial?.notes ?? '');
    _source = initial?.source;
    _reason = pool?.reason;
    _rating = pool?.rating;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _currentTitle.dispose();
    _skills.dispose();
    _resumeUrl.dispose();
    _linkedIn.dispose();
    _portfolio.dispose();
    _notes.dispose();
    super.dispose();
  }

  String get _title => switch (widget.mode) {
        _Mode.editCandidate => 'Edit candidate',
        _Mode.addToPool => 'Add to talent pool',
        _Mode.editPoolEntry => 'Edit pool entry',
      };

  String get _action => switch (widget.mode) {
        _Mode.editCandidate => 'Save changes',
        _Mode.addToPool => 'Add to pool',
        _Mode.editPoolEntry => 'Save changes',
      };

  String get _done => switch (widget.mode) {
        _Mode.editCandidate => 'Candidate updated.',
        _Mode.addToPool => 'Added to the talent pool.',
        _Mode.editPoolEntry => 'Pool entry updated.',
      };

  CandidateRequest _candidateRequest() => CandidateRequest(
        name: _name.text,
        email: _email.text,
        phone: _phone.text,
        currentTitle: _currentTitle.text,
        skills: _skills.text,
        source: _source,
        resumeUrl: _resumeUrl.text,
        linkedInUrl: _linkedIn.text,
        portfolioUrl: _portfolio.text,
        notes: _notes.text,
      );

  TalentPoolRequest _poolRequest() => TalentPoolRequest(
        name: _name.text,
        email: _email.text,
        phone: _phone.text,
        // The same box, meaning a different thing: a candidate's current job
        // versus the job a pooled person is being kept in mind for.
        desiredRole: _currentTitle.text,
        skills: _skills.text,
        resumeUrl: _resumeUrl.text,
        linkedInUrl: _linkedIn.text,
        rating: _rating,
        reason: _reason,
        notes: _notes.text,
      );

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      switch (widget.mode) {
        case _Mode.editCandidate:
          final updated = await ref
              .read(candidatesProvider.notifier)
              .updateItem(widget.candidateId!, _candidateRequest());
          if (!mounted) return;
          navigator.pop(updated);
        case _Mode.addToPool:
          await ref.read(talentPoolProvider.notifier).add(_poolRequest());
          if (!mounted) return;
          navigator.pop();
        case _Mode.editPoolEntry:
          await ref
              .read(talentPoolProvider.notifier)
              .updateItem(widget.candidateId!, _poolRequest());
          if (!mounted) return;
          navigator.pop();
      }
      messenger.showSnackBar(SnackBar(content: Text(_done)));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save those details.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final sources = _source == null || applicationSources.contains(_source)
        ? applicationSources
        : [_source!, ...applicationSources];

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
                _title,
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
                controller: _name,
                autofocus: widget.mode == _Mode.addToPool,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Who is this?'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText:
                      widget.mode.isPool ? 'Email' : 'Email (optional)',
                  prefixIcon: const Icon(Icons.alternate_email_rounded),
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) {
                    // The talent pool endpoint validates this and then calls
                    // .trim() on it regardless, so an empty one is a 400.
                    return widget.mode.isPool ? 'An email is required.' : null;
                  }
                  return trimmed.contains('@') ? null : 'That is not an email.';
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone (optional)',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _currentTitle,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: widget.mode == _Mode.editCandidate
                      ? 'Current job title (optional)'
                      : 'Role they are wanted for (optional)',
                  prefixIcon: const Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _skills,
                textCapitalization: TextCapitalization.words,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Skills (optional)',
                  hintText: 'Flutter, Kotlin, REST',
                  alignLabelWithHint: true,
                ),
              ),
              if (!widget.mode.isPool) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _source,
                  decoration: const InputDecoration(
                    labelText: 'Source (optional)',
                    prefixIcon: Icon(Icons.input_rounded),
                  ),
                  items: [
                    for (final source in sources)
                      DropdownMenuItem(
                        value: source,
                        child: Text(Fmt.label(source)),
                      ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _source = value),
                ),
              ],
              if (widget.mode.isPool) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _reason,
                  decoration: const InputDecoration(
                    labelText: 'Why they are in the pool (optional)',
                    prefixIcon: Icon(Icons.bookmark_border_rounded),
                  ),
                  items: [
                    for (final reason in talentPoolReasons)
                      DropdownMenuItem(
                        value: reason,
                        child: Text(Fmt.label(reason)),
                      ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _reason = value),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int?>(
                  initialValue: _rating,
                  decoration: const InputDecoration(
                    labelText: 'Rating (optional)',
                    prefixIcon: Icon(Icons.star_border_rounded),
                  ),
                  // A dropdown rather than a free number field because the
                  // backend refuses anything outside 1-5, and a picker cannot
                  // produce a 7.
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Not rated')),
                    DropdownMenuItem(value: 1, child: Text('1')),
                    DropdownMenuItem(value: 2, child: Text('2')),
                    DropdownMenuItem(value: 3, child: Text('3')),
                    DropdownMenuItem(value: 4, child: Text('4')),
                    DropdownMenuItem(value: 5, child: Text('5')),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _rating = value),
                ),
              ],
              const SizedBox(height: 22),
              const SectionHeader('Links', icon: Icons.link_rounded),
              const SizedBox(height: 12),
              TextFormField(
                controller: _resumeUrl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'CV (optional)'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _linkedIn,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration:
                    const InputDecoration(labelText: 'LinkedIn (optional)'),
              ),
              if (!widget.mode.isPool) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _portfolio,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration:
                      const InputDecoration(labelText: 'Portfolio (optional)'),
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _notes,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 18),
              LoadingButton(
                label: _action,
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
