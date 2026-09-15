import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_controller.dart';
import '../core/theme/bos_tokens.dart';

/// Pins a strip to the top for as long as the read-only demo is running.
///
/// The same slot the impersonation banner uses, and for the same reason: both
/// mark a session that is not an ordinary sign-in, and both have to survive
/// navigation, so they live above the router rather than inside a screen.
///
/// Worth stating plainly, because nothing else in the app does: a demo session
/// looks exactly like a normal one. The account is an ordinary company owner,
/// the token is an ordinary token, and every screen renders as it always does.
/// The only difference is that the backend refuses the writes — so without
/// this strip, the first sign that anything is different would be a save
/// failing for no visible reason.
class DemoScope extends ConsumerWidget {
  const DemoScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDemo = ref.watch(demoSessionProvider);
    if (!isDemo) return child;

    return Material(
      color: Theme.of(context).bos.bgPage,
      child: Column(
        children: [
          const _Banner(),
          Expanded(
            // The strip has taken the status-bar inset; without this the
            // Scaffold below insets for it a second time and leaves a dead
            // band under the bar.
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends ConsumerStatefulWidget {
  const _Banner();

  @override
  ConsumerState<_Banner> createState() => _BannerState();
}

class _BannerState extends ConsumerState<_Banner> {
  bool _leaving = false;

  Future<void> _exit() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    try {
      // Plain sign-out. There is no account to hand back to the way ending an
      // impersonation has — the demo *is* the session.
      await ref.read(authControllerProvider.notifier).logout();
    } finally {
      if (mounted) setState(() => _leaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    // The soft token fills, the solid one draws on it — the pair is the unit,
    // and MessageBanner uses it the same way. Filling with the solid instead
    // looked right in light mode, where `info` is a deep teal, and turned the
    // strip into the brightest thing on a dark screen, because in dark mode
    // the solid tokens are inks meant for text rather than fills.
    final background = bos.infoSoft;
    final foreground = bos.info;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: background,
        border: Border(
          bottom: BorderSide(color: foreground.withValues(alpha: 0.3)),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
          child: Row(
            children: [
              Icon(Icons.visibility_rounded, size: 17, color: foreground),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Demo — everything is real, nothing is saved.',
                  style: TextStyle(
                    color: foreground,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: _leaving ? null : _exit,
                style: TextButton.styleFrom(
                  foregroundColor: foreground,
                  minimumSize: const Size(48, 40),
                ),
                child: Text(_leaving ? 'Leaving...' : 'Exit'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
