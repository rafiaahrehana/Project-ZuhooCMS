import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/date_field.dart';
import '../../shared/widgets/employee_picker.dart';
import '../../shared/widgets/primitives.dart';
import 'directory_models.dart';
import 'directory_repository.dart';

/// Adds a colleague, and the login they will sign in with.
Future<void> showNewEmployeeSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _EmployeeFormSheet(),
  );
}

/// Edits one. Returns nothing — the detail screen watches `personProvider`,
/// which the controller invalidates on success.
Future<void> showEditEmployeeSheet(BuildContext context, Person person) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EmployeeFormSheet(existing: person),
  );
}

class _EmployeeFormSheet extends ConsumerStatefulWidget {
  const _EmployeeFormSheet({this.existing});

  final Person? existing;

  @override
  ConsumerState<_EmployeeFormSheet> createState() => _EmployeeFormSheetState();
}

class _EmployeeFormSheetState extends ConsumerState<_EmployeeFormSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _email;
  late final TextEditingController _jobTitle;
  late final TextEditingController _workPhone;
  late final TextEditingController _officeLocation;

  // Create-only. Never seeded, never read back, never kept.
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _showPassword = false;

  String? _employmentType;
  String? _employmentStatus;
  String? _gender;
  int? _departmentId;
  Person? _manager;
  DateTime? _dateOfBirth;
  DateTime? _hireDate;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final person = widget.existing;
    _firstName = TextEditingController(text: person?.firstName ?? '');
    _lastName = TextEditingController(text: person?.lastName ?? '');
    _email = TextEditingController(text: person?.email ?? '');
    _jobTitle = TextEditingController(text: person?.jobTitle ?? '');
    _workPhone = TextEditingController(text: person?.workPhone ?? '');
    _officeLocation = TextEditingController(text: person?.officeLocation ?? '');
    _employmentType = person?.employmentType ?? employmentTypes.first;
    _employmentStatus = person?.employmentStatus;
    _departmentId = person?.departmentId;
    _hireDate = Fmt.parse(person?.hireDate);
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _jobTitle.dispose();
    _workPhone.dispose();
    _officeLocation.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _pickManager() async {
    final person = await EmployeePicker.show(context, title: 'Reports to');
    if (person != null) setState(() => _manager = person);
  }

  /// True when the chosen status stands the person down. Worth warning about
  /// before it happens: the backend also clears their `active` flag and
  /// deactivates their portal login, which is not what "change a status" looks
  /// like it does.
  bool get _willDeactivate =>
      _isEdit &&
      _employmentStatus != null &&
      terminalEmploymentStatuses.contains(_employmentStatus) &&
      _employmentStatus != widget.existing?.employmentStatus;

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_willDeactivate) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Stand ${widget.existing!.fullName} down?'),
          content: Text(
            'Setting the status to ${Fmt.label(_employmentStatus).toLowerCase()} '
            'also marks them inactive and disables their login. They stop '
            'counting towards headcount and drop out of payroll.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final controller = ref.read(directoryProvider.notifier);
    try {
      if (_isEdit) {
        await controller.updateItem(
          widget.existing!.id,
          UpdateEmployeeRequest(
            jobTitle: _jobTitle.text,
            employmentType: _employmentType,
            employmentStatus: _employmentStatus,
            workPhone: _workPhone.text,
            officeLocation: _officeLocation.text,
            departmentId: _departmentId,
            reportingManagerId: _manager?.id,
            hireDate: _hireDate == null ? null : Fmt.isoDate(_hireDate!),
          ),
        );
        if (!mounted) return;
        navigator.pop();
        messenger.showSnackBar(
          const SnackBar(content: Text('Employee updated.')),
        );
      } else {
        await controller.create(
          CreateEmployeeRequest(
            firstName: _firstName.text,
            lastName: _lastName.text,
            email: _email.text,
            password: _password.text,
            employmentType: _employmentType ?? employmentTypes.first,
            jobTitle: _jobTitle.text,
            workPhone: _workPhone.text,
            employmentStatus: _employmentStatus,
            departmentId: _departmentId,
            reportingManagerId: _manager?.id,
            gender: _gender,
            dateOfBirth:
                _dateOfBirth == null ? null : Fmt.isoDate(_dateOfBirth!),
            hireDate: _hireDate == null ? null : Fmt.isoDate(_hireDate!),
            officeLocation: _officeLocation.text,
          ),
        );
        if (!mounted) return;
        navigator.pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${_firstName.text.trim()} added. They can sign in with the '
              'password you set.',
            ),
          ),
        );
      }
    } on ApiException catch (e) {
      // A duplicate email lands here and names itself.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = _isEdit
            ? 'Could not save that employee.'
            : 'Could not add that employee.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final now = DateTime.now();
    final departments = ref.watch(departmentsProvider).value ?? const [];

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
                _isEdit ? 'Edit employee' : 'New employee',
                style: TextStyle(
                  color: bos.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (_isEdit) ...[
                const SizedBox(height: 4),
                Text(
                  widget.existing!.fullName,
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

              // ── Identity: create only ─────────────────────
              // Name and email live on the person's user account and this
              // endpoint cannot change them, so on an edit they are shown as
              // the subtitle above rather than as fields that would not save.
              if (!_isEdit) ...[
                TextFormField(
                  controller: _firstName,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'First name',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) return 'A first name is required.';
                    return trimmed.length < 2 ? 'At least two characters.' : null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _lastName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Last name',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) return 'A last name is required.';
                    return trimmed.length < 2 ? 'At least two characters.' : null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    helperText: 'They sign in with this.',
                    prefixIcon: Icon(Icons.alternate_email_rounded),
                  ),
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) return 'An email is required.';
                    return trimmed.contains('@') ? null : 'That is not an email.';
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _password,
                  obscureText: !_showPassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Temporary password',
                    helperText: 'Share it with them; they can change it after.',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20,
                      ),
                      tooltip: _showPassword ? 'Hide' : 'Show',
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                  validator: (value) {
                    final entered = value ?? '';
                    if (entered.isEmpty) return 'Set a password for them.';
                    // Matches the backend's @Size(min = 8).
                    return entered.length < 8
                        ? 'At least eight characters.'
                        : null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPassword,
                  obscureText: !_showPassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                  validator: (value) => (value ?? '') == _password.text
                      ? null
                      : 'The two do not match.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _gender,
                  decoration: const InputDecoration(
                    labelText: 'Gender (optional)',
                    prefixIcon: Icon(Icons.wc_rounded),
                  ),
                  items: [
                    for (final gender in genders)
                      DropdownMenuItem(
                        value: gender,
                        child: Text(Fmt.label(gender)),
                      ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _gender = value),
                ),
                const SizedBox(height: 16),
                DateField(
                  label: 'Date of birth (optional)',
                  icon: Icons.cake_outlined,
                  value: _dateOfBirth,
                  enabled: !_submitting,
                  firstDate: DateTime(now.year - 80),
                  lastDate: DateTime(now.year - 14),
                  onChanged: (date) => setState(() => _dateOfBirth = date),
                ),
                const SizedBox(height: 22),
                const SectionHeader('Role', icon: Icons.work_outline_rounded),
                const SizedBox(height: 12),
              ],

              // ── Role: both ────────────────────────────────
              TextFormField(
                controller: _jobTitle,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Job title (optional)',
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
                    : (value) => setState(() => _employmentType = value),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _employmentStatus,
                decoration: const InputDecoration(
                  labelText: 'Status (optional)',
                  prefixIcon: Icon(Icons.toggle_on_outlined),
                ),
                items: [
                  for (final status in employmentStatuses)
                    DropdownMenuItem(
                      value: status,
                      child: Text(Fmt.label(status)),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _employmentStatus = value),
              ),
              if (_willDeactivate) ...[
                const SizedBox(height: 12),
                const MessageBanner.warning(
                  'This also marks them inactive and disables their login.',
                ),
              ],
              const SizedBox(height: 16),
              if (departments.isNotEmpty) ...[
                DropdownButtonFormField<int?>(
                  initialValue: departments.any((d) => d.id == _departmentId)
                      ? _departmentId
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Department (optional)',
                    prefixIcon: Icon(Icons.apartment_rounded),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('None')),
                    for (final department in departments)
                      DropdownMenuItem(
                        value: department.id,
                        child: Text(department.name),
                      ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _departmentId = value),
                ),
                const SizedBox(height: 16),
              ],
              InkWell(
                onTap: _submitting ? null : _pickManager,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Reports to (optional)',
                    prefixIcon: Icon(Icons.supervisor_account_outlined),
                  ),
                  child: Text(
                    _manager?.fullName ??
                        widget.existing?.reportingManagerName ??
                        'Choose a colleague',
                    style: TextStyle(
                      color: _manager == null &&
                              widget.existing?.reportingManagerName == null
                          ? bos.muted
                          : bos.text,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _workPhone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Work phone (optional)',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _officeLocation,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Office (optional)',
                  prefixIcon: Icon(Icons.place_outlined),
                ),
              ),
              const SizedBox(height: 16),
              DateField(
                label: 'Start date (optional)',
                value: _hireDate,
                enabled: !_submitting,
                firstDate: DateTime(now.year - 40),
                lastDate: DateTime(now.year + 1),
                onChanged: (date) => setState(() => _hireDate = date),
              ),
              if (_isEdit) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 15,
                      color: bos.muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pay, bank details and emergency contacts are edited on '
                        'the web — this app does not show them, so it does not '
                        'offer to change them.',
                        style: TextStyle(
                          color: bos.muted,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              LoadingButton(
                label: _isEdit ? 'Save changes' : 'Add employee',
                loading: _submitting,
                icon: _isEdit ? Icons.check_rounded : Icons.person_add_alt_rounded,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
