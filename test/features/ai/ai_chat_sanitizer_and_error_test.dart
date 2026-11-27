import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makaw/features/ai/presentation/pages/ai_chat_page.dart';

void main() {
  group('AiChatPage.cleanApiKey', () {
    test('returns clean key unchanged', () {
      const raw = 'AIzaSyD-1234567890abcdefghijklmnopqrst';
      expect(AiChatPage.cleanApiKey(raw), raw);
    });

    test('strips leading and trailing whitespace', () {
      const raw = '   AIzaSyD-1234567890abcdefghijklmnopqrst \n\t ';
      expect(AiChatPage.cleanApiKey(raw), 'AIzaSyD-1234567890abcdefghijklmnopqrst');
    });

    test('strips surrounding double quotes', () {
      const raw = '"AIzaSyD-1234567890abcdefghijklmnopqrst"';
      expect(AiChatPage.cleanApiKey(raw), 'AIzaSyD-1234567890abcdefghijklmnopqrst');
    });

    test('strips surrounding single quotes', () {
      const raw = "'AIzaSyD-1234567890abcdefghijklmnopqrst'";
      expect(AiChatPage.cleanApiKey(raw), 'AIzaSyD-1234567890abcdefghijklmnopqrst');
    });

    test('strips export prefix and variable assignments', () {
      const raw = 'export GEMINI_API_KEY="AIzaSyD-1234567890abcdefghijklmnopqrst"';
      expect(AiChatPage.cleanApiKey(raw), 'AIzaSyD-1234567890abcdefghijklmnopqrst');
    });

    test('strips variable assignment without export', () {
      const raw = 'GEMINI_API_KEY=AIzaSyD-1234567890abcdefghijklmnopqrst';
      expect(AiChatPage.cleanApiKey(raw), 'AIzaSyD-1234567890abcdefghijklmnopqrst');
    });
  });

  group('AiChatPage model configuration', () {
    testWidgets('renders AiChatPage with initialModel gemini-3.8-flash', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AiChatPage(
            apiKey: 'AIzaSyFakeKeyForTest',
            initialModel: 'gemini-3.8-flash',
          ),
        ),
      );

      expect(find.text('AI Assistant'), findsOneWidget);
      expect(find.text('gemini-3.8-flash'), findsOneWidget);
    });
  });
}
