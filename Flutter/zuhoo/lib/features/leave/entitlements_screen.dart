import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/config_list.dart';
import '../../shared/widgets/form_sheet.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import '../hrpolicy/hrpolicy_models.dart';
import '../hrpolicy/hrpolicy_repository.dart';
import 'grant_leave_balance_sheet.dart';
import 'leave_models.dart';
import 'leave_repository.dart';

/// Which year the entitlements screen is showing.
class EntitlementYearController extends Notifier<int> {
  @override
  int build() => DateTime.now().year;

  void set(int year) => state = year;
}

final entitlementYearProvider =
    NotifierProvider<EntitlementYearController, int>(
  EntitlementYearController.new,
);

/// Everybody's entitlements for the year in view.
final allBalancesProvider =
    FutureProvider.autoDispose<List<LeaveBalance>>((ref) async {
  final year = ref.watch(entitlementYearProvider);
  final page =
      await ref.read(leaveRepositoryProvider).allBalances(year: year);
  return page.content;
});

/// What everybody is entitled to, and what the rules behind it are.
///
/// Two halves of one question. A balance is how many days one person has this
/// year; a policy is the rule that decides how many days people get. HR sets
/// the policy and then grants the balances, so they belong on one screen.
class EntitlementsScreen extends StatelessWidget {
  const EntitlementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(
          title: const Text('Leave entitlements'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Who has what'), Tab(text: 'The rules')],
          ),
        ),
        body: const TabBarView(children: [_BalancesTab(), _PoliciesTab()]),
      ),
    );
  }
}

class _BalancesTab extends ConsumerWidget {
  const _BalancesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = ref.watch(entitlementYearProvider);
    final canManage = ref
        .watch(permissionControllerProvider)
        .hasAny(const [
      LeavePermissions.balanceCreate,
      LeavePermissions.balanceUpdate,
    ]);

    // Last year, this year and next: granting next year's entitlement early
    // is ordinary, and last year's is what gets queried when somebody
    // disputes a figure.
    final now = DateTime.now().year;

    return Stack(
      children: [
        ConfigList<LeaveBalance>(
          async: ref.watch(allBalancesProvider),
          onRefresh: () async => ref.invalidate(allBalancesProvider),
          emptyIcon: Icons.event_available_outlined,
          emptyTitle: 'Nothing granted for $year',
          emptyMessage:
              'Until somebody has a balance for the year, every request they '
              'make is measured against nothing.',
          errorMessage: 'Could not load the entitlements.',
          header: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: FilterBar(
              selected: year.toString(),
              options: [
                for (final value in [now - 1, now, now + 1])
                  (value: value.toString(), label: value.toString()),
              ],
              onSelected: (value) => ref
                  .read(entitlementYearProvider.notifier)
                  .set(int.tryParse(value ?? '') ?? now),
            ),
          ),
          itemBuilder: (context, balance) =>
              _BalanceRow(balance: balance, canManage: canManage),
        ),
        if (canManage)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              onPressed: () async {
                await showGrantLeaveBalanceSheet(context);
                ref.invalidate(allBalancesProvider);
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Grant days'),
            ),
          ),
      ],
    );
  }
}

class _BalanceRow extends ConsumerStatefulWidget {
  const _BalanceRow({required this.balance, required this.canManage});

  final LeaveBalance balance;
  final bool canManage;

  @override
  ConsumerState<_BalanceRow> createState() => _BalanceRowState();
}

class _BalanceRowState extends ConsumerState<_BalanceRow> {
  bool _busy = false;

