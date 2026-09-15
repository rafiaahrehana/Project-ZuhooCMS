import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/attachment_picker.dart';
import '../../shared/widgets/config_list.dart';
import '../../shared/widgets/primitives.dart';
import 'itam_models.dart';
import 'itam_repository.dart';

/// Who has had what.
///
/// A row per spell rather than per event: a piece of kit going out and coming
/// back is one entry, with the condition recorded at each end. An entry with
/// no return date is somebody who still has it.
class AssetHistoryScreen extends ConsumerWidget {
  const AssetHistoryScreen({super.key});

  static void open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AssetHistoryScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Where the kit has been')),
      body: ConfigList<AssetHistoryEntry>(
        async: ref.watch(assetHistoryProvider),
        onRefresh: () async => ref.invalidate(assetHistoryProvider),
        emptyIcon: Icons.history_rounded,
        emptyTitle: 'Nothing handed out yet',
        emptyMessage:
            'Every hand-over and return appears here once assets start '
            'moving.',
        errorMessage: 'Could not load the history.',
        itemBuilder: (context, entry) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    entry.stillOut
                        ? Icons.arrow_outward_rounded
                        : Icons.keyboard_return_rounded,
                    size: 16,
                    color: entry.stillOut ? bos.warning : bos.muted,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.assetName ?? 'An asset',
                        style: TextStyle(color: bos.text, fontSize: 13.5),
                      ),
                      Text(
                        entry.employeeName ?? 'Somebody',
                        style: TextStyle(
                          color: bos.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.stillOut
                            ? 'out since ${Fmt.dateShort(entry.assignedAt)}'
                            : '${Fmt.dateShort(entry.assignedAt)} — '
                                '${Fmt.dateShort(entry.returnedAt)}',
                        style: TextStyle(color: bos.muted, fontSize: 11.5),
                      ),
                      if (entry.condition != null ||
                          entry.conditionOnReturn != null)
                        Text(
                          entry.conditionOnReturn == null
                              ? 'went out ${Fmt.label(entry.condition)}'
                              : 'went out ${Fmt.label(entry.condition)}, '
                                  'came back ${Fmt.label(entry.conditionOnReturn)}',
                          style: TextStyle(color: bos.muted, fontSize: 11.5),
                        ),
                      if (entry.notes != null && entry.notes!.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            entry.notes!,
                            style: TextStyle(
                              color: bos.muted,
                              fontSize: 11.5,
                              height: 1.4,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bringing assets in from a CSV.
///
/// The template comes from the backend, but it is a download the phone has
/// nowhere useful to put — so the sheet says what the file needs rather than
/// offering one.
Future<void> showAssetImportSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AssetImportSheet(),
    );

class _AssetImportSheet extends ConsumerStatefulWidget {
  const _AssetImportSheet();

  @override
  ConsumerState<_AssetImportSheet> createState() => _AssetImportSheetState();
}

class _AssetImportSheetState extends ConsumerState<_AssetImportSheet> {
  AssetImportResult? _result;
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
          .read(itamRepositoryProvider)
          .importAssets(picked.path, picked.name);
      setState(() => _result = result);
      // Anything created is now in the hardware list behind this sheet.
      ref.read(assetsProvider.notifier).refresh();
    } on ApiException catch (e) {
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
            'Import assets',
            style: TextStyle(
              color: bos.text,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'A CSV with a header row. Rows that cannot be used are reported '
            'with their line number, so the file can be fixed and tried '
            'again.',
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
              '${result.succeeded} of ${result.totalRows} imported',
              style: TextStyle(
                color: result.failed == 0 ? bos.success : bos.warning,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (result.errors.isNotEmpty) ...[
              const SizedBox(height: 10),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final error in result.errors)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 46,
                              child: Text(
                                'Row ${error.row}',
                                style: TextStyle(
                                  color: bos.muted,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                error.reason,
                                style: TextStyle(
                                  color: bos.text,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
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
