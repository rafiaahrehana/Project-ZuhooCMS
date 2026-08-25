import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/widgets/config_list.dart';
import '../../shared/widgets/primitives.dart';
import 'workflow_models.dart';
import 'workflow_repository.dart';
import 'workflow_sheets.dart';

/// The stages a service request moves through.
///
/// A template is a short ordered list, which is the one part of the workflow
/// designer that fits a phone. The service form-field designer beside it —
/// typed fields nested inside stages — stays on the web.
class WorkflowScreen extends ConsumerStatefulWidget {
  const WorkflowScreen({super.key});

  @override
  ConsumerState<WorkflowScreen> createState() => _WorkflowScreenState();
}

class _WorkflowScreenState extends ConsumerState<WorkflowScreen> {
  int? _busyId;

  Future<void> _toggle(WorkflowTemplate row) async {
    setState(() => _busyId = row.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await ref.read(workflowRepositoryProvider).toggle(row.id);
      ref.read(workflowsProvider.notifier).apply(updated);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not change that workflow.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _delete(WorkflowTemplate row) async {
    final bos = Theme.of(context).bos;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${row.name}?'),
        content: const Text(
          'Services that use it fall back to the default stages. Requests '
          'already running keep the path they are on.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Never mind'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: bos.danger),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyId = row.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(workflowRepositoryProvider).delete(row.id);
      ref.read(workflowsProvider.notifier).remove(row.id);
      messenger.showSnackBar(SnackBar(content: Text('${row.name} removed.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not remove that workflow.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final permissions = ref.watch(permissionControllerProvider);

    if (!permissions.loaded && permissions.codes.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Workflows')),
        body: const Loader(),
      );
    }

    if (!permissions.has(WorkflowPermissions.view)) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Workflows')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Not available to you',
          message:
              'Designing workflows needs administrator permissions. Your owner '
              'can grant them.',
        ),
      );
    }

    final canEdit = permissions.has(WorkflowPermissions.update);
    final canDelete = permissions.has(WorkflowPermissions.delete);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Workflows')),
      floatingActionButton: permissions.has(WorkflowPermissions.create)
          ? FloatingActionButton.extended(
              onPressed: () => showWorkflowSheet(context),
              backgroundColor: bos.brand,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New'),
            )
          : null,
      body: ConfigList<WorkflowTemplate>(
        async: ref.watch(workflowsProvider),
        onRefresh: ref.read(workflowsProvider.notifier).refresh,
        emptyIcon: Icons.account_tree_outlined,
        emptyTitle: 'No workflows yet',
        emptyMessage:
            'A workflow is the ordered set of stages a request moves through — '
            'who does what, in what order, and what has to be signed off.',
        errorMessage: 'Could not load the workflows.',
        itemBuilder: (context, row) => ConfigRow(
          title: row.name,
          active: row.active,
          subtitle: [
            row.stages.isEmpty
                ? 'No stages yet'
                : '${row.stages.length} stages',
            if (row.totalDays != null) '${row.totalDays} days',
            'v${row.version}',
          ].join(' · '),
          busy: _busyId == row.id,
          onEdit: canEdit ? () => showWorkflowSheet(context, existing: row) : null,
          onToggle: canEdit ? () => _toggle(row) : null,
          actions: [
            RowAction(
              label: row.stages.isEmpty ? 'Add stages' : 'Stages',
              onSelected: () => WorkflowStagesScreen.open(context, template: row),
            ),
            if (canDelete)
              RowAction(
                label: 'Remove',
                destructive: true,
                onSelected: () => _delete(row),
              ),
          ],
        ),
      ),
    );
  }
}

/// One workflow's stages, in order.
class WorkflowStagesScreen extends ConsumerWidget {
  const WorkflowStagesScreen({super.key, required this.template});

  final WorkflowTemplate template;

