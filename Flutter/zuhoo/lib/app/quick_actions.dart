import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/permission_controller.dart';
import '../core/theme/bos_tokens.dart';
import '../features/crm/client_form_sheet.dart' show showNewClientSheet;
import '../features/crm/crm_models.dart' show CrmPermissions;
import '../features/crm/crm_screen.dart' show showNewLeadSheet;
import '../features/finance/submit_expense_sheet.dart' show showSubmitExpenseSheet;
import '../features/leave/apply_leave_sheet.dart' show showApplyLeaveSheet;
import '../features/requests/raise_request_sheet.dart' show showRaiseRequestSheet;
import '../features/support/new_ticket_sheet.dart' show showNewTicketSheet;
import 'router.dart';

/// One entry in the global quick-action sheet — a shortcut straight to a
/// create-flow that already exists somewhere in the app, so this file adds
/// no new screens or API calls, only a faster way to reach the ones a user
/// reaches for most often. [gate] mirrors the permission the owning screen
/// itself checks before offering the same action, so this sheet never shows
/// something the backend would then refuse.
class QuickAction {
  const QuickAction({
    required this.label,
    required this.icon,
    required this.run,
    this.gate,
  });

  final String label;
  final IconData icon;
  final void Function(BuildContext context, WidgetRef ref) run;

  /// Null means always offered — the same self-service actions (raising a
  /// request, applying for leave, submitting an expense, logging a
  /// timesheet, opening a ticket) that their own screens offer to any
  /// signed-in employee with no extra permission check.
  final bool Function(PermissionState perms)? gate;

  bool allowed(PermissionState perms) => gate == null || gate!(perms);
}

/// The full quick-action list, filtered by [perms] — every caller reads from
/// here rather than keeping its own copy, the same rule [buildNavGroups]
/// follows for the drawer.
List<QuickAction> quickActions(PermissionState perms) {
  final all = <QuickAction>[
    QuickAction(
      label: 'Raise a request',
      icon: Icons.assignment_outlined,
      run: (context, ref) => showRaiseRequestSheet(context),
    ),
    QuickAction(
      label: 'Apply for leave',
      icon: Icons.event_note_outlined,
      run: (context, ref) => showApplyLeaveSheet(context, ref),
    ),
    QuickAction(
      label: 'Submit an expense',
      icon: Icons.payments_outlined,
      run: (context, ref) => showSubmitExpenseSheet(context),
    ),
    QuickAction(
      label: 'Open a support ticket',
      icon: Icons.support_agent_outlined,
      run: (context, ref) => showNewTicketSheet(context),
    ),
    QuickAction(
      label: 'New lead',
      icon: Icons.person_add_alt_rounded,
      gate: (p) => p.has(CrmPermissions.leadCreate),
      run: (context, ref) => showNewLeadSheet(context),
    ),
    QuickAction(
      label: 'New client',
      icon: Icons.business_rounded,
      gate: (p) => p.has(CrmPermissions.clientCreate),
      run: (context, ref) => showNewClientSheet(context),
    ),
    QuickAction(
      label: 'Attendance',
      icon: Icons.access_time_rounded,
      run: (context, ref) => context.go(Routes.attendance),
    ),
  ];

  return all.where((a) => a.allowed(perms)).toList();
}

/// The bottom sheet the floating action button opens: a role-filtered grid of
/// the actions above, closing itself before handing off to whichever create
/// flow was tapped so the target sheet opens over the real screen rather than
/// stacking on top of this one.
Future<void> showQuickActionSheet(BuildContext context, WidgetRef ref) {
  final perms = ref.read(permissionControllerProvider);
  final actions = quickActions(perms);

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      final bos = Theme.of(sheetContext).bos;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick actions',
              style: TextStyle(
                color: bos.text,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.92,
              children: [
                for (final action in actions)
                  _QuickActionTile(
                    action: action,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      action.run(context, ref);
                    },
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({required this.action, required this.onTap});

  final QuickAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return Material(
      color: bos.bgSubtle,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: bos.brandSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(action.icon, size: 19, color: bos.brandInk),
              ),
              const SizedBox(height: 8),
              Text(
                action.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: bos.textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
