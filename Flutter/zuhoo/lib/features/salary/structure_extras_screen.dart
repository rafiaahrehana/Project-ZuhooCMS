import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import 'salary_models.dart';
import 'salary_repository.dart';
import 'template_models.dart';

/// Components bolted onto one person's structure on top of the recipe.
///
/// Saving replaces the whole set rather than adding to it — `setExtras`
/// deletes every extra on the structure and writes back exactly what it is
/// sent. So the screen holds the full list in hand and sends all of it, and
/// removing a line here really does mean removing it.
class StructureExtrasScreen extends ConsumerStatefulWidget {
  const StructureExtrasScreen({
    super.key,
    required this.structureId,
    required this.subtitle,
  });

  final int structureId;

  /// Which structure this is — the dates it covers, typically. The endpoint
  /// deals in ids and the screen needs something a person recognises.
  final String subtitle;

  static void open(
    BuildContext context, {
    required int structureId,
    required String subtitle,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StructureExtrasScreen(
          structureId: structureId,
          subtitle: subtitle,
        ),
      ),
    );
  }

  @override
  ConsumerState<StructureExtrasScreen> createState() =>
      _StructureExtrasScreenState();
}

class _StructureExtrasScreenState extends ConsumerState<StructureExtrasScreen> {
  /// The working copy. Null until the stored list has been read — sending
  /// before then would wipe whatever is there.
  List<StructureExtraLine>? _lines;

  String? _error;
  bool _busy = false;
  bool _dirty = false;

  Future<void> _save() async {
    final lines = _lines;
    if (lines == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(salaryRepositoryProvider)
          .setExtras(widget.structureId, lines);
      ref.invalidate(structureExtrasProvider(widget.structureId));
      if (!mounted) return;
      setState(() => _dirty = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved.')));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not save those components.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(List<SalaryComponent> catalogue) async {
    final chosen = _lines?.map((line) => line.componentId).toSet() ?? {};
    final available = catalogue
        .where((component) => component.active && !chosen.contains(component.id))
        .toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Every component in the catalogue is already on here.'),
        ),
      );
      return;
    }

    final componentId = await pickOne(
      context,
      options: [
        for (final component in available)
          (value: component.id.toString(), label: component.name),
      ],
    );
    if (componentId == null || !mounted) return;

    final amount = await askForText(
      context,
      title: 'How much?',
      message: 'The figure this component adds or takes off each month.',
      label: 'Amount',
      action: 'Add it',
      required: true,
    );
    if (amount == null || !mounted) return;

    final figure = double.tryParse(amount.trim());
    if (figure == null) {
      setState(() => _error = 'That did not read as a figure.');
      return;
    }

    setState(() {
      _lines = [
        ...?_lines,
        StructureExtraLine(
          componentId: int.parse(componentId),
          amount: figure,
        ),
      ];
      _dirty = true;
    });
  }

  void _remove(int componentId) {
    setState(() {
      _lines = [
        for (final line in _lines ?? const <StructureExtraLine>[])
          if (line.componentId != componentId) line,
      ];
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final canWrite =
        ref.watch(permissionControllerProvider).has(SalaryPermissions.create);
    final stored = ref.watch(structureExtrasProvider(widget.structureId));
    final catalogue =
        ref.watch(salaryComponentsProvider).value ?? const <SalaryComponent>[];

    // Seed the working copy the first time the stored list arrives, and not
    // again — otherwise a rebuild would throw away unsaved edits.
    final loaded = stored.value;
    if (loaded != null && _lines == null) {
      _lines = loaded.map(StructureExtraLine.from).toList();
    }

    String nameFor(int componentId) {
      for (final component in catalogue) {
        if (component.id == componentId) return component.name;
      }
      for (final extra in loaded ?? const <StructureExtra>[]) {
        if (extra.componentId == componentId) {
          return extra.componentName ?? 'A component';
        }
      }
      return 'A component';
    }

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(
        title: const Text('Extra components'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.subtitle,
                style: TextStyle(color: bos.muted, fontSize: 12),
              ),
            ),
          ),
        ),
      ),
      body: stored.when(
        loading: () => const Loader(),
        error: (error, _) => ErrorState(
          message: error is ApiException
              ? error.message
              : 'Could not load the components on this structure.',
          onRetry: () =>
              ref.invalidate(structureExtrasProvider(widget.structureId)),
        ),
        data: (_) {
          final lines = _lines ?? const <StructureExtraLine>[];

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              if (_error != null) ...[
                MessageBanner.error(
                  _error!,
                  onDismiss: () => setState(() => _error = null),
                ),
                const SizedBox(height: 12),
              ],
              if (lines.isEmpty)
                AppCard(
                  child: Text(
                    'Nothing extra on this structure. What it pays comes '
                    'entirely from the figures on the structure itself.',
                    style:
                        TextStyle(color: bos.muted, fontSize: 13, height: 1.5),
                  ),
                )
              else
                AppCard(
                  child: Column(
                    children: [
                      for (final line in lines)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  nameFor(line.componentId),
                                  style: TextStyle(
                                    color: bos.text,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ),
                              Text(
                                Fmt.money(line.amount),
                                style: TextStyle(
                                  color: bos.text,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (canWrite)
                                IconButton(
                                  tooltip:
                                      'Remove ${nameFor(line.componentId)}',
                                  onPressed: () => _remove(line.componentId),
                                  icon: Icon(
                                    Icons.close_rounded,
                                    size: 17,
                                    color: bos.muted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              if (canWrite) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _add(catalogue),
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: const Text('Add a component'),
                ),
                const SizedBox(height: 10),
                LoadingButton(
                  label: 'Save',
                  icon: Icons.check_rounded,
                  loading: _busy,
                  onPressed: _dirty ? _save : null,
                ),
                const SizedBox(height: 8),
                Text(
                  'Saving replaces the whole set. What is listed here is what '
                  'the structure will have.',
                  style: TextStyle(
                    color: bos.muted,
                    fontSize: 11.5,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
