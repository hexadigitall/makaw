import 'package:flutter/material.dart';
import 'responsive.dart';

class AdaptiveContainer extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final bool center;
  final Color? background;
  final EdgeInsetsGeometry? padding;
  final bool useCard;

  const AdaptiveContainer({
    super.key,
    required this.child,
    this.maxWidth,
    this.center = true,
    this.background,
    this.padding,
    this.useCard = false,
  });

  @override
  Widget build(BuildContext context) {
    final w = Responsive.width(context);
    final max = maxWidth ?? Responsive.contentMaxWidth(context);
    final isDesktop = Responsive.isDesktop(context);
    final pad = padding ?? Responsive.pagePadding(context);
    final bg = background ?? Theme.of(context).colorScheme.surface;

    if (w >= Responsive.tabletMax) {
      final content = Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: max),
          child: useCard
              ? Card(
                  elevation: 1,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(padding: pad, child: child),
                )
              : Padding(padding: pad, child: child),
        ),
      );
      if (isDesktop) {
        return Container(color: bg, child: content);
      }
      return content;
    }

    return Padding(padding: pad, child: child);
  }
}

class AdaptiveSplitView extends StatelessWidget {
  final Widget master;
  final Widget detail;
  final double masterFlex;
  final double detailFlex;

  const AdaptiveSplitView({
    super.key,
    required this.master,
    required this.detail,
    this.masterFlex = 1,
    this.detailFlex = 2,
  });

  @override
  Widget build(BuildContext context) {
    if (Responsive.isDesktop(context)) {
      return Row(
        children: [
          Expanded(flex: masterFlex.round(), child: master),
          const VerticalDivider(width: 1),
          Expanded(flex: detailFlex.round(), child: detail),
        ],
      );
    }
    return detail;
  }
}

class AdaptiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final double runSpacing;

  const AdaptiveGrid({
    super.key,
    required this.children,
    this.spacing = 12,
    this.runSpacing = 12,
  });

  @override
  Widget build(BuildContext context) {
    final columns = Responsive.gridColumns(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileW = (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: children.map((child) => SizedBox(width: tileW, child: child)).toList(),
        );
      },
    );
  }
}
