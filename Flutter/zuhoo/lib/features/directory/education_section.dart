import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/widgets/form_sheet.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import '../profile/employee_repository.dart';
import 'directory_models.dart';

/// A degree somebody holds. Mirrors `EducationQualificationResponse`.
class Qualification {
  const Qualification({
    required this.id,
    required this.degree,
    this.institution,
    this.fieldOfStudy,
    this.passingYear,
    this.result,
    this.notes,
  });

  final int id;
  final String degree;
  final String? institution;
  final String? fieldOfStudy;
  final int? passingYear;
  final String? result;
  final String? notes;

  factory Qualification.fromJson(Map<String, dynamic> json) => Qualification(
        id: (json['id'] as num?)?.toInt() ?? 0,
        degree: json['degree'] as String? ?? '',
        institution: json['institution'] as String?,
        fieldOfStudy: json['fieldOfStudy'] as String?,
        passingYear: (json['passingYear'] as num?)?.toInt(),
        result: json['result'] as String?,
        notes: json['notes'] as String?,
      );
}

/// Recording or changing a qualification.
///
/// Every field is sent whether or not it changed: `update` assigns all six
/// without a null check, so an omitted institution or year is cleared rather
/// than left alone. The employee id is only read on create — an existing
/// qualification cannot be moved to somebody else.
class QualificationRequest {
  const QualificationRequest({
    required this.employeeId,
    required this.degree,
    this.institution,
    this.fieldOfStudy,
    this.passingYear,
    this.result,
    this.notes,
  });

  final int employeeId;
  final String degree;
  final String? institution;
  final String? fieldOfStudy;
  final int? passingYear;
  final String? result;
  final String? notes;

  Map<String, dynamic> toJson() => {
        'employeeId': employeeId,
        'degree': degree,
        'institution': institution,
        'fieldOfStudy': fieldOfStudy,
        'passingYear': passingYear,
        'result': result,
        'notes': notes,
      };
}

class EducationRepository {
  EducationRepository(this._api);

  final ApiClient _api;

  static const _base = '/hr/education-qualifications';

  /// A bare list, newest first as the backend orders it.
  Future<List<Qualification>> forEmployee(int employeeId) async {
    final list = await _api.get<List<dynamic>>('$_base/employee/$employeeId');
    return list
        .whereType<Map<String, dynamic>>()
        .map(Qualification.fromJson)
        .toList(growable: false);
  }

  Future<Qualification> create(QualificationRequest request) async {
    final json = await _api.post<Map<String, dynamic>>(_base, request.toJson());
    return Qualification.fromJson(json);
  }

  Future<Qualification> update(int id, QualificationRequest request) async {
    final json =
        await _api.put<Map<String, dynamic>>('$_base/$id', request.toJson());
    return Qualification.fromJson(json);
  }

  Future<void> delete(int id) => _api.delete<dynamic>('$_base/$id');
}

final educationRepositoryProvider = Provider<EducationRepository>(
  (ref) => EducationRepository(ref.watch(apiClientProvider)),
);

final qualificationsProvider =
    FutureProvider.autoDispose.family<List<Qualification>, int>(
  (ref, employeeId) =>
      ref.read(educationRepositoryProvider).forEmployee(employeeId),
);

/// What somebody studied.
///
/// Anybody may add to their own record; changing somebody else's needs
/// EMPLOYEE_UPDATE. The backend falls back to "your own" when the permission
/// is absent, and this mirrors that rather than hiding the section from people
/// looking at themselves.
class EducationSection extends ConsumerStatefulWidget {
  const EducationSection({super.key, required this.employeeId});

  final int employeeId;

  @override
  ConsumerState<EducationSection> createState() => _EducationSectionState();
}

class _EducationSectionState extends ConsumerState<EducationSection> {
  bool _busy = false;

  Future<void> _delete(Qualification qualification) async {
    final confirmed = await confirmAction(
      context,
      title: 'Remove ${qualification.degree}?',
      message: 'It stops appearing on this profile.',
      action: 'Remove',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(educationRepositoryProvider).delete(qualification.id);
      ref.invalidate(qualificationsProvider(widget.employeeId));
      messenger.showSnackBar(const SnackBar(content: Text('Removed.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not remove that.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(qualificationsProvider(widget.employeeId));

    // Either the permission, or this being your own record. The endpoint
    // checks exactly that pair.
    final canEdit = ref
            .watch(permissionControllerProvider)
            .has(DirectoryPermissions.employeeUpdate) ||
        ref.watch(myEmployeeProvider).value?.id == widget.employeeId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Education',
          icon: Icons.school_outlined,
          trailing: canEdit && !_busy
              ? TextButton.icon(
                  onPressed: () => showQualificationSheet(
                    context,
                    employeeId: widget.employeeId,
                  ),
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: const Text('Add'),
                )
              : null,
        ),
        AppCard(
          child: _busy
              ? const Loader(padding: 12)
              : async.when(
                  loading: () => const Loader(padding: 12),
                  // A profile is still worth reading without this section, so
                  // a failure here is a note rather than an error state.
                  error: (_, _) => Text(
                    'The education record could not be loaded.',
                    style: TextStyle(color: bos.muted, fontSize: 13),
                  ),
                  data: (qualifications) => qualifications.isEmpty
                      ? Text(
                          'Nothing recorded.',
                          style: TextStyle(color: bos.muted, fontSize: 13),
                        )
                      : Column(
                          children: [
                            for (final qualification in qualifications)
                              _QualificationRow(
                                qualification: qualification,
                                employeeId: widget.employeeId,
                                canEdit: canEdit,
                                onDelete: () => _delete(qualification),
                              ),
                          ],
                        ),
                ),
        ),
      ],
    );
  }
}

class _QualificationRow extends StatelessWidget {
  const _QualificationRow({
    required this.qualification,
    required this.employeeId,
    required this.canEdit,
    required this.onDelete,
  });

