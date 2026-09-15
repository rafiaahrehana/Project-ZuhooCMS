import 'package:flutter/material.dart';

import '../../core/theme/bos_tokens.dart';

/// The Zuhoo mark, as the web app draws it.
///
/// The three places that show it — the splash, the login screen and the
/// drawer header — all used to draw a generic grid glyph on a brand-coloured
/// square, which is a placeholder rather than a logo.
///
/// One asset, not a pair. The brand files all carry their background baked in
/// — the mark on near-white in one, on near-black in another — so the first
/// version of this picked between them by theme and rounded the corners off
/// to hide how square they were. The asset here has that background removed
/// instead: flood-filled from the edges, so the white *inside* the Z survives
/// while the white around the hexagon does not. Being genuinely transparent,
/// it sits on any surface, in either theme, with no plate behind it.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Image.asset(
      'assets/brand/logo-mark-transparent.png',
      height: size,
      width: size,
      fit: BoxFit.contain,
      // A missing asset must not take the whole screen down with it — the
      // splash and the login screen both draw this before anything else has
      // had a chance to go right.
      errorBuilder: (_, _, _) => Container(
        height: size,
        width: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bos.brand,
          borderRadius: BorderRadius.circular(size * 0.28),
        ),
        child: Icon(
          Icons.grid_view_rounded,
          color: Colors.white,
          size: size * 0.47,
        ),
      ),
    );
  }
}
