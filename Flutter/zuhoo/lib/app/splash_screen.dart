import 'package:flutter/material.dart';

import '../core/theme/bos_tokens.dart';
import '../shared/widgets/brand_mark.dart';

/// Shown only while the stored session is being read back.
///
/// This is a fraction of a second on a warm start, but it is the difference
/// between opening straight into the dashboard and watching the login screen
/// appear and then vanish.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return Scaffold(
      backgroundColor: bos.bgPage,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 66),
            const SizedBox(height: 18),
            Text(
              'Zuhoo',
              style: TextStyle(
                color: bos.text,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: bos.brand),
            ),
          ],
        ),
      ),
    );
  }
}
