import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import 'location_models.dart';
import 'location_repository.dart';
import 'platform_models.dart' show platformUserRoles;

/// The country/division/district reference hierarchy every address field in
/// the app picks from — public to browse, platform staff only to edit.
///
/// A phone has no room for Angular's five side-by-side columns, so this
/// drills into one branch at a time instead: pick a country, then its
/// divisions, and so on down to whichever level the country's data stops at.
class LocationsScreen extends ConsumerStatefulWidget {
  const LocationsScreen({super.key});

  @override
  ConsumerState<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends ConsumerState<LocationsScreen> {
  /// The drill-down trail: empty means "showing countries", and each entry
  /// after that is the node whose children are on screen.
  final List<GeoNode> _path = [];

  void _drillInto(GeoNode node) {
    if (node.type == 'LEVEL4') return;
    setState(() => _path.add(node));
  }

  bool _canPop(BuildContext context) => _path.isNotEmpty;

  void _up() => setState(() => _path.removeLast());

  /// Only called once a country has been drilled into — there is no
  /// create-a-country capability, so [_path] is never empty here. The child
  /// being added is one level deeper than [_path]'s last entry: `LEVEL1`
  /// straight under the country, `LEVEL2`-`LEVEL4` under whichever node is
  /// currently open.
  Future<void> _addChild() async {
    final level = _path.length;
    final country = _path.first;
    final name =
        await _promptForName(context, title: 'Add ${hierarchyLabel(country.code, level)}');
    if (name == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(locationRepositoryProvider).create(
            LocationCreateRequest(
              name: name,
              type: locationTypeForDepth(level - 1),
              countryId: level == 1 ? country.id : null,
              parentId: level == 1 ? null : _path.last.id,
            ),
          );
      _invalidateCurrentLevel();
      messenger.showSnackBar(const SnackBar(content: Text('Added.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not add that.')),
      );
    }
  }

  Future<void> _rename(GeoNode node) async {
    final name =
        await _promptForName(context, title: 'Rename', initial: node.name);
    if (name == null || name == node.name || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(locationRepositoryProvider)
          .update(node.id, LocationUpdateRequest(name: name));
      _invalidateCurrentLevel();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not rename that.')),
      );
    }
  }

  Future<void> _delete(GeoNode node) async {
    final confirmed = await confirmAction(
      context,
      title: 'Delete ${node.name}?',
      message: 'Everything under it goes too. This cannot be undone.',
      action: 'Delete',
    );
    if (!confirmed || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(locationRepositoryProvider).delete(node.id);
      _invalidateCurrentLevel();
      messenger.showSnackBar(SnackBar(content: Text('${node.name} deleted.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not delete that.')),
      );
    }
  }

  void _invalidateCurrentLevel() {
    if (_path.isEmpty) {
      ref.invalidate(countriesProvider);
    } else {
      final parent = _path.last;
      ref.invalidate(locationChildrenProvider(
        (parentId: parent.id, parentIsCountry: parent.isCountry),
      ));
    }
  }

  Future<String?> _promptForName(
    BuildContext context, {
    required String title,
    String? initial,
  }) async {
    final controller = TextEditingController(text: initial ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final value = controller.text.trim();
              Navigator.pop(dialogContext, value.isEmpty ? null : value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final user = ref.watch(currentUserProvider);
    final canManage = user?.hasAnyRole(platformUserRoles) ?? false;
    final depth = _path.length;
    final current = _path.isEmpty ? null : _path.last;

    final async = current == null
        ? ref.watch(countriesProvider)
        : ref.watch(locationChildrenProvider(
            (parentId: current.id, parentIsCountry: current.isCountry),
          ));

    return PopScope(
      canPop: !_canPop(context),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _up();
      },
      child: Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(
          title: Text(current?.name ?? 'Locations'),
          leading: _path.isEmpty
              ? null
              : IconButton(
                  // Not "Back" — it leaves the level rather than the screen,
                  // and the two do different things from here.
                  tooltip: 'Up one level',
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: _up,
                ),
        ),
        // Countries themselves are read-only reference data seeded on the
        // backend — nothing here can create one, so the FAB only appears once
        // a country has been drilled into, and never past LEVEL4.
        floatingActionButton: !canManage || current == null || current.type == 'LEVEL4'
            ? null
            : FloatingActionButton.extended(
                onPressed: _addChild,
                backgroundColor: bos.brand,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add_rounded),
                label: Text('Add ${hierarchyLabel(_path.first.code, depth)}'),
              ),
        body: RefreshIndicator(
          color: bos.brand,
          backgroundColor: bos.bgCard,
          onRefresh: () async => _invalidateCurrentLevel(),
          child: async.when(
            loading: () => const Loader(),
            error: (error, _) => ErrorState(
              message: error is ApiException
                  ? error.message
                  : 'Could not load that.',
              onRetry: _invalidateCurrentLevel,
            ),
            data: (nodes) {
              if (nodes.isEmpty) {
                return ListView(
                  children: [
                    const SizedBox(height: 60),
                    EmptyState(
                      icon: Icons.public_off_outlined,
                      title: 'Nothing here yet',
                      message: current == null
                          ? 'No countries are set up.'
                          : canManage
                              ? 'Add the first one below.'
                              : 'Nothing has been added here yet.',
                    ),
                  ],
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                itemCount: nodes.length,
                itemBuilder: (context, index) {
                  final node = nodes[index];
                  final isLeaf = node.type == 'LEVEL4';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      child: InkWell(
                        onTap: isLeaf ? null : () => _drillInto(node),
                        borderRadius: BorderRadius.circular(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                node.name,
                                style: TextStyle(
                                  color: bos.text,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (canManage && !node.isCountry)
                              PopupMenuButton<int>(
                                onSelected: (value) => value == 0
                                    ? _rename(node)
                                    : _delete(node),
                                itemBuilder: (context) => const [
                                  PopupMenuItem(value: 0, child: Text('Rename')),
                                  PopupMenuItem(
                                    value: 1,
                                    child: Text('Delete'),
                                  ),
                                ],
                              )
                            else if (!isLeaf)
                              Icon(Icons.chevron_right_rounded,
                                  color: bos.muted),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
