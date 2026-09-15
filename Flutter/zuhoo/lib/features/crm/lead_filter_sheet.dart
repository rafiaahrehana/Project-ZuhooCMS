import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/paged_response.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/paged_controller.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/attachment_picker.dart';
import '../../shared/widgets/date_field.dart';
import '../../shared/widgets/form_sheet.dart';
import '../../shared/widgets/primitives.dart';
import 'crm_models.dart';
import 'crm_repository.dart';

/// The filter the Leads tab is using. An empty one means "no filter", and the
/// tab falls back to its plain views.
class LeadFilterController extends Notifier<LeadFilter> {
  @override
  LeadFilter build() => const LeadFilter();

  void set(LeadFilter filter) => state = filter;

  void clear() => state = const LeadFilter();
}

final leadFilterProvider =
    NotifierProvider<LeadFilterController, LeadFilter>(
  LeadFilterController.new,
);

/// Leads matching the current filter. Only asked for when the filter narrows
/// something — otherwise the tab uses its own view lists.
class FilteredLeadsController extends AsyncNotifier<PagedState<Lead>>
    with PagedLoader<Lead> {
  @override
  Future<PagedState<Lead>> build() {
    ref.watch(leadFilterProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<Lead>> fetchPage(int page) => ref
      .read(crmRepositoryProvider)
      .filterLeads(ref.read(leadFilterProvider), page: page);
}

final filteredLeadsProvider =
    AsyncNotifierProvider<FilteredLeadsController, PagedState<Lead>>(
  FilteredLeadsController.new,
);

/// How many leads are live, and how many are yours.
final leadCountsProvider =
    FutureProvider.autoDispose<({int active, int mine})>((ref) async {
  final repo = ref.read(crmRepositoryProvider);
  // Two calls rather than one; the backend has no combined endpoint. Run
  // together so the header does not take twice as long to appear.
  final results = await Future.wait([
    repo.activeLeadCount(),
    repo.myActiveLeadCount(),
  ]);
  return (active: results[0], mine: results[1]);
});

Future<void> showLeadFilterSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _LeadFilterSheet(),
    );

class _LeadFilterSheet extends ConsumerStatefulWidget {
  const _LeadFilterSheet();

  @override
  ConsumerState<_LeadFilterSheet> createState() => _LeadFilterSheetState();
}

class _LeadFilterSheetState extends ConsumerState<_LeadFilterSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _keyword =
      TextEditingController(text: ref.read(leadFilterProvider).keyword ?? '');

  late LeadFilter _filter = ref.read(leadFilterProvider);

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }

  void _apply() {
    ref.read(leadFilterProvider.notifier).set(
          _filter.copyWith(keyword: _keyword.text.trim()),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: 'Narrow the list',
      formKey: _formKey,
      error: null,
      onDismissError: () {},
      action: 'Apply',
      submitting: false,
      onSubmit: _apply,
      children: [
        TextFormField(
          controller: _keyword,
          decoration: const InputDecoration(
            labelText: 'Search',
            hintText: 'A name, a company, an email',
          ),
        ),
        const SizedBox(height: 12),
        _Choice(
          label: 'Status',
          value: _filter.status,
          options: LeadStatus.all,
          onChanged: (value) => setState(
            () => _filter = value == null
                ? _filter.copyWith(clearStatus: true)
                : _filter.copyWith(status: value),
          ),
        ),
        const SizedBox(height: 12),
        _Choice(
          label: 'Source',
          value: _filter.source,
          options: leadSources,
          onChanged: (value) => setState(
            () => _filter = value == null
                ? _filter.copyWith(clearSource: true)
                : _filter.copyWith(source: value),
          ),
        ),
        const SizedBox(height: 12),
        _Choice(
          label: 'Priority',
          value: _filter.priority,
          options: leadPriorities,
          onChanged: (value) => setState(
            () => _filter = value == null
                ? _filter.copyWith(clearPriority: true)
                : _filter.copyWith(priority: value),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DateField(
                label: 'Closing after',
                value: Fmt.parse(_filter.expectedCloseDateFrom),
                clearable: true,
                onChanged: (value) => setState(
                  () => _filter = _filter.copyWith(
                    expectedCloseDateFrom:
                        value == null ? null : Fmt.isoDate(value),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DateField(
                label: 'Closing before',
                value: Fmt.parse(_filter.expectedCloseDateTo),
                clearable: true,
                onChanged: (value) => setState(
                  () => _filter = _filter.copyWith(
                    expectedCloseDateTo:
                        value == null ? null : Fmt.isoDate(value),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _Flag(
          label: 'Only ones with something logged',
          value: _filter.hasActivity,
          onChanged: (value) =>
              setState(() => _filter = _filter.copyWith(hasActivity: value)),
        ),
        _Flag(
          label: 'Only unassigned',
          value: _filter.isUnassigned,
          onChanged: (value) =>
              setState(() => _filter = _filter.copyWith(isUnassigned: value)),
        ),
        _Flag(
          label: 'Only high priority',
          value: _filter.isHighPriority,
          onChanged: (value) =>
              setState(() => _filter = _filter.copyWith(isHighPriority: value)),
        ),
        _Flag(
          label: 'Only converted',
          value: _filter.isConverted,
          onChanged: (value) =>
              setState(() => _filter = _filter.copyWith(isConverted: value)),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _filter.sortBy,
                decoration: const InputDecoration(labelText: 'Order by'),
                items: [
                  for (final value in LeadFilter.sortOptions)
                    DropdownMenuItem(
                      value: value,
                      child: Text(_sortLabel(value)),
                    ),
                ],
                onChanged: (value) => setState(
                  () => _filter = _filter.copyWith(sortBy: value),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _filter.sortDirection,
                decoration: const InputDecoration(labelText: 'Direction'),
                items: const [
                  DropdownMenuItem(value: 'DESC', child: Text('Newest first')),
                  DropdownMenuItem(value: 'ASC', child: Text('Oldest first')),
                ],
                onChanged: (value) => setState(
                  () => _filter = _filter.copyWith(sortDirection: value),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () {
            ref.read(leadFilterProvider.notifier).clear();
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.clear_rounded, size: 17),
          label: const Text('Clear the filter'),
          style: TextButton.styleFrom(foregroundColor: bos.muted),
        ),
      ],
    );
  }

  static String _sortLabel(String value) => switch (value) {
        'createdAt' => 'When it came in',
        'lastActivityAt' => 'Last touched',
        'expectedCloseDate' => 'Expected close',
        'priority' => 'Priority',
        _ => value,
      };
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Any')),
        for (final option in options)
          DropdownMenuItem<String?>(
            value: option,
            child: Text(Fmt.label(option)),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

/// A flag with three states, because the backend has three.
///
/// Off is not the same as absent: `isUnassigned: false` asks for leads that
/// *do* have an owner, while leaving it out asks for both. The switch here
/// only ever sets it or clears it, since "only the assigned ones" is not
/// something anybody asks for on a phone.
class _Flag extends StatelessWidget {
  const _Flag({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool? value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return SwitchListTile.adaptive(
      value: value ?? false,
      onChanged: (on) => onChanged(on ? true : null),
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label, style: TextStyle(color: bos.text, fontSize: 13.5)),
    );
  }
}

// ── Importing and exporting ───────────────────────────────────

/// Bringing leads in from a CSV.
Future<void> showLeadImportSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ImportSheet(),
    );

class _ImportSheet extends ConsumerStatefulWidget {
  const _ImportSheet();

  @override
  ConsumerState<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends ConsumerState<_ImportSheet> {
  LeadImportResult? _result;
  String? _error;
  bool _busy = false;

  Future<void> _pick() async {
    final picked = await pickAttachment(context);
    if (picked == null || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(crmRepositoryProvider)
          .importLeads(picked.path, picked.name);
      setState(() => _result = result);
      ref.invalidate(leadCountsProvider);
    } on ApiException catch (e) {
      // An empty file, too many rows, or something that is not a CSV all come
      // back with the backend's own wording, which is more use than ours.
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not read that file.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final result = _result;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Import leads',
            style: TextStyle(
              color: bos.text,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'A CSV with a header row. Rows that cannot be used are reported '
            'rather than skipped quietly.',
            style: TextStyle(color: bos.muted, fontSize: 12.5, height: 1.5),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            MessageBanner.error(
              _error!,
              onDismiss: () => setState(() => _error = null),
            ),
          ],
          if (result != null) ...[
            const SizedBox(height: 14),
            Text(
              '${result.created} created',
              style: TextStyle(
                color: bos.success,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (result.skipped.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${result.skipped.length} skipped:',
                style: TextStyle(color: bos.warning, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final line in result.skipped)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          line,
                          style: TextStyle(
                            color: bos.muted,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
          const SizedBox(height: 14),
          LoadingButton(
            label: result == null ? 'Choose a file' : 'Import another',
            icon: Icons.upload_file_outlined,
            loading: _busy,
            onPressed: _pick,
          ),
        ],
      ),
    );
  }
}

/// Saves the lead list as a PDF and opens it.
Future<void> exportLeadsPdf(
  BuildContext context,
  WidgetRef ref, {
  String? status,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await ref.read(crmRepositoryProvider).leadsPdf(status: status);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}leads.pdf');
    await file.writeAsBytes(bytes, flush: true);

    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No app on this device can open a PDF.')),
      );
    }
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not produce that PDF.')),
    );
  }
}
