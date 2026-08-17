import 'package:flutter/material.dart';
import 'responsive.dart';

Future<T?> showAdaptiveModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useRootNavigator = false,
  String? barrierLabel,
  Color? barrierColor,
  double? maxHeight,
}) {
  if (Responsive.isDesktop(context)) {
    return showDialog<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      barrierLabel: barrierLabel,
      barrierColor: barrierColor ?? Colors.black54,
      builder: (ctx) {
        return Dialog(
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 550,
              maxHeight: maxHeight ?? MediaQuery.sizeOf(ctx).height * 0.75,
            ),
            child: builder(ctx),
          ),
        );
      },
    );
  }

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useRootNavigator: useRootNavigator,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final sheet = Container(
        constraints: BoxConstraints(
          maxHeight: maxHeight ?? MediaQuery.sizeOf(ctx).height * 0.85,
        ),
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: builder(ctx),
      );
      if (isScrollControlled) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: sheet,
        );
      }
      return sheet;
    },
  );
}

Future<T?> showAdaptiveConfirmation<T>({
  required BuildContext context,
  required String title,
  required String message,
  String confirmText = 'Confirm',
  String cancelText = 'Cancel',
  Color? confirmColor,
  IconData? icon,
}) {
  if (Responsive.isDesktop(context)) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: icon != null ? Icon(icon, size: 48, color: confirmColor) : null,
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(cancelText)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: confirmColor != null ? FilledButton.styleFrom(backgroundColor: confirmColor) : null,
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  return showModalBottomSheet<T>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 40, color: confirmColor),
              const SizedBox(height: 12),
            ],
            Text(title, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, style: Theme.of(ctx).textTheme.bodyMedium),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(cancelText),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: confirmColor != null ? FilledButton.styleFrom(backgroundColor: confirmColor) : null,
                    child: Text(confirmText),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
