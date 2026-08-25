import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import 'primitives.dart';

/// An extra entry in a [ConfigRow]'s menu, past edit and retire.
class RowAction {
  const RowAction({
    required this.label,
    required this.onSelected,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onSelected;

  /// Drawn in the danger colour. For things that cannot be undone from here.
  final bool destructive;
}

/// One row in a configuration list.
///
/// The setup and catalogue lists differ only in what the subtitle says and what
/// the row does when tapped, so the chrome — the retired styling, the toggle,
/// the trailing menu — is written once and not eight times.
class ConfigRow extends StatelessWidget {
  const ConfigRow({
    super.key,
    required this.title,
    required this.active,
    this.subtitle,
    this.trailingLabel,
    this.onEdit,
    this.onToggle,
    this.actions = const [],
    this.inactiveLabel = 'Retired',
    this.busy = false,
  });

  final String title;
  final bool active;
  final String? subtitle;
  final String? trailingLabel;
  final VoidCallback? onEdit;
  final VoidCallback? onToggle;

  /// Appended below edit and retire, in order.
  final List<RowAction> actions;

  /// What the chip says when [active] is false. "Retired" suits a
  /// configuration list; a roster of people wants something else.
  final String inactiveLabel;

  final bool busy;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final hasMenu = onEdit != null || onToggle != null || actions.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            // A retired row stays legible but plainly reads as
                            // out of use, rather than being hidden — somebody
                            // has to be able to bring it back.
                            color: active ? bos.text : bos.muted,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (trailingLabel != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          trailingLabel!,
                          style: TextStyle(color: bos.muted, fontSize: 11.5),
                        ),
                      ],
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: bos.muted, fontSize: 12),
                    ),
                  ],
                  if (!active) ...[
                    const SizedBox(height: 6),
                    StatusChip('CANCELLED', label: inactiveLabel, dense: true),
                  ],
                ],
              ),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(10),
                child: SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (hasMenu)
              PopupMenuButton<int>(
                // Indices rather than names: the extra actions are supplied by
                // the caller and two of them could otherwise collide.
                onSelected: (value) {
                  if (value == -1) {
                    onEdit?.call();
                  } else if (value == -2) {
                    onToggle?.call();
                  } else {
                    actions[value].onSelected();
                  }
                },
                itemBuilder: (context) => [
                  if (onEdit != null)
                    const PopupMenuItem(value: -1, child: Text('Edit')),
                  if (onToggle != null)
                    PopupMenuItem(
                      value: -2,
                      child: Text(active ? 'Retire' : 'Restore'),
                    ),
                  for (var i = 0; i < actions.length; i++)
                    PopupMenuItem(
                      value: i,
                      child: Text(
                        actions[i].label,
                        style: actions[i].destructive
                            ? TextStyle(color: bos.danger)
                            : null,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// A row of choices above a list. One is always selected, and the first entry
/// is conventionally "everything", carrying a null value.
class FilterBar extends StatelessWidget {
  const FilterBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<({String? value, String label})> options;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: options.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final option = options[index];
            return ChoiceChip(
              label: Text(option.label),
              selected: option.value == selected,
              onSelected: (_) => onSelected(option.value),
            );
          },
        ),
      ),
    );
  }
}

/// Wraps a list that loads as a whole rather than a page at a time.
class ConfigList<T> extends StatelessWidget {
  const ConfigList({
    super.key,
    required this.async,
    required this.onRefresh,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.errorMessage,
    required this.itemBuilder,
    this.emptyIcon = Icons.tune_rounded,
    this.header,
  });

  final AsyncValue<List<T>> async;
  final Future<void> Function() onRefresh;
  final String emptyTitle;
  final String emptyMessage;
  final String errorMessage;
  final Widget Function(BuildContext, T) itemBuilder;
  final IconData emptyIcon;

  /// Drawn above the rows — a filter bar, a summary line. Not shown when the
  /// list is empty, where the empty state says everything there is to say.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return RefreshIndicator(
      color: bos.brand,
      backgroundColor: bos.bgCard,
      onRefresh: onRefresh,
      child: async.when(
        loading: () => const Loader(),
        error: (error, _) => ErrorState(
          message: error is ApiException ? error.message : errorMessage,
          onRetry: onRefresh,
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return ListView(
              children: [
                const SizedBox(height: 60),
                EmptyState(
                  icon: emptyIcon,
                  title: emptyTitle,
                  message: emptyMessage,
                ),
              ],
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
            itemCount: rows.length + (header == null ? 0 : 1),
            itemBuilder: (context, index) {
              if (header != null) {
                if (index == 0) return header!;
                return itemBuilder(context, rows[index - 1]);
              }
              return itemBuilder(context, rows[index]);
            },
          );
        },
      ),
    );
  }
}
