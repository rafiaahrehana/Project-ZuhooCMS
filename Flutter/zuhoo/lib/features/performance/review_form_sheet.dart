import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/date_field.dart';
import '../../shared/widgets/employee_picker.dart';
import '../../shared/widgets/primitives.dart';
import '../directory/directory_models.dart';
import 'performance_models.dart';
import 'performance_repository.dart';

/// Opens a review on somebody.
Future<void> showNewReviewSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _ReviewFormSheet(),
  );
}

/// Edits the scores and write-ups on one, and hands back the server's version.
///
/// Returns null if dismissed. The detail screen keeps its own copy, and the
/// overall score is recomputed server-side on every write, so it needs the
/// response rather than its own arithmetic.
Future<PerformanceReview?> showEditReviewSheet(
  BuildContext context,
  PerformanceReview review,
) {
  return showModalBottomSheet<PerformanceReview>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ReviewFormSheet(existing: review),
  );
}

class _ReviewFormSheet extends ConsumerStatefulWidget {
  const _ReviewFormSheet({this.existing});

  final PerformanceReview? existing;

  @override
  ConsumerState<_ReviewFormSheet> createState() => _ReviewFormSheetState();
}

class _ReviewFormSheetState extends ConsumerState<_ReviewFormSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _strengths;
  late final TextEditingController _improvements;
  late final TextEditingController _goals;
  late final TextEditingController _comments;
  late final TextEditingController _performanceLevel;
  late final TextEditingController _promotion;
  late final TextEditingController _training;
  late final TextEditingController _recognition;

  final Map<String, int?> _scores = {};
  Person? _employee;
  DateTime? _periodStart;
  DateTime? _periodEnd;
  int? _goalPercent;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final seed = existing == null
        ? const PerformanceReviewRequest()
        : PerformanceReviewRequest.from(existing);

    for (final competency in reviewCompetencies) {
      _scores[competency.key] = seed.scores[competency.key];
    }
    _strengths = TextEditingController(text: seed.strengths ?? '');
    _improvements = TextEditingController(text: seed.areasForImprovement ?? '');
    _goals = TextEditingController(text: seed.goalsForNextPeriod ?? '');
    _comments = TextEditingController(text: seed.comments ?? '');
    _performanceLevel = TextEditingController(text: seed.performanceLevel ?? '');
    _promotion =
        TextEditingController(text: seed.promotionRecommendation ?? '');
    _training = TextEditingController(text: seed.trainingRecommendation ?? '');
    _recognition = TextEditingController(text: seed.recognition ?? '');
    _goalPercent = seed.goalCompletionPercent;

    if (existing == null) {
      // Default to the quarter that has just finished, which is what most
      // reviews are actually about.
      final now = DateTime.now();
      _periodEnd = DateTime(now.year, now.month, 1).subtract(
        const Duration(days: 1),
      );
      _periodStart = DateTime(_periodEnd!.year, _periodEnd!.month - 2, 1);
    }
  }

  @override
  void dispose() {
    _strengths.dispose();
    _improvements.dispose();
    _goals.dispose();
    _comments.dispose();
    _performanceLevel.dispose();
    _promotion.dispose();
    _training.dispose();
    _recognition.dispose();
    super.dispose();
  }

  Future<void> _pickEmployee() async {
    final person = await EmployeePicker.show(context, title: 'Review whom?');
    if (person != null) setState(() => _employee = person);
  }

  PerformanceReviewRequest _buildRequest() => PerformanceReviewRequest(
        // All three are create-only; the update path ignores them.
        employeeId: _isEdit ? null : _employee?.id,
        reviewPeriodStart: _isEdit || _periodStart == null
            ? null
            : Fmt.isoDate(_periodStart!),
        reviewPeriodEnd:
            _isEdit || _periodEnd == null ? null : Fmt.isoDate(_periodEnd!),
        scores: _scores,
        strengths: _strengths.text,
        areasForImprovement: _improvements.text,
        goalsForNextPeriod: _goals.text,
        comments: _comments.text,
        performanceLevel: _performanceLevel.text,
        promotionRecommendation: _promotion.text,
        trainingRecommendation: _training.text,
        recognition: _recognition.text,
        goalCompletionPercent: _goalPercent,
      );

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (!_isEdit) {
      if (_employee == null) {
        setState(() => _error = 'Choose who the review is for.');
        return;
      }
      if (_periodStart == null || _periodEnd == null) {
        setState(() => _error = 'Set the period the review covers.');
        return;
      }
      if (_periodEnd!.isBefore(_periodStart!)) {
        setState(() => _error = 'The period ends before it starts.');
        return;
      }
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final controller = ref.read(teamReviewsProvider.notifier);
    try {
      if (_isEdit) {
        final updated =
            await controller.updateItem(widget.existing!.id, _buildRequest());
        if (!mounted) return;
        navigator.pop(updated);
        messenger.showSnackBar(
          const SnackBar(content: Text('Review updated.')),
        );
      } else {
        await controller.create(_buildRequest());
        if (!mounted) return;
        navigator.pop();
        messenger.showSnackBar(const SnackBar(content: Text('Review opened.')));
      }
    } on ApiException catch (e) {
      // "Employee profile not found" lands here when the signed-in user has no
      // employee record of their own — a reviewer has to be an employee.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            _isEdit ? 'Could not save that review.' : 'Could not open that review.');
      }
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
                _isEdit ? 'Edit review' : 'New review',
                style: TextStyle(
                  color: bos.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (_isEdit && widget.existing?.employeeName != null) ...[
                const SizedBox(height: 4),
                Text(
                  widget.existing!.employeeName!,
                  style: TextStyle(color: bos.muted, fontSize: 13),
                ),
              ],
              const SizedBox(height: 18),
              if (_error != null) ...[
                MessageBanner.error(
                  _error!,
                  onDismiss: () => setState(() => _error = null),
                ),
                const SizedBox(height: 14),
              ],
              if (!_isEdit) ...[
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
                DateField(
                  label: 'Period from',
                  value: _periodStart,
                  enabled: !_submitting,
                  firstDate: DateTime(now.year - 3),
                  lastDate: now,
                  clearable: false,
                  onChanged: (date) => setState(() => _periodStart = date),
                ),
                const SizedBox(height: 16),
                DateField(
                  label: 'Period to',
                  value: _periodEnd,
                  enabled: !_submitting,
                  firstDate: DateTime(now.year - 3),
                  lastDate: now,
                  clearable: false,
                  onChanged: (date) => setState(() => _periodEnd = date),
                ),
                const SizedBox(height: 22),
              ],
              const SectionHeader('Scores', icon: Icons.speed_rounded),
              const SizedBox(height: 4),
              Text(
                'Out of ten. Leave one blank and it is left out of the average '
                'rather than counted as zero.',
                style: TextStyle(color: bos.muted, fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 8),
              for (final competency in reviewCompetencies)
                _ScoreRow(
                  label: competency.label,
                  value: _scores[competency.key],
                  enabled: !_submitting,
                  onChanged: (value) =>
                      setState(() => _scores[competency.key] = value),
                ),
              const SizedBox(height: 18),
              const SectionHeader('Write-up', icon: Icons.notes_rounded),
              const SizedBox(height: 12),
              TextFormField(
                controller: _strengths,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Strengths',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _improvements,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Areas for improvement',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _goals,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Goals for next period',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _comments,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Comments',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 22),
              const SectionHeader(
                'Recommendations',
                icon: Icons.trending_up_rounded,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _performanceLevel,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Performance level (optional)',
                  hintText: 'Exceeds expectations',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _promotion,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Promotion recommendation (optional)',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _training,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Training recommendation (optional)',
                  hintText: 'Comma separated',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _recognition,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Recognition (optional)',
                  hintText: 'Comma separated',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int?>(
                initialValue: _goalPercent,
                decoration: const InputDecoration(
                  labelText: 'Goals completed (optional)',
                  prefixIcon: Icon(Icons.percent_rounded),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Not set')),
                  for (var percent = 0; percent <= 100; percent += 10)
                    DropdownMenuItem(value: percent, child: Text('$percent%')),
                ],
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _goalPercent = value),
              ),
              const SizedBox(height: 18),
              LoadingButton(
                label: _isEdit ? 'Save review' : 'Open review',
                loading: _submitting,
                icon: _isEdit ? Icons.check_rounded : Icons.add_rounded,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One competency, scored out of ten.
///
/// A dropdown rather than a slider or a free number field: the range is fixed,
/// "not scored" has to stay reachable, and a slider cannot express it.
class _ScoreRow extends StatelessWidget {
  const _ScoreRow({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final int? value;
  final bool enabled;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: bos.text, fontSize: 14),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 116,
            child: DropdownButtonFormField<int?>(
              initialValue: value,
              isDense: true,
              decoration: const InputDecoration(
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('—')),
                for (var score = 1; score <= 10; score++)
                  DropdownMenuItem(value: score, child: Text('$score')),
              ],
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ],
      ),
    );
  }
}
