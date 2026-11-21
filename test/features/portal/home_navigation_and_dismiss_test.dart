import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makaw/features/portal/domain/home_activity.dart';
import 'package:makaw/features/portal/presentation/pages/makaw_home_portal_page.dart';
import 'package:makaw/features/history/data/history_service.dart';

void main() {
  group('HomeActivityItem tests', () {
    test('creates item with id, callbacks and properties', () {
      bool dismissed = false;
      bool tapped = false;
      final item = HomeActivityItem(
        id: 'test_item_1',
        title: 'Test Title',
        subtitle: 'Test Subtitle',
        icon: Icons.language,
        accent: Colors.blue,
        onTap: () => tapped = true,
        onDismiss: () => dismissed = true,
      );

      expect(item.id, equals('test_item_1'));
      expect(item.title, equals('Test Title'));
      expect(item.subtitle, equals('Test Subtitle'));
      expect(item.icon, equals(Icons.language));
      expect(item.accent, equals(Colors.blue));

      item.onTap();
      expect(tapped, isTrue);

      item.onDismiss?.call();
      expect(dismissed, isTrue);
    });
  });

  group('HistoryService version notifier tests', () {
    test('historyVersion notifier updates when notified', () {
      final initialVersion = HistoryService.historyVersion.value;
      HistoryService.historyVersion.value++;
      expect(HistoryService.historyVersion.value, equals(initialVersion + 1));
    });
  });

  group('MakawHomePortalPage UI dismiss and clear tests', () {
    testWidgets('renders Dismissible and close button for items', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool clearedContinue = false;
      bool clearedRecent = false;
      bool dismissedItem = false;

      final testItem = HomeActivityItem(
        id: 'continue_1',
        title: 'Makaw Web Page',
        subtitle: 'Continue browsing',
        icon: Icons.public,
        accent: Colors.cyan,
        onTap: () {},
        onDismiss: () => dismissedItem = true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MakawHomePortalPage(
            onNavigate: (_) {},
            onOpenEcosystem: (_) {},
            onOpenQrScanner: () {},
            onToggleIncognito: () {},
            onOpenAiAssistant: () {},
            onOpenSearch: () {},
            onNewTab: () {},
            continueItems: [testItem],
            recentItems: [testItem],
            onClearContinue: () => clearedContinue = true,
            onClearRecent: () => clearedRecent = true,
            onDismissItem: (_) => dismissedItem = true,
          ),
        ),
      );

      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('Makaw Web Page'), findsWidgets);

      // Verify Dismissible exists
      expect(find.byType(Dismissible), findsWidgets);

      // Verify 'Clear' buttons exist on the section headers
      final clearButtons = find.text('Clear');
      expect(clearButtons, findsWidgets);

      // Tap clear continue button
      await tester.tap(clearButtons.first);
      await tester.pump();
      expect(clearedContinue, isTrue);

      // Tap clear recent button
      await tester.tap(clearButtons.last);
      await tester.pump();
      expect(clearedRecent, isTrue);

      // Test item dismissal
      testItem.onDismiss?.call();
      expect(dismissedItem, isTrue);
    });
  });
}
