import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';

/// The one Tawazzn mark used on launch and on the welcome screen.
///
/// R2 #20/#24 + owner note: the app used to show the logo three times in
/// three different styles (white native launch, an animated splash with a
/// square and green arcs, then the welcome circle). Now the native launch
/// image (ios LaunchImage / android launch_mark, rendered from this same
/// recipe), the routing splash and the welcome screen all draw this mark:
/// a 136pt tonal ring, a 120pt white disc with a soft shadow, the logo
/// clipped round. Change it here and re-render the native images.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key});

  static const double ring = 136;
  static const double disc = 120;

  @override
  Widget build(BuildContext context) {
    final wash = AppColors.of(context).accentWash;
    return SizedBox(
      width: ring,
      height: ring,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: Container(
              width: ring,
              height: ring,
              decoration: BoxDecoration(color: wash, shape: BoxShape.circle),
            ),
          ),
          Container(
            width: disc,
            height: disc,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/branding/tawazzn_icon.png',
                width: disc,
                height: disc,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
