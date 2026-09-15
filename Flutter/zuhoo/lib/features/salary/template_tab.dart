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
import 'salary_models.dart';
import 'salary_repository.dart';
import 'template_models.dart';

/// The salary recipes a grade's pay is built from.
class TemplatesTab extends ConsumerWidget {
  const TemplatesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(permissionControllerProvider);
    final canWrite = permissions.has(SalaryPermissions.create);
    final canDelete = permissions.has(SalaryPermissions.delete);

    return ConfigList<SalaryTemplate>(
      async: ref.watch(salaryTemplatesProvider),
      onRefresh: () async => ref.invalidate(salaryTemplatesProvider),
      emptyIcon: Icons.tune_rounded,
      emptyTitle: 'No templates',
      emptyMessage:
          'A template is a grade — what it pays, and how that splits into '
          'basic, house rent and the allowances.',
      errorMessage: 'Could not load the templates.',
      itemBuilder: (context, template) => _TemplateRow(
        template: template,
        canWrite: canWrite,
        canDelete: canDelete,
      ),
    );
  }
}

class _TemplateRow extends ConsumerStatefulWidget {
  const _TemplateRow({
    required this.template,
    required this.canWrite,
    required this.canDelete,
  });

  final SalaryTemplate template;
  final bool canWrite;
  final bool canDelete;

  @override
  ConsumerState<_TemplateRow> createState() => _TemplateRowState();
}

class _TemplateRowState extends ConsumerState<_TemplateRow> {
  bool _busy = false;

  Future<void> _delete() async {
    final confirmed = await confirmAction(
      context,
      title: 'Delete ${widget.template.structureName}?',
      message: 'Structures already built from it keep their figures. Only the '
          'recipe goes.',
      action: 'Delete',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(salaryRepositoryProvider)
          .deleteTemplate(widget.template.id);
      ref.invalidate(salaryTemplatesProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Deleted.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not delete that template.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final template = widget.template;

    final facts = <String>[
      if (template.defaultGross != null) Fmt.money(template.defaultGross),
      'basic ${Fmt.percent(template.basicPercentage)}',
      'house rent ${Fmt.percent(template.hraPercentage)} of basic',
    ];

    return ConfigRow(
      title: template.structureName,
      subtitle: facts.join('  ·  '),
      active: template.active,
      busy: _busy,
      onEdit: widget.canWrite
          ? () => showTemplateSheet(context, template: template)
          : null,
      actions: [
        RowAction(
          label: 'Work it out',
          onSelected: () =>
              showBreakdownSheet(context, template: template),
        ),
        if (widget.canDelete)
          RowAction(label: 'Delete', destructive: true, onSelected: _delete),
      ],
    );
  }
}

/// Writing a template, or rewriting one.
///
/// Every figure is sent whether it was touched or not. The backend assigns
/// them all and turns a missing one into zero, so a partial payload is how an
/// allowance quietly disappears.
Future<void> showTemplateSheet(
  BuildContext context, {
  SalaryTemplate? template,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TemplateSheet(template: template),
    );

class _TemplateSheet extends ConsumerStatefulWidget {
  const _TemplateSheet({this.template});

  final SalaryTemplate? template;

  @override
  ConsumerState<_TemplateSheet> createState() => _TemplateSheetState();
}

class _TemplateSheetState extends ConsumerState<_TemplateSheet> {
  final _formKey = GlobalKey<FormState>();

  late final _name =
      TextEditingController(text: widget.template?.structureName ?? '');
  late final _gross = _money(widget.template?.defaultGross);
  late final _basic = _money(widget.template?.basicPercentage ?? 50);
  late final _hra = _money(widget.template?.hraPercentage ?? 40);
  late final _medical = _money(widget.template?.medicalAmount ?? 0);
  late final _transport = _money(widget.template?.transportAmount ?? 0);
  late final _internet = _money(widget.template?.internetAmount ?? 0);
  late final _mobile = _money(widget.template?.mobileAmount ?? 0);
  late final _meal = _money(widget.template?.mealAmount ?? 0);
  late bool _active = widget.template?.active ?? true;

  String? _error;
  bool _busy = false;

  static TextEditingController _money(double? value) =>
      TextEditingController(text: value == null ? '' : Fmt.plain(value));

  @override
  void dispose() {
    for (final controller in [
      _name,
      _gross,
      _basic,
      _hra,
      _medical,
      _transport,
      _internet,
      _mobile,
      _meal,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  double _read(TextEditingController controller) =>
      double.tryParse(controller.text.trim()) ?? 0;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final request = SalaryTemplateRequest(
      structureName: _name.text.trim(),
      defaultGross: double.tryParse(_gross.text.trim()),
      basicPercentage: _read(_basic),
      hraPercentage: _read(_hra),
      medicalAmount: _read(_medical),
      transportAmount: _read(_transport),
      internetAmount: _read(_internet),
      mobileAmount: _read(_mobile),
      mealAmount: _read(_meal),
      active: _active,
    );

    try {
      final repo = ref.read(salaryRepositoryProvider);
      if (widget.template == null) {
        await repo.createTemplate(request);
      } else {
        await repo.updateTemplate(widget.template!.id, request);
      }
      ref.invalidate(salaryTemplatesProvider);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not save that template.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: widget.template == null ? 'New template' : 'Edit template',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'Save',
      submitting: _busy,
      onSubmit: _submit,
      children: [
        TextFormField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Grade',
            hintText: 'Software Engineer Grade A',
          ),
          validator: (value) =>
              (value?.trim().isEmpty ?? true) ? 'A name, please.' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _gross,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'What the grade pays',
            hintText: 'Fills the gross when the template is chosen.',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _basic,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Basic',
                  suffixText: '% of gross',
                ),
                validator: _percentage,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _hra,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'House rent',
                  suffixText: '% of basic',
                ),
                validator: _percentage,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Fixed allowances',
          style: TextStyle(
            color: bos.muted,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 8),
        _AmountRow(left: _medical, leftLabel: 'Medical', right: _transport, rightLabel: 'Transport'),
        const SizedBox(height: 12),
        _AmountRow(left: _internet, leftLabel: 'Internet', right: _mobile, rightLabel: 'Mobile'),
        const SizedBox(height: 12),
        TextFormField(
          controller: _meal,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Meals'),
        ),
        const SizedBox(height: 4),
        SwitchListTile.adaptive(
          value: _active,
          onChanged: (value) => setState(() => _active = value),
          contentPadding: EdgeInsets.zero,
          title: Text(
            'In use',
            style: TextStyle(color: bos.text, fontSize: 14),
          ),
        ),
        Text(
          'Every figure above is saved as it stands here, including the blank '
          'ones. Clearing a box sets that allowance to nothing.',
          style: TextStyle(color: bos.muted, fontSize: 11.5, height: 1.5),
        ),
      ],
    );
  }

  static String? _percentage(String? value) {
    final number = double.tryParse(value?.trim() ?? '');
    if (number == null) return 'A percentage, please.';
    if (number < 0 || number > 100) return 'Between 0 and 100.';
    return null;
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.left,
    required this.leftLabel,
    required this.right,
    required this.rightLabel,
  });

  final TextEditingController left;
  final String leftLabel;
  final TextEditingController right;
  final String rightLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: left,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: leftLabel),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            controller: right,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: rightLabel),
          ),
        ),
      ],
    );
  }
}

