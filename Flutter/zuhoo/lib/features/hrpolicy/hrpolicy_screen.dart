import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/config_list.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import 'hrpolicy_models.dart';
import 'hrpolicy_repository.dart';
import 'hrpolicy_sheets.dart';

/// The standing HR rules: days off, leave, hours, and the letters that record
/// what was agreed.
class HrPolicyScreen extends ConsumerWidget {
  const HrPolicyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final permissions = ref.watch(permissionControllerProvider);

    if (!permissions.loaded && permissions.codes.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('HR rules')),
        body: const Loader(),
      );
    }

    final tabs = <({String label, Widget view, VoidCallback? create})>[
      if (permissions.has(HrPolicyPermissions.holidayView))
        (
          label: 'Holidays',
          view: const _HolidaysTab(),
          create: permissions.has(HrPolicyPermissions.holidayCreate)
              ? () => showHolidaySheet(context)
              : null,
        ),
      if (permissions.has(HrPolicyPermissions.policyView))
        (
          label: 'Leave',
          view: const _PoliciesTab(),
          create: permissions.has(HrPolicyPermissions.policyCreate)
              ? () => showLeavePolicySheet(context)
              : null,
        ),
      if (permissions.has(HrPolicyPermissions.shiftView))
        (
          label: 'Shifts',
          view: const _ShiftsTab(),
          create: permissions.has(HrPolicyPermissions.shiftCreate)
              ? () => showShiftSheet(context)
              : null,
        ),
      if (permissions.has(HrPolicyPermissions.letterView))
        (
          label: 'Letters',
          view: const _LettersTab(),
          create: permissions.has(HrPolicyPermissions.letterCreate)
              ? () => showLetterSheet(context)
              : null,
        ),
    ];

    if (tabs.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('HR rules')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Not available to you',
          message:
              'Holidays, leave policies, shifts and letters need HR '
              'permissions. Your own leave is on the Leave screen.',
        ),
      );
    }

    return DefaultTabController(
      length: tabs.length,
      child: Builder(
        builder: (context) {
          final tabController = DefaultTabController.of(context);
          return AnimatedBuilder(
            animation: tabController,
            builder: (context, _) {
              final create = tabs[tabController.index].create;
              return Scaffold(
                backgroundColor: bos.bgPage,
                appBar: AppBar(
                  title: const Text('HR rules'),
                  bottom: TabBar(
                    isScrollable: tabs.length > 3,
                    tabAlignment: tabs.length > 3 ? TabAlignment.start : null,
                    tabs: [for (final tab in tabs) Tab(text: tab.label)],
                  ),
                ),
                floatingActionButton: create == null
                    ? null
                    : FloatingActionButton.extended(
                        onPressed: create,
                        backgroundColor: bos.brand,
                        foregroundColor: Colors.white,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('New'),
                      ),
                body: TabBarView(children: [for (final tab in tabs) tab.view]),
              );
            },
          );
        },
      ),
    );
  }
}

// ── Holidays ──────────────────────────────────────────────────

class _HolidaysTab extends ConsumerStatefulWidget {
  const _HolidaysTab();

  @override
  ConsumerState<_HolidaysTab> createState() => _HolidaysTabState();
}

class _HolidaysTabState extends ConsumerState<_HolidaysTab> {
  int? _busyId;

