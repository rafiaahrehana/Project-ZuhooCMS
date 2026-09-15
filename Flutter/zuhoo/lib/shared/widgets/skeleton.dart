import 'package:flutter/material.dart';

import '../../core/theme/bos_tokens.dart';

/// Placeholder blocks shaped like the content that is coming.
///
/// A spinner says "something is happening"; a skeleton says "a list of rows is
/// happening, and here is roughly where each one will sit". The second stops
/// the screen jumping when the data lands, because the space is already
/// reserved at about the right size.
///
/// Worth being clear about where this belongs. [Loader] is still the right
/// answer for a small area whose shape is not known ahead of time — a figure
/// inside a card, a sheet that is saving. Skeletons are for the large content
/// areas where the shape *is* known: a list, a stat grid, a detail page.
/// Reaching for one where a spinner would do adds motion without adding
/// information.
///
/// No shimmer package for this. The effect is a gradient slid across the
/// block by one controller, which is a few lines here and one less dependency
/// to keep current.
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 6,
  });

  /// Null means "as wide as the parent allows". A fixed width is for the
  /// places a real line would not fill the row — a label above a value.
  final double? width;
  final double height;
  final double radius;

  /// A circle, for where an avatar will be.
  factory Skeleton.circle({Key? key, double size = 40}) =>
      Skeleton(key: key, width: size, height: size, radius: size / 2);

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  /// A moving highlight is exactly the kind of repeating motion someone turns
  /// animations off to avoid, and a loading placeholder is on screen for as
  /// long as the network takes.
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (still == _still && _controller.isAnimating != still) return;
    _still = still;

    // Stopping matters as much as not painting. A controller left repeating
    // schedules a frame every tick even when nothing reads it, so a list of
    // these would keep the whole app rendering at 60fps to animate something
    // deliberately held still.
    if (still) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final still = _still;

    final base = bos.isDark ? bos.bgHover : bos.borderLight;
    final highlight = bos.isDark ? bos.border : bos.bgSubtle;

    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
      child: SizedBox(width: widget.width, height: widget.height),
    );

    if (still) return box;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // Slide a soft band from off the left edge to off the right, so the
        // block never starts or ends mid-highlight.
        final t = _controller.value * 2 - 1;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment(t - 0.4, 0),
            end: Alignment(t + 0.4, 0),
            colors: [base, highlight, base],
          ).createShader(rect),
          child: box,
        );
      },
    );
  }
}

/// A stack of [Skeleton] rows shaped like the card lists this app uses —
/// a title line, a shorter subtitle, and an optional leading avatar.
///
/// Rows are deliberately not all the same width. Uniform bars read as a
/// progress element rather than as text, and the eye stops treating them as
/// "content arriving".
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.rows = 5,
    this.hasLeading = true,
    this.padding = const EdgeInsets.all(16),
  });

  final int rows;
  final bool hasLeading;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    // Cycled rather than random: a rebuild must not reshuffle the widths, or
    // the placeholder twitches every time the parent repaints.
    const widths = [0.55, 0.42, 0.62, 0.38, 0.5];

    return Column(
      children: [
        for (var i = 0; i < rows; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: bos.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: bos.border),
            ),
            padding: padding,
            child: Row(
              children: [
                if (hasLeading) ...[
                  Skeleton.circle(size: 40),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: widths[i % widths.length],
                        child: const Skeleton(height: 13),
                      ),
                      const SizedBox(height: 8),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: widths[(i + 2) % widths.length] * 0.8,
                        child: const Skeleton(height: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