/// What a template pays out at a given gross.
///
/// The arithmetic is done server-side rather than here, so what this shows is
/// what payroll would actually produce.
Future<void> showBreakdownSheet(
  BuildContext context, {
  required SalaryTemplate template,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BreakdownSheet(template: template),
    );

class _BreakdownSheet extends ConsumerStatefulWidget {
  const _BreakdownSheet({required this.template});

  final SalaryTemplate template;

  @override
  ConsumerState<_BreakdownSheet> createState() => _BreakdownSheetState();
}

class _BreakdownSheetState extends ConsumerState<_BreakdownSheet> {
  late final _gross = TextEditingController(
    text: widget.template.defaultGross == null
        ? ''
        : Fmt.plain(widget.template.defaultGross!),
  );

  SalaryBreakdown? _breakdown;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.template.defaultGross != null) _work();
  }

  @override
  void dispose() {
    _gross.dispose();
    super.dispose();
  }

  Future<void> _work() async {
    final gross = double.tryParse(_gross.text.trim());
    if (gross == null || gross <= 0) {
      setState(() => _error = 'A gross figure, please.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final breakdown = await ref
          .read(salaryRepositoryProvider)
          .breakdown(widget.template.id, gross);
      setState(() => _breakdown = breakdown);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not work that out.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final breakdown = _breakdown;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.template.structureName,
              style: TextStyle(
                color: bos.text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _gross,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Gross'),
                    onSubmitted: (_) => _work(),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 110,
                  child: LoadingButton(
                    label: 'Work it out',
                    loading: _busy,
                    onPressed: _work,
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              MessageBanner.error(
                _error!,
                onDismiss: () => setState(() => _error = null),
              ),
            ],
            if (breakdown != null) ...[
              const SizedBox(height: 16),
              for (final entry in breakdown.lines.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _readable(entry.key),
                          style: TextStyle(
                            color: entry.key == 'grossSalary'
                                ? bos.text
                                : bos.muted,
                            fontSize: 13,
                            fontWeight: entry.key == 'grossSalary'
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      Text(
                        Fmt.money(entry.value),
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 13,
                          fontWeight: entry.key == 'grossSalary'
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              if (breakdown.overrun > 0) ...[
                const SizedBox(height: 10),
                MessageBanner.warning(
                  'The parts add up to ${Fmt.money(breakdown.overrun)} more '
                  'than the gross. The internet and mobile allowances are not '
                  'taken out of the gross before the special allowance is '
                  'worked out, so they sit on top of it.',
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Turns a breakdown key into something readable.
///
/// Not [Fmt.label], which is built for the SCREAMING_SNAKE the rest of this
/// API uses and would render "grossSalary" as "Grosssalary". These keys are
/// camelCase, and the backend builds the map by hand rather than from an enum.
String _readable(String key) {
  final spaced = key.replaceAllMapped(
    RegExp(r'(?<=[a-z])(?=[A-Z])'),
    (_) => ' ',
  );
  return spaced[0].toUpperCase() + spaced.substring(1).toLowerCase();
}
