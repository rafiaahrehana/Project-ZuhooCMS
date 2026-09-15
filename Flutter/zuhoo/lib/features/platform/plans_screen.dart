import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/config_list.dart';
import '../../shared/widgets/form_sheet.dart';
import 'platform_create_sheets.dart';
import 'platform_models.dart';
import 'platform_repository.dart';

/// Every plan, switched-off ones included.
///
/// Distinct from [subscriptionPlansProvider], which asks for the active ones
/// only because it feeds the picker that moves a company onto a plan. This
/// screen has to show the retired ones too, or there would be no way to turn
/// one back on.
final allPlansProvider =
    FutureProvider.autoDispose<List<SubscriptionPlanOption>>((ref) {
  return ref.read(platformRepositoryProvider).plans(activeOnly: false);
});

/// The plans on offer.
class PlansScreen extends ConsumerWidget {
  const PlansScreen({super.key});

  static void open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PlansScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Plans')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await showNewSubscriptionPlanSheet(context);
          ref.invalidate(allPlansProvider);
          ref.invalidate(subscriptionPlansProvider);
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('New plan'),
      ),
      body: ConfigList<SubscriptionPlanOption>(
        async: ref.watch(allPlansProvider),
        onRefresh: () async {
          ref.invalidate(allPlansProvider);
          ref.invalidate(subscriptionPlansProvider);
        },
        emptyIcon: Icons.workspace_premium_outlined,
        emptyTitle: 'No plans defined',
        emptyMessage:
            'Until there is a plan, no company can be moved onto one.',
        errorMessage: 'Could not load the plans.',
        itemBuilder: (context, plan) => _PlanRow(plan: plan),
      ),
    );
  }
}

class _PlanRow extends ConsumerStatefulWidget {
  const _PlanRow({required this.plan});

  final SubscriptionPlanOption plan;

  @override
  ConsumerState<_PlanRow> createState() => _PlanRowState();
}

class _PlanRowState extends ConsumerState<_PlanRow> {
  bool _busy = false;

  Future<void> _toggle() async {
    final id = widget.plan.id;
    if (id == null) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(platformRepositoryProvider).togglePlan(id);
      ref.invalidate(allPlansProvider);
      ref.invalidate(subscriptionPlansProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.plan.active
                ? '${widget.plan.name} is off the menu. Companies already on '
                    'it stay on it.'
                : '${widget.plan.name} is on offer again.',
          ),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not change that plan.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;

    return ConfigRow(
      title: plan.name,
      subtitle: [
        plan.key,
        if (plan.price != null) Fmt.money(plan.price),
        if (plan.billingCycle != null) Fmt.label(plan.billingCycle),
      ].join('  ·  '),
      active: plan.active,
      inactiveLabel: 'Off the menu',
      busy: _busy,
      // The id is what the write endpoints key on, and an older response
      // shape did not carry it. Without one there is nothing to edit.
      onEdit: plan.id == null
          ? null
          : () => showEditPlanSheet(context, plan: plan),
      onToggle: plan.id == null ? null : _toggle,
    );
  }
}

/// Changing a plan.
///
/// The code is shown but not editable. A company's `subscriptionPlan` stores
/// that string, and so does every row of subscription history — changing it
/// would orphan all of them, which is why the backend refuses.
Future<void> showEditPlanSheet(
  BuildContext context, {
  required SubscriptionPlanOption plan,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditPlanSheet(plan: plan),
    );

class _EditPlanSheet extends ConsumerStatefulWidget {
  const _EditPlanSheet({required this.plan});

  final SubscriptionPlanOption plan;

  @override
  ConsumerState<_EditPlanSheet> createState() => _EditPlanSheetState();
}

class _EditPlanSheetState extends ConsumerState<_EditPlanSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.plan.name);
  late final _description =
      TextEditingController(text: widget.plan.description ?? '');
  late final _price = TextEditingController(
    text: widget.plan.price == null ? '' : Fmt.plain(widget.plan.price!),
  );
  late String _cycle = billingCycles.contains(widget.plan.billingCycle)
      ? widget.plan.billingCycle!
      : billingCycles.first;

  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(platformRepositoryProvider).updatePlan(
            widget.plan.id!,
            CreateSubscriptionPlanRequest(
              // Sent because the request model requires it, and dropped again
              // by the repository — the backend ignores it either way.
              code: widget.plan.key,
              name: _name.text,
              billingCycle: _cycle,
              price: double.parse(_price.text.trim()),
              description: _description.text,
            ),
          );
      ref.invalidate(allPlansProvider);
      ref.invalidate(subscriptionPlansProvider);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not save that plan.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: 'Edit plan',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'Save',
      submitting: _busy,
      onSubmit: _submit,
      children: [
        TextFormField(
          initialValue: widget.plan.key,
          readOnly: true,
          decoration: const InputDecoration(
            labelText: 'Code',
            helperText: 'Fixed once created.',
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
          validator: (value) =>
              (value?.trim().isEmpty ?? true) ? 'A name, please.' : null,
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _price,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Price'),
                validator: (value) {
                  final price = double.tryParse(value?.trim() ?? '');
                  if (price == null) return 'A figure, please.';
                  if (price < 0) return 'Not less than nothing.';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _cycle,
                decoration: const InputDecoration(labelText: 'Billed'),
                items: [
                  for (final value in billingCycles)
                    DropdownMenuItem(
                      value: value,
                      child: Text(Fmt.label(value)),
                    ),
                ],
                onChanged: (value) => setState(() => _cycle = value ?? _cycle),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _description,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Description'),
        ),
        const SizedBox(height: 10),
        Text(
          'Changing the price does not change what any company is already '
          'paying — it is what the next company on this plan will pay.',
          style: TextStyle(color: bos.muted, fontSize: 11.5, height: 1.5),
        ),
      ],
    );
  }
}
