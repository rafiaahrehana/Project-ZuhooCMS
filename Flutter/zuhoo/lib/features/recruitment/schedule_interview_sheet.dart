import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/date_field.dart';
import '../../shared/widgets/employee_picker.dart';
import '../../shared/widgets/primitives.dart';
import '../directory/directory_models.dart';
import 'recruitment_models.dart';
import 'recruitment_repository.dart';

/// Books an interview against an application.
///
/// Returns true when one was scheduled, so the caller can refresh both the
/// interview list and the application itself — the first round scheduled moves
/// the application to INTERVIEW_SCHEDULED, which the screen behind is showing.
/// Schedules an interview, or moves one.
///
/// Rescheduling takes the same shape as scheduling — `PUT` against the same
/// DTO — so it is the same form with the existing time filled in, rather than
/// a second one that would drift out of step.
Future<bool> showScheduleInterviewSheet(
  BuildContext context, {
  required int applicationId,
  Interview? existing,
}) async {
  final scheduled = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ScheduleInterviewSheet(
      applicationId: applicationId,
      existing: existing,
    ),
  );
  return scheduled ?? false;
}

class _ScheduleInterviewSheet extends ConsumerStatefulWidget {
  const _ScheduleInterviewSheet({
    required this.applicationId,
    this.existing,
  });

  final int applicationId;
  final Interview? existing;

  @override
  ConsumerState<_ScheduleInterviewSheet> createState() =>
      _ScheduleInterviewSheetState();
}

class _ScheduleInterviewSheetState
    extends ConsumerState<_ScheduleInterviewSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _duration = TextEditingController(
    text: '${widget.existing?.durationMinutes ?? 45}',
  );
  late final _meetingLink =
      TextEditingController(text: widget.existing?.meetingLink ?? '');

  late String _round = interviewRounds.contains(widget.existing?.round)
      ? widget.existing!.round!
      : interviewRounds.first;
  late String _mode = interviewModes.contains(widget.existing?.mode)
      ? widget.existing!.mode!
      : interviewModes.first;
  late DateTime? _date = Fmt.parse(widget.existing?.scheduledAt);
  late TimeOfDay? _time = _existingTime;

  /// The interviewer cannot be seeded from the row — it carries a name, not an
  /// id — so rescheduling asks for one again. The backend needs an id.
  Person? _interviewer;

  bool get _isEdit => widget.existing != null;

  TimeOfDay? get _existingTime {
    final parsed = Fmt.parse(widget.existing?.scheduledAt);
    if (parsed == null) return null;
    return TimeOfDay(hour: parsed.hour, minute: parsed.minute);
  }

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _duration.dispose();
    _meetingLink.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 10, minute: 0),
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _pickInterviewer() async {
    final person =
        await EmployeePicker.show(context, title: 'Who is interviewing?');
    if (person != null) setState(() => _interviewer = person);
  }

  /// `LocalDateTime` on the wire: a wall clock with no zone and no `Z`.
  ///
  /// Sending an instant would be read by the backend as a local time anyway,
  /// which would silently shift every interview by the offset of whoever
  /// booked it.
  String _scheduledAt(DateTime date, TimeOfDay time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${Fmt.isoDate(date)}T${two(time.hour)}:${two(time.minute)}:00';
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Neither of these is a text field, so the form validator cannot speak for
    // them — and the backend answers both with a bare 400 sentence.
    if (_date == null || _time == null) {
      setState(() => _error = 'Pick a date and a time for the interview.');
      return;
    }
    if (_interviewer == null) {
      setState(() => _error = 'Choose who is running the interview.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final request = InterviewRequest(
        jobApplicationId: widget.applicationId,
        scheduledAt: _scheduledAt(_date!, _time!),
        interviewerId: _interviewer!.id,
        round: _round,
        mode: _mode,
        durationMinutes: int.tryParse(_duration.text.trim()),
        meetingLink: _meetingLink.text,
      );
      final repo = ref.read(recruitmentRepositoryProvider);
      if (_isEdit) {
        await repo.rescheduleInterview(widget.existing!.id, request);
      } else {
        await repo.scheduleInterview(request);
      }
      if (!mounted) return;
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(_isEdit ? 'Interview moved.' : 'Interview scheduled.'),
        ),
      );
    } on ApiException catch (e) {
      // "This application is closed" lands here — a real answer, not a fault.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not schedule that interview.');
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
                _isEdit ? 'Move the interview' : 'Schedule an interview',
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
              DropdownButtonFormField<String>(
                initialValue: _round,
                decoration: const InputDecoration(
                  labelText: 'Round',
                  prefixIcon: Icon(Icons.layers_outlined),
                ),
                items: [
                  for (final round in interviewRounds)
                    DropdownMenuItem(
                      value: round,
                      child: Text(Fmt.label(round)),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _round = value ?? _round),
              ),
              const SizedBox(height: 16),
              DateField(
                label: 'Date',
                value: _date,
                enabled: !_submitting,
                // Interviews are booked ahead. A week back is allowed only so
                // one that happened can still be recorded after the fact.
                firstDate: now.subtract(const Duration(days: 7)),
                lastDate: DateTime(now.year + 1),
                emptyText: 'Pick a date',
                onChanged: (date) => setState(() => _date = date),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _submitting ? null : _pickTime,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Time',
                    prefixIcon: Icon(Icons.schedule_rounded),
                  ),
                  child: Text(
                    _time == null ? 'Pick a time' : _time!.format(context),
                    style: TextStyle(
                      color: _time == null ? bos.muted : bos.text,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _submitting ? null : _pickInterviewer,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Interviewer',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  child: Text(
                    _interviewer?.fullName ?? 'Choose a colleague',
                    style: TextStyle(
                      color: _interviewer == null ? bos.muted : bos.text,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _mode,
                decoration: const InputDecoration(
                  labelText: 'Mode',
                  prefixIcon: Icon(Icons.videocam_outlined),
                ),
                items: [
                  for (final mode in interviewModes)
                    DropdownMenuItem(
                      value: mode,
                      child: Text(Fmt.label(mode)),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _mode = value ?? _mode),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _duration,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Length (minutes)',
                  prefixIcon: Icon(Icons.timelapse_rounded),
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) return null;
                  final parsed = int.tryParse(trimmed);
                  if (parsed == null) return 'Enter a whole number of minutes.';
                  return parsed <= 0 ? 'Longer than nothing.' : null;
                },
              ),
              if (_mode != 'ONSITE') ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _meetingLink,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Meeting link (optional)',
                    prefixIcon: Icon(Icons.link_rounded),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              LoadingButton(
                label: _isEdit ? 'Move it' : 'Schedule',
                loading: _submitting,
                icon: Icons.event_available_rounded,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
