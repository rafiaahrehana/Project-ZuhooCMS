import 'package:flutter/material.dart';

/// A vertical rail of dated events — a status history, an approval chain, a
/// CRM activity log. Extracted from the requests module's own status-change
/// timeline so every detail screen with a "what happened, in order" section
/// draws the same rail rather than each re-implementing the dot-and-line
/// layout on its own.
///
/// This only draws the rail and lays out whatever [TimelineTile.child] each
/// entry provides — it carries no opinion about what a row's content looks
/// like, since a status change, an approval decision and a CRM activity all
/// show different things.
class Timeline extends StatelessWidget {
  const Timeline({super.key, required this.tiles, this.railColor});

  final List<TimelineTile> tiles;

  /// Defaults to the theme's border colour when omitted.
  final Color? railColor;

  @override
  Widget build(BuildContext context) {
    final rail = railColor ?? Theme.of(context).dividerColor;
    return Column(
      children: [
        for (var i = 0; i < tiles.length; i++)
          _RailRow(
            tile: tiles[i],
            isFirst: i == 0,
            isLast: i == tiles.length - 1,
            railColor: rail,
          ),
      ],
    );
  }
}

/// One event on a [Timeline]: a dot (coloured to mean whatever the caller
/// wants — a status, a stage, a completion state) and arbitrary content next
/// to it.
class TimelineTile {
  const TimelineTile({required this.dotColor, required this.child});

  final Color dotColor;
  final Widget child;
}

class _RailRow extends StatelessWidget {
  const _RailRow({
    required this.tile,
    required this.isFirst,
    required this.isLast,
    required this.railColor,
  });

  final TimelineTile tile;
  final bool isFirst;
  final bool isLast;
  final Color railColor;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A rail rather than a plain list: the order of events is the
          // information here, and a column of rows does not convey sequence.
          SizedBox(
            width: 22,
            child: Column(
              children: [
                Container(
                  width: 2,
                  height: 6,
                  color: isFirst ? Colors.transparent : railColor,
                ),
                Container(
                  height: 10,
                  width: 10,
                  decoration: BoxDecoration(
                    color: tile.dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast ? Colors.transparent : railColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: tile.child,
            ),
          ),
        ],
      ),
    );
  }
}
