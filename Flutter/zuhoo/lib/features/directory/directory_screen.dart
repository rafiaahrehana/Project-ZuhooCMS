import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/search_field.dart';
import '../../shared/widgets/primitives.dart';
import 'directory_models.dart';
import 'directory_repository.dart';
import 'employee_form_sheet.dart';
import 'person_detail_screen.dart';

/// Who works here.
///
/// Gated on EMPLOYEE_VIEW to match the web app. The API would serve any
/// employee — see [DirectoryPermissions.employeeView] for why that difference
/// is not taken as licence to open it up here.
class DirectoryScreen extends ConsumerWidget {
  const DirectoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final permissions = ref.watch(permissionControllerProvider);

    if (!permissions.loaded && permissions.codes.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Employees')),
        body: const Loader(),
      );
    }

    if (!permissions.has(DirectoryPermissions.employeeView)) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Employees')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Not available to you',
          message:
              'Browsing colleagues needs the employee directory permission. '
              'Your HR team can grant it.',
        ),
      );
    }

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(
        title: const Text('Employees'),
        actions: [
          IconButton(
            tooltip: 'Export a PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => _exportPdf(context, ref),
          ),
        ],
      ),
      floatingActionButton:
          permissions.has(DirectoryPermissions.employeeCreate)
              ? FloatingActionButton.extended(
                  onPressed: () => showNewEmployeeSheet(context),
                  backgroundColor: bos.brand,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.person_add_alt_rounded),
                  label: const Text('New employee'),
                )
              : null,
      body: Column(
        children: [
          const _SearchField(),
          const _DepartmentFilter(),
          Expanded(
            child: PagedListView<Person>(
              async: ref.watch(directoryProvider),
              onRefresh: () => ref.read(directoryProvider.notifier).refresh(),
              onLoadMore: () => ref.read(directoryProvider.notifier).loadMore(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
              emptyTitle: 'Nobody here',
              emptyMessage:
                  'No colleague matches that. Try a different name or clear '
                  'the filters.',
              emptyIcon: Icons.person_search_outlined,
              errorMessage: 'Could not load the directory.',
              itemBuilder: (context, person) => _PersonRow(person: person),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends ConsumerWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: AppSearchField(
        hint: 'Search by name',
        // Debounced, because every change to the term restarts a paged
        // request. Typing a six-letter name would otherwise fire six searches
        // and let an earlier, slower one land last.
        onChanged: (value) =>
            ref.read(directorySearchProvider.notifier).set(value),
      ),
    );
  }
}

class _DepartmentFilter extends ConsumerWidget {
  const _DepartmentFilter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final departments = ref.watch(departmentsProvider).value ?? const [];
    if (departments.isEmpty) return const SizedBox.shrink();

    final selected = ref.watch(departmentFilterProvider);

    return SizedBox(
      height: scaledStripHeight(context, 42),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: departments.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i == 0) {
            return _Chip(
              label: 'Everyone',
              active: selected == null,
              onTap: () => ref.read(departmentFilterProvider.notifier).set(null),
            );
          }
          final department = departments[i - 1];
          final count = department.employeeCount;
          return _Chip(
            label: count == null || count == 0
                ? department.name
                : '${department.name} · $count',
            active: selected == department.id,
            onTap: () => ref
                .read(departmentFilterProvider.notifier)
                .set(selected == department.id ? null : department.id),
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? bos.brand : bos.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? bos.brand : bos.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : bos.textSecondary,
            fontSize: 12.5,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => PersonDetailScreen.open(context, person: person),
        child: AppCard(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Avatar(
                initials: person.initials,
                imageUrl: person.imageUrl,
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            person.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: bos.text,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (person.isFormer) ...[
                          const SizedBox(width: 6),
                          StatusChip(
                            person.employmentStatus!,
                            label: 'Left',
                            dense: true,
                          ),
                        ],
                      ],
                    ),
                    if (person.roleLabel != null)
                      Text(
                        person.roleLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: bos.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    if (person.departmentName != null)
                      Text(
                        person.departmentName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: bos.muted, fontSize: 11.5),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: bos.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Saves the people list as a PDF and opens it.
///
/// Narrowed the same way the screen is, so the printed list matches what was
/// on it — a discrepancy between the two gets noticed at the worst moment.
Future<void> _exportPdf(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await ref.read(directoryRepositoryProvider).peoplePdf(
          search: ref.read(directorySearchProvider),
          departmentId: ref.read(departmentFilterProvider),
        );
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}people.pdf');
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
