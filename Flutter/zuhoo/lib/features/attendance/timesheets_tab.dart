import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/primitives.dart';
import 'attendance_controller.dart';
import 'attendance_models.dart';
import 'submit_timesheet_sheet.dart';

class TimesheetsTab extends ConsumerWidget {
  const TimesheetsTab({super.key});

  Future<void> _submitForReview(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final count =
          await ref.read(timesheetsProvider.notifier).submitForReview();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            count == 0
                ? 'Nothing to submit — every entry is already in review or approved.'
                : count == 1
                    ? '1 entry submitted for review.'
                    : '$count entries submitted for review.',
          ),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not submit your entries.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(timesheetsProvider);
    final hasDraft =
        async.value?.items.any((t) => t.status == TimesheetStatus.notSubmitted) ??
            false;

    return Scaffold(
      backgroundColor: bos.bgPage,
      body: PagedListView<Timesheet>(
        async: async,
        onRefresh: () => ref.read(timesheetsProvider.notifier).refresh(),
        onLoadMore: () =>
            guardListAction(context, ref.read(timesheetsProvider.notifier).loadMore),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        emptyIcon: Icons.schedule_outlined,
        emptyTitle: 'No entries yet',
        emptyMessage: 'Log a day\'s hours with the button below.',
        errorMessage: 'Could not load your timesheets.',
        itemBuilder: (context, timesheet) => _TimesheetCard(timesheet: timesheet),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (hasDraft) ...[
            FloatingActionButton.extended(
              heroTag: 'submitTimesheets',
              onPressed: () => _submitForReview(context, ref),
              backgroundColor: bos.bgCard,
              foregroundColor: bos.text,
              icon: const Icon(Icons.send_outlined),
              label: const Text('Submit for review'),
            ),
            const SizedBox(height: 12),
          ],
          FloatingActionButton.extended(
            heroTag: 'logTimesheet',
            onPressed: () => showLogTimesheetSheet(context),
            backgroundColor: bos.brand,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Log time'),
          ),
        ],
      ),
    );
  }
}

class _TimesheetCard extends ConsumerStatefulWidget {
  const _TimesheetCard({required this.timesheet});

  final Timesheet timesheet;

  @override
  ConsumerState<_TimesheetCard> createState() => _TimesheetCardState();
}

class _TimesheetCardState extends ConsumerState<_TimesheetCard> {
  bool _deleting = false;

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${Fmt.date(widget.timesheet.workDate)}?'),
        content: const Text('This entry is removed for good.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(timesheetsProvider.notifier).delete(widget.timesheet.id);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not delete that entry.')),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final timesheet = widget.timesheet;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Fmt.date(timesheet.workDate),
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (timesheet.projectName?.trim().isNotEmpty == true)
                        Text(
                          timesheet.projectName!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: bos.textSecondary, fontSize: 12.5),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusChip(timesheet.status, dense: true),
              ],
            ),
            if (timesheet.description?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(
                timesheet.description!.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: bos.textSecondary, fontSize: 12.5, height: 1.35),
              ),
            ],
            const SizedBox(height: 9),
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 13, color: bos.muted),
                const SizedBox(width: 4),
                Text(
                  '${Fmt.hours(timesheet.hoursWorked)} worked',
                  style: TextStyle(color: bos.muted, fontSize: 11.5),
                ),
                if (timesheet.billableHours > 0) ...[
                  const SizedBox(width: 10),
                  Icon(Icons.receipt_long_rounded, size: 13, color: bos.muted),
                  const SizedBox(width: 4),
                  Text(
                    '${Fmt.hours(timesheet.billableHours)} billable',
                    style: TextStyle(color: bos.muted, fontSize: 11.5),
                  ),
                ],
              ],
            ),
            if (timesheet.approvedByName != null) ...[
              const SizedBox(height: 6),
              Text(
                'Approved by ${timesheet.approvedByName}',
                style: TextStyle(color: bos.muted, fontSize: 11.5),
              ),
            ],
            if (timesheet.isEditable) ...[
              const SizedBox(height: 10),
              if (_deleting)
                const Loader(padding: 4)
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () =>
                          showEditTimesheetSheet(context, timesheet),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit'),
                    ),
                    const SizedBox(width: 4),
                    TextButton.icon(
                      onPressed: _delete,
                      icon: Icon(Icons.delete_outline_rounded,
                          size: 16, color: bos.danger),
                      label: Text('Delete', style: TextStyle(color: bos.danger)),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}