  final Qualification qualification;
  final int employeeId;
  final bool canEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    final facts = <String>[
      if (qualification.institution != null) qualification.institution!,
      if (qualification.passingYear != null) '${qualification.passingYear}',
      if (qualification.result != null) qualification.result!,
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    qualification.degree,
                    if (qualification.fieldOfStudy != null)
                      qualification.fieldOfStudy!,
                  ].join(', '),
                  style: TextStyle(color: bos.text, fontSize: 13.5),
                ),
                if (facts.isNotEmpty)
                  Text(
                    facts.join('  ·  '),
                    style: TextStyle(color: bos.muted, fontSize: 11.5),
                  ),
                if (qualification.notes != null &&
                    qualification.notes!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      qualification.notes!,
                      style: TextStyle(
                        color: bos.muted,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (canEdit)
            PopupMenuButton<String>(
              onSelected: (value) => value == 'edit'
                  ? showQualificationSheet(
                      context,
                      employeeId: employeeId,
                      qualification: qualification,
                    )
                  : onDelete(),
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Remove', style: TextStyle(color: bos.danger)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

Future<void> showQualificationSheet(
  BuildContext context, {
  required int employeeId,
  Qualification? qualification,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _QualificationSheet(
        employeeId: employeeId,
        qualification: qualification,
      ),
    );

class _QualificationSheet extends ConsumerStatefulWidget {
  const _QualificationSheet({required this.employeeId, this.qualification});

  final int employeeId;
  final Qualification? qualification;

  @override
  ConsumerState<_QualificationSheet> createState() =>
      _QualificationSheetState();
}

class _QualificationSheetState extends ConsumerState<_QualificationSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _degree =
      TextEditingController(text: widget.qualification?.degree ?? '');
  late final _institution =
      TextEditingController(text: widget.qualification?.institution ?? '');
  late final _field =
      TextEditingController(text: widget.qualification?.fieldOfStudy ?? '');
  late final _year = TextEditingController(
    text: widget.qualification?.passingYear?.toString() ?? '',
  );
  late final _result =
      TextEditingController(text: widget.qualification?.result ?? '');
  late final _notes =
      TextEditingController(text: widget.qualification?.notes ?? '');

  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final controller in [
      _degree,
      _institution,
      _field,
      _year,
      _result,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _clean(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final request = QualificationRequest(
      employeeId: widget.employeeId,
      degree: _degree.text.trim(),
      institution: _clean(_institution),
      fieldOfStudy: _clean(_field),
      passingYear: int.tryParse(_year.text.trim()),
      result: _clean(_result),
      notes: _clean(_notes),
    );

    try {
      final repo = ref.read(educationRepositoryProvider);
      if (widget.qualification == null) {
        await repo.create(request);
      } else {
        await repo.update(widget.qualification!.id, request);
      }
      ref.invalidate(qualificationsProvider(widget.employeeId));
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not save that.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: widget.qualification == null
          ? 'Add a qualification'
          : 'Edit qualification',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'Save',
      submitting: _busy,
      onSubmit: _submit,
      children: [
        TextFormField(
          controller: _degree,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Degree',
            hintText: 'BSc, MBA, Diploma',
          ),
          validator: (value) =>
              (value?.trim().isEmpty ?? true) ? 'A degree, please.' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _field,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Subject'),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _institution,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Where'),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _year,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Year'),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return null;
                  final year = int.tryParse(text);
                  if (year == null || year < 1900 || year > 2100) {
                    return 'A four-digit year.';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _result,
                decoration: const InputDecoration(
                  labelText: 'Result',
                  hintText: 'First, 3.8, Merit',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _notes,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Notes'),
        ),
        const SizedBox(height: 10),
        Text(
          'Everything here is saved as it stands, blanks included. Clearing a '
          'box removes what was there.',
          style: TextStyle(color: bos.muted, fontSize: 11.5, height: 1.5),
        ),
      ],
    );
  }
}