  static void open(BuildContext context, {required WorkflowTemplate template}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkflowStagesScreen(template: template),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final permissions = ref.watch(permissionControllerProvider);
    final canEdit = permissions.has(WorkflowPermissions.update);
    final detail = ref.watch(workflowDetailProvider(template.id));

    // The list the screen was opened from is enough to draw with while the
    // fresh copy loads — it carries the stages too.
    final current = detail.value ?? template;
    final nextOrder = current.stages.isEmpty
        ? 1
        : current.stages
                .map((stage) => stage.stageOrder)
                .reduce((a, b) => a > b ? a : b) +
            1;

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(
        title: Text(current.name),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Version ${current.version}',
              style: TextStyle(color: bos.muted, fontSize: 12),
            ),
          ),
        ),
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => showStageSheet(
                context,
                templateId: current.id,
                nextOrder: nextOrder,
              ),
              backgroundColor: bos.brand,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Stage'),
            )
          : null,
      body: detail.hasError && detail.value == null
          ? ErrorState(
              message: detail.error is ApiException
                  ? (detail.error! as ApiException).message
                  : 'Could not load that workflow.',
              onRetry: () => ref.invalidate(workflowDetailProvider(template.id)),
            )
          : RefreshIndicator(
              color: bos.brand,
              backgroundColor: bos.bgCard,
              onRefresh: () async =>
                  ref.invalidate(workflowDetailProvider(template.id)),
              child: current.stages.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 60),
                        EmptyState(
                          icon: Icons.flag_outlined,
                          title: 'No stages yet',
                          message:
                              'Add the steps a request goes through, in the '
                              'order they happen.',
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                      itemCount: current.stages.length,
                      itemBuilder: (context, index) {
                        final stage = current.stages[index];
                        return _StageCard(
                          stage: stage,
                          isLast: index == current.stages.length - 1,
                          onEdit: canEdit
                              ? () => showStageSheet(
                                    context,
                                    templateId: current.id,
                                    nextOrder: nextOrder,
                                    existing: stage,
                                  )
                              : null,
                          onDelete: canEdit
                              ? () => deleteStage(
                                    context,
                                    ref,
                                    templateId: current.id,
                                    stage: stage,
                                  )
                              : null,
                        );
                      },
                    ),
            ),
    );
  }
}

class _StageCard extends StatelessWidget {
  const _StageCard({
    required this.stage,
    required this.isLast,
    this.onEdit,
    this.onDelete,
  });

  final WorkflowStage stage;

  /// The connecting line is drawn between stages, not after the last one.
  final bool isLast;

  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    final facts = <String>[
      if (stage.estimatedDays != null) '${stage.estimatedDays} days',
      if (stage.slaHours != null) '${stage.slaHours}h SLA',
      if (stage.assigneeRole != null) stage.assigneeRole!,
      if (stage.requiresApproval) 'needs approval',
      if (stage.requiresPayment)
        stage.paymentPercent == null
            ? 'needs payment'
            : '${stage.paymentPercent}% due',
    ];

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The order runs down the left as a rail, so the sequence reads at a
          // glance rather than having to be inferred from the numbers.
          Column(
            children: [
              Container(
                height: 26,
                width: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: bos.brand.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${stage.stageOrder}',
                  style: TextStyle(
                    color: bos.brand,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(child: Container(width: 2, color: bos.borderLight)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
              child: AppCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stage.name,
                            style: TextStyle(
                              color: bos.text,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (stage.description != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              stage.description!,
                              style: TextStyle(
                                color: bos.text,
                                fontSize: 12.5,
                                height: 1.4,
                              ),
                            ),
                          ],
                          if (facts.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              facts.join(' · '),
                              style:
                                  TextStyle(color: bos.muted, fontSize: 11.5),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (onEdit != null || onDelete != null)
                      PopupMenuButton<String>(
                        onSelected: (value) => value == 'edit'
                            ? onEdit?.call()
                            : onDelete?.call(),
                        itemBuilder: (context) => [
                          if (onEdit != null)
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('Edit'),
                            ),
                          if (onDelete != null)
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(
                                'Remove',
                                style: TextStyle(color: bos.danger),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
