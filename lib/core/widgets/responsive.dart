import 'package:flutter/material.dart';

enum DeviceType { mobile, tablet, desktop }

class Responsive {
  static const double mobileMax = 600;
  static const double tabletMax = 900;
  static const double desktopMax = 1200;
  static const double wideDesktop = 1600;

  static DeviceType deviceType(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < mobileMax) return DeviceType.mobile;
    if (w < tabletMax) return DeviceType.tablet;
    return DeviceType.desktop;
  }

  static double width(BuildContext context) => MediaQuery.sizeOf(context).width;
  static double height(BuildContext context) => MediaQuery.sizeOf(context).height;

  static bool isMobile(BuildContext context) => deviceType(context) == DeviceType.mobile;
  static bool isTablet(BuildContext context) => deviceType(context) == DeviceType.tablet;
  static bool isDesktop(BuildContext context) => deviceType(context) == DeviceType.desktop;
  static bool isWideDesktop(BuildContext context) => width(context) >= wideDesktop;

  static bool isLandscape(BuildContext context) =>
      MediaQuery.orientationOf(context) == Orientation.landscape;

  static bool isRTL(BuildContext context) =>
      Directionality.of(context) == TextDirection.rtl;

  static int gridColumns(BuildContext context) {
    final w = width(context);
    if (w < mobileMax) return 1;
    if (w < tabletMax) return 2;
    if (w < desktopMax) return 3;
    if (w < wideDesktop) return 4;
    return 5;
  }

  static double tileWidth(BuildContext context, {int columns = 0, double spacing = 12}) {
    final cols = columns > 0 ? columns : gridColumns(context);
    final w = width(context);
    final padding = isMobile(context) ? 16.0 : 32.0;
    return (w - padding * 2 - spacing * (cols - 1)) / cols;
  }

  static double contentMaxWidth(BuildContext context) {
    final w = width(context);
    if (w < tabletMax) return w;
    if (w < wideDesktop) return desktopMax;
    return wideDesktop;
  }

  static EdgeInsets pagePadding(BuildContext context) {
    if (isMobile(context)) return const EdgeInsets.all(12);
    if (isTablet(context)) return const EdgeInsets.all(20);
    return const EdgeInsets.symmetric(horizontal: 32, vertical: 24);
  }

  static double iconSize(BuildContext context) {
    if (isMobile(context)) return 24;
    if (isTablet(context)) return 26;
    return 28;
  }

  static double fontSize(BuildContext context, {double base = 14}) {
    if (isMobile(context)) return base;
    if (isTablet(context)) return base + 1;
    return base + 2;
  }
}