  Future<void> _delete() async {
    final confirmed = await confirmAction(
      context,
      title: 'Remove this entitlement?',
      message: 'Requests already approved against it stay approved. Only the '
          'allowance goes.',
      action: 'Remove',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(leaveRepositoryProvider).deleteBalance(widget.balance.id);
      ref.invalidate(allBalancesProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Removed.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not remove that entitlement.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = widget.balance;

    return ConfigRow(
      title: balance.employeeName ?? 'Employee #${balance.employeeId ?? "?"}',
      subtitle: '${Fmt.label(balance.leaveType)} · '
          '${Fmt.plain(balance.remainingDays)} of '
          '${Fmt.plain(balance.entitledDays)} days left',
      // Nothing is switched off here; a balance either exists or it does not.
      active: balance.remainingDays > 0,
      inactiveLabel: 'Used up',
      busy: _busy,
      onEdit: widget.canManage
          ? () => showEditEntitlementSheet(context, balance: balance)
          : null,
      actions: [
        if (widget.canManage)
          RowAction(label: 'Remove', destructive: true, onSelected: _delete),
      ],
    );
  }
}

/// Changing an entitlement.
///
/// Sets how many days somebody gets, not how many they have left. Used and
/// pending days come from the requests themselves and no endpoint edits them —
/// so a figure that looks wrong is fixed by correcting the requests, not here.
Future<void> showEditEntitlementSheet(
  BuildContext context, {
  required LeaveBalance balance,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditEntitlementSheet(balance: balance),
    );

class _EditEntitlementSheet extends ConsumerStatefulWidget {
  const _EditEntitlementSheet({required this.balance});

  final LeaveBalance balance;

  @override
  ConsumerState<_EditEntitlementSheet> createState() =>
      _EditEntitlementSheetState();
}

class _EditEntitlementSheetState
    extends ConsumerState<_EditEntitlementSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _days = TextEditingController(
    text: widget.balance.entitledDays.round().toString(),
  );

  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final employeeId = widget.balance.employeeId;
    if (employeeId == null) {
      setState(() => _error = 'This balance has no employee on it to save '
          'against.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(leaveRepositoryProvider).updateBalance(
            widget.balance.id,
            LeaveBalanceRequest(
              employeeId: employeeId,
              leaveType: widget.balance.leaveType,
              year: widget.balance.year,
              totalDays: int.parse(_days.text.trim()),
            ),
          );
      ref.invalidate(allBalancesProvider);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not save that entitlement.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final balance = widget.balance;

    return FormSheetFrame(
      title: 'Change the entitlement',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'Save',
      submitting: _busy,
      onSubmit: _submit,
      children: [
        Text(
          '${balance.employeeName ?? "This employee"} · '
          '${Fmt.label(balance.leaveType)} · ${balance.year}',
          style: TextStyle(color: bos.text, fontSize: 14),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _days,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Days a year'),
          validator: (value) {
            final days = int.tryParse(value?.trim() ?? '');
            if (days == null) return 'A whole number of days.';
            if (days < 0) return 'Not less than nothing.';
            return null;
          },
        ),
        const SizedBox(height: 10),
        Text(
          '${Fmt.plain(balance.usedDays)} used and '
          '${Fmt.plain(balance.pendingDays)} pending. Those come from the '
          'requests themselves and cannot be changed here.',
          style: TextStyle(color: bos.muted, fontSize: 11.5, height: 1.5),
        ),
      ],
    );
  }
}

/// The rules that decide how many days people get.
class _PoliciesTab extends ConsumerWidget {
  const _PoliciesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;

    return ConfigList<LeavePolicy>(
      // Only the ones in force. A switched-off policy still exists but grants
      // nothing, and this tab answers "what are people entitled to", not
      // "what has ever been written down" — that lives on the HR rules screen.
      async: ref.watch(activeLeavePoliciesProvider),
      onRefresh: () async => ref.invalidate(activeLeavePoliciesProvider),
      emptyIcon: Icons.rule_folder_outlined,
      emptyTitle: 'No policy is in force',
      emptyMessage:
          'Without one, nothing decides how many days people get — every '
          'balance has to be granted by hand.',
      errorMessage: 'Could not load the policies.',
      itemBuilder: (context, policy) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      Fmt.label(policy.leaveType),
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${policy.annualEntitlement} days',
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (policy.employmentType != null)
                    Fmt.label(policy.employmentType),
                  policy.paid ? 'paid' : 'unpaid',
                  if (policy.requiresApproval) 'needs approval',
                  if (policy.canCarryForward)
                    'carries ${policy.maxCarryForward} over',
                  if (policy.applicableFromMonths > 0)
                    'after ${policy.applicableFromMonths} months',
                ].join('  ·  '),
                style: TextStyle(color: bos.muted, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