  Future<void> _delete(Holiday holiday) async {
    final confirmed = await confirmAction(
      context,
      title: 'Remove ${holiday.name}?',
      message:
          'The day stops being a holiday. Leave already approved around it is '
          'not recalculated.',
      action: 'Remove',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyId = holiday.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(hrPolicyRepositoryProvider).deleteHoliday(holiday.id);
      ref.read(holidaysProvider.notifier).remove(holiday.id);
      messenger.showSnackBar(SnackBar(content: Text('${holiday.name} removed.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not remove that holiday.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(permissionControllerProvider);
    final canEdit = permissions.has(HrPolicyPermissions.holidayUpdate);
    final canDelete = permissions.has(HrPolicyPermissions.holidayDelete);
    final year = ref.watch(holidayYearProvider);
    final now = DateTime.now().year;

    return ConfigList<Holiday>(
      async: ref.watch(holidaysProvider),
      onRefresh: ref.read(holidaysProvider.notifier).refresh,
      emptyIcon: Icons.celebration_outlined,
      emptyTitle: 'No holidays in $year',
      emptyMessage:
          'Holidays are what leave and attendance are worked out around. Add '
          'the ones the company observes.',
      errorMessage: 'Could not load the holidays.',
      header: FilterBar(
        selected: '$year',
        onSelected: (value) {
          final parsed = int.tryParse(value ?? '');
          if (parsed != null) {
            ref.read(holidayYearProvider.notifier).set(parsed);
          }
        },
        // Last year, this year, next year — the only three anybody sets up.
        options: [
          for (final y in [now - 1, now, now + 1]) (value: '$y', label: '$y'),
        ],
      ),
      itemBuilder: (context, holiday) => ConfigRow(
        title: holiday.name,
        // Optional holidays read as available rather than fixed, which is
        // what they are.
        active: !holiday.isOptional,
        inactiveLabel: 'Optional',
        subtitle: [
          Fmt.date(holiday.holidayDate),
          Fmt.label(holiday.holidayType),
          if (holiday.description != null) holiday.description!,
        ].join(' · '),
        trailingLabel: holiday.holidayDate == null
            ? null
            : Fmt.dayDate(holiday.holidayDate).split(',').first,
        busy: _busyId == holiday.id,
        onEdit: canEdit
            ? () => showHolidaySheet(context, existing: holiday)
            : null,
        actions: [
          if (canDelete)
            RowAction(
              label: 'Remove',
              destructive: true,
              onSelected: () => _delete(holiday),
            ),
        ],
      ),
    );
  }
}

// ── Leave policies ────────────────────────────────────────────

class _PoliciesTab extends ConsumerStatefulWidget {
  const _PoliciesTab();

  @override
  ConsumerState<_PoliciesTab> createState() => _PoliciesTabState();
}

class _PoliciesTabState extends ConsumerState<_PoliciesTab> {
  int? _busyId;

  Future<void> _delete(LeavePolicy policy) async {
    final confirmed = await confirmAction(
      context,
      title: 'Remove this policy?',
      message:
          '${Fmt.label(policy.leaveType)} would have no entitlement rule, so '
          'balances for it stop being granted.',
      action: 'Remove',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyId = policy.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(hrPolicyRepositoryProvider).deletePolicy(policy.id);
      ref.read(leavePoliciesProvider.notifier).remove(policy.id);
      messenger.showSnackBar(const SnackBar(content: Text('Removed.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not remove that policy.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(permissionControllerProvider);
    final canEdit = permissions.has(HrPolicyPermissions.policyUpdate);
    final canDelete = permissions.has(HrPolicyPermissions.policyDelete);

    return ConfigList<LeavePolicy>(
      async: ref.watch(leavePoliciesProvider),
      onRefresh: ref.read(leavePoliciesProvider.notifier).refresh,
      emptyIcon: Icons.beach_access_outlined,
      emptyTitle: 'No leave policies yet',
      emptyMessage:
          'A policy says what one kind of leave is worth, and to whom. '
          'Without one, nothing is granted.',
      errorMessage: 'Could not load the leave policies.',
      header: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => showPolicyDocumentSheet(context),
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('Draft the document'),
          ),
        ),
      ),
      itemBuilder: (context, policy) => ConfigRow(
        title: Fmt.label(policy.leaveType),
        active: policy.active,
        subtitle: policy.terms,
        trailingLabel: policy.employmentType == null
            ? 'everybody'
            : Fmt.label(policy.employmentType).toLowerCase(),
        busy: _busyId == policy.id,
        onEdit: canEdit
            ? () => showLeavePolicySheet(context, existing: policy)
            : null,
        actions: [
          if (canDelete)
            RowAction(
              label: 'Remove',
              destructive: true,
              onSelected: () => _delete(policy),
            ),
        ],
      ),
    );
  }
}

// ── Shifts ────────────────────────────────────────────────────

class _ShiftsTab extends ConsumerStatefulWidget {
  const _ShiftsTab();

  @override
  ConsumerState<_ShiftsTab> createState() => _ShiftsTabState();
}

class _ShiftsTabState extends ConsumerState<_ShiftsTab> {
  int? _busyId;

  Future<void> _toggle(Shift shift) async {
    setState(() => _busyId = shift.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated =
          await ref.read(hrPolicyRepositoryProvider).toggleShift(shift.id);
      ref.read(hrShiftsProvider.notifier).apply(updated);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not change that shift.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _delete(Shift shift) async {
    final confirmed = await confirmAction(
      context,
      title: 'Remove ${shift.name}?',
      message:
          'Anybody assigned to it keeps the assignment until it is changed. '
          'Retiring it instead stops it being assigned to anyone new.',
      action: 'Remove',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyId = shift.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(hrPolicyRepositoryProvider).deleteShift(shift.id);
      ref.read(hrShiftsProvider.notifier).remove(shift.id);
      messenger.showSnackBar(SnackBar(content: Text('${shift.name} removed.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not remove that shift.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(permissionControllerProvider);
    final canEdit = permissions.has(HrPolicyPermissions.shiftUpdate);
    final canDelete = permissions.has(HrPolicyPermissions.shiftDelete);

    return ConfigList<Shift>(
      async: ref.watch(hrShiftsProvider),
      onRefresh: ref.read(hrShiftsProvider.notifier).refresh,
      emptyIcon: Icons.schedule_rounded,
      emptyTitle: 'No shifts yet',
      emptyMessage:
          'A shift is the hours somebody is expected to work. Attendance is '
          'judged late or on time against it.',
      errorMessage: 'Could not load the shifts.',
      itemBuilder: (context, shift) => ConfigRow(
        title: shift.name,
        active: shift.active,
        subtitle: [
          shift.window,
          Fmt.hours(shift.hours),
          if (shift.flexible) 'flexible',
          if (shift.nightShift) 'night',
          if (shift.gracePeriodMinutes > 0)
            '${shift.gracePeriodMinutes} min grace',
        ].join(' · '),
        trailingLabel: shift.weeklyOffDays,
        busy: _busyId == shift.id,
        onEdit: canEdit ? () => showShiftSheet(context, existing: shift) : null,
        onToggle: canEdit ? () => _toggle(shift) : null,
        actions: [
          if (canDelete)
            RowAction(
              label: 'Remove',
              destructive: true,
              onSelected: () => _delete(shift),
            ),
        ],
      ),
    );
  }
}

// ── Letters ───────────────────────────────────────────────────

class _LettersTab extends ConsumerStatefulWidget {
  const _LettersTab();

  @override
  ConsumerState<_LettersTab> createState() => _LettersTabState();
}

class _LettersTabState extends ConsumerState<_LettersTab> {
  int? _busyId;

  Future<void> _issue(HrLetter letter) async {
    final confirmed = await confirmAction(
      context,
      title: 'Issue this letter?',
      message:
          'It is marked as given to ${letter.about}. There is no unissuing it '
          'afterwards.',
      action: 'Issue it',
      destructive: false,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyId = letter.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated =
          await ref.read(hrPolicyRepositoryProvider).issueLetter(letter.id);
      ref.read(lettersProvider.notifier).apply(updated);
      messenger.showSnackBar(const SnackBar(content: Text('Issued.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not issue that letter.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _delete(HrLetter letter) async {
    final confirmed = await confirmAction(
      context,
      title: 'Delete this letter?',
      message: letter.issued
          ? 'It has already been issued, so deleting it loses the record that '
              'it was.'
          : 'It is still a draft and has not been given to anyone.',
      action: 'Delete',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyId = letter.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(hrPolicyRepositoryProvider).deleteLetter(letter.id);
      ref.read(lettersProvider.notifier).remove(letter.id);
      messenger.showSnackBar(const SnackBar(content: Text('Deleted.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not delete that letter.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(permissionControllerProvider);
    final canIssue = permissions.has(HrPolicyPermissions.letterUpdate);
    final canDelete = permissions.has(HrPolicyPermissions.letterDelete);

    return ConfigList<HrLetter>(
      async: ref.watch(lettersProvider),
      onRefresh: ref.read(lettersProvider.notifier).refresh,
      emptyIcon: Icons.description_outlined,
      emptyTitle: 'No letters yet',
      emptyMessage:
          'Offers, confirmations, certificates and warnings — anything written '
          'about somebody and kept on their file.',
      errorMessage: 'Could not load the letters.',
      itemBuilder: (context, letter) => ConfigRow(
        title: letter.about,
        // A draft is drawn muted; an issued letter is the finished thing.
        active: letter.issued,
        inactiveLabel: 'Draft',
        subtitle: [
          Fmt.label(letter.letterType),
          if (letter.referenceNumber != null) letter.referenceNumber!,
          if (letter.issueDate != null) Fmt.date(letter.issueDate),
          if (letter.signedBy != null) 'signed by ${letter.signedBy}',
        ].join(' · '),
        busy: _busyId == letter.id,
        onEdit: () => LetterScreen.open(context, letter: letter),
        actions: [
          if (canIssue && !letter.issued)
            RowAction(label: 'Issue it', onSelected: () => _issue(letter)),
          if (canDelete)
            RowAction(
              label: 'Delete',
              destructive: true,
              onSelected: () => _delete(letter),
            ),
        ],
      ),
    );
  }
}

/// One letter, read in full.
///
/// There is no editing: the backend has no update endpoint for a letter, which
/// is right for a document — a wrong one is deleted and written again.
class LetterScreen extends StatelessWidget {
  const LetterScreen({super.key, required this.letter});

  final HrLetter letter;

  static void open(BuildContext context, {required HrLetter letter}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => LetterScreen(letter: letter)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: Text(Fmt.label(letter.letterType))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        letter.about,
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    StatusChip(
                      letter.issued ? 'APPROVED' : 'PENDING',
                      label: letter.issued ? 'Issued' : 'Draft',
                      dense: true,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (letter.referenceNumber != null)
                      letter.referenceNumber!,
                    if (letter.issueDate != null) Fmt.date(letter.issueDate),
                    if (letter.createdByName != null)
                      'written by ${letter.createdByName}',
                  ].join(' · '),
                  style: TextStyle(color: bos.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppCard(
            child: SelectableText(
              letter.content ?? 'This letter has no content.',
              style: TextStyle(color: bos.text, fontSize: 14, height: 1.6),
            ),
          ),
          if (letter.signedBy != null) ...[
            const SizedBox(height: 14),
            Text(
              'Signed by ${letter.signedBy}',
              style: TextStyle(color: bos.muted, fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }
}
