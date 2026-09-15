import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/contact_actions.dart';
import '../../shared/widgets/primitives.dart';
import 'directory_models.dart';
import 'directory_repository.dart';
import '../itam/itam_repository.dart';
import '../itam/offboarding_detail_screen.dart';
import 'education_section.dart';
import 'employee_form_sheet.dart';

/// One colleague.
///
/// Opened with the row that was tapped, so the name and photo are on screen
/// immediately and the fuller record fills in behind them. A directory lookup
/// is usually two seconds long — waiting on a spinner for the part the list
/// already knew would be most of that.
class PersonDetailScreen extends ConsumerWidget {
  const PersonDetailScreen({super.key, required this.person});

  final Person person;

  static void open(BuildContext context, {required Person person}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PersonDetailScreen(person: person)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final full = ref.watch(personProvider(person.id));

    // The row we were opened with, upgraded to the full record once it lands.
    final shown = full.value ?? person;

    final canEdit = ref
        .watch(permissionControllerProvider)
        .has(DirectoryPermissions.employeeUpdate);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          // Only once the full record has landed: the row this screen opened
          // with is a summary, and seeding an edit form from it would offer
          // fields whose current values are not actually known yet.
          if (canEdit && full.hasValue)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit employee',
              onPressed: () => showEditEmployeeSheet(context, shown),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _Header(person: shown),
          const SizedBox(height: 18),
          _ContactActions(person: shown),
          if (full.hasError) ...[
            const SizedBox(height: 16),
            MessageBanner.info(
              full.error is ApiException
                  ? (full.error! as ApiException).message
                  : 'Could not load the rest of this profile.',
            ),
          ],
          const SizedBox(height: 20),
          _Details(person: shown, loading: full.isLoading),
          _Offboarding(employeeId: shown.id),
          const SizedBox(height: 20),
          _HeldAssets(employeeId: shown.id),
          const SizedBox(height: 20),
          EducationSection(employeeId: shown.id),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Column(
      children: [
        Avatar(
          initials: person.initials,
          imageUrl: person.imageUrl,
          size: 88,
        ),
        const SizedBox(height: 12),
        Text(
          person.fullName,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: bos.text,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (person.roleLabel != null) ...[
          const SizedBox(height: 3),
          Text(
            person.roleLabel!,
            textAlign: TextAlign.center,
            style: TextStyle(color: bos.textSecondary, fontSize: 14),
          ),
        ],
        if (person.departmentName != null) ...[
          const SizedBox(height: 8),
          StatusChip(
            person.isFormer ? person.employmentStatus! : 'ACTIVE',
            label: person.departmentName,
            dense: true,
          ),
        ],
        if (person.isFormer) ...[
          const SizedBox(height: 12),
          MessageBanner.warning(
            'This person has left the company. Their contact details are kept '
            'for the record and may no longer reach them.',
          ),
        ],
      ],
    );
  }
}

/// Call and email, the two things a directory exists for.
class _ContactActions extends StatelessWidget {
  const _ContactActions({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    return ContactActions(
      phone: person.bestPhone,
      email: person.bestEmail,
      emptyMessage: 'No contact details are recorded for this person.',
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.person, required this.loading});

  final Person person;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    final rows = <({String label, String? value, IconData icon})>[
      (
        label: 'Work email',
        value: person.officialEmail,
        icon: Icons.alternate_email_rounded
      ),
      (
        label: 'Work phone',
        value: person.workPhone,
        icon: Icons.phone_outlined
      ),
      (
        label: 'Department',
        value: person.departmentName,
        icon: Icons.account_tree_outlined
      ),
      (
        label: 'Designation',
        value: person.designationName,
        icon: Icons.workspace_premium_outlined
      ),
      (
        label: 'Reporting to',
        value: person.reportingManagerName,
        icon: Icons.supervisor_account_outlined
      ),
      (
        label: 'Office',
        value: person.officeLocation,
        icon: Icons.location_on_outlined
      ),
      (label: 'Shift', value: person.shiftName, icon: Icons.schedule_outlined),
      (
        label: 'Employee number',
        value: person.employeeNumber,
        icon: Icons.badge_outlined
      ),
      (
        label: 'Employment',
        value: person.employmentType == null
            ? null
            : Fmt.label(person.employmentType),
        icon: Icons.work_outline_rounded
      ),
      (
        label: 'Joined',
        value: person.hireDate == null ? null : Fmt.date(person.hireDate),
        icon: Icons.event_outlined
      ),
    ].where((r) => r.value != null && r.value!.trim().isNotEmpty).toList();

    if (rows.isEmpty) {
      return loading ? const Loader() : const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Details', icon: Icons.badge_outlined),
        AppCard(
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) ...[
                  const SizedBox(height: 10),
                  Divider(height: 1, color: bos.borderLight),
                  const SizedBox(height: 10),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(rows[i].icon, size: 17, color: bos.muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        rows[i].label,
                        style: TextStyle(color: bos.muted, fontSize: 13),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        rows[i].value!,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (loading) ...[
          const SizedBox(height: 10),
          const Loader(padding: 4),
        ],
      ],
    );
  }
}

/// A quiet note when somebody is on their way out.
///
/// The lookup 404s for everybody who is not leaving, which is nearly
/// everybody — so a failure here shows nothing at all rather than an error.
/// The absence of a checklist is the normal case, not a fault.
class _Offboarding extends ConsumerWidget {
  const _Offboarding({required this.employeeId});

  final int employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final checklist =
        ref.watch(offboardingForEmployeeProvider(employeeId)).value;

    if (checklist == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: AppCard(
        onTap: () =>
            OffboardingDetailScreen.open(context, checklist: checklist),
        child: Row(
          children: [
            Icon(
              Icons.logout_rounded,
              size: 18,
              color: checklist.completed ? bos.muted : bos.warning,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    checklist.completed
                        ? 'Offboarding finished'
                        : 'Offboarding in progress',
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${checklist.completionPercentage}% done',
                    style: TextStyle(color: bos.muted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: bos.muted),
          ],
        ),
      ),
    );
  }
}

/// What this person is holding.
///
/// Only what is out on them now. Where a piece of kit has been over time is
/// its own screen under IT assets — this answers the question somebody asks
/// standing in front of the person, which is what needs handing back.
class _HeldAssets extends ConsumerWidget {
  const _HeldAssets({required this.employeeId});

  final int employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final assets = ref.watch(assetsForEmployeeProvider(employeeId));

    // Reading the asset register needs its own permission, and most people
    // looking at a colleague's profile do not have it. A refusal shows
    // nothing rather than an error.
    final held = assets.value;
    if (held == null || held.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Holding', icon: Icons.devices_other_outlined),
        AppCard(
          child: Column(
            children: [
              for (final asset in held)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.laptop_mac_outlined,
                        size: 15,
                        color: bos.muted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          asset.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: bos.text, fontSize: 13),
                        ),
                      ),
                      if (asset.assetTag != null)
                        Text(
                          asset.assetTag!,
                          style: TextStyle(color: bos.muted, fontSize: 11.5),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
