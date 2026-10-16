import 'package:flutter/material.dart';

/// Brand ink, the splash and adaptive-icon background.
const kBrandInk = Color(0xFF101C30);

/// Shown while the app starts up (database opening), laid out exactly like
/// the native splash — the "Open Ring" mark centred, the wordmark near the
/// bottom — so launch flows from the system splash straight into the app
/// instead of flashing a white screen with a spinner.
class BrandSplash extends StatelessWidget {
  const BrandSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: kBrandInk,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The native splash draws the 1152px mark canvas at 288dp; the
          // mark itself fills 1024/1152 of it.
          Image(
            image: AssetImage('assets/images/logo_mark.png'),
            width: 256,
            height: 256,
          ),
          Positioned(
            bottom: 48,
            child: Image(
              image: AssetImage('assets/images/wordmark.png'),
              width: 200,
              height: 50,
            ),
          ),
        ],
      ),
    );
  }
}
