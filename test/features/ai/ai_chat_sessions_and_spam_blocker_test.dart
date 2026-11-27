import 'package:flutter_test/flutter_test.dart';
import 'package:makaw/features/ai/presentation/pages/ai_chat_page.dart';
import 'package:makaw/features/browser/data/services/ad_blocker_service.dart';

void main() {
  group('AiAttachment model', () {
    test('serializes and deserializes file attachment', () {
      final att = AiAttachment(
        id: 'att-1',
        name: 'main.dart',
        type: AiAttachmentType.file,
        path: '/storage/emulated/0/Download/main.dart',
        textContent: 'void main() {}',
        sizeInBytes: 1024,
      );

      final json = att.toJson();
      final decoded = AiAttachment.fromJson(json);

      expect(decoded.id, 'att-1');
      expect(decoded.name, 'main.dart');
      expect(decoded.type, AiAttachmentType.file);
      expect(decoded.textContent, 'void main() {}');
      expect(decoded.formattedSize, '1.0 KB');
    });

    test('serializes and deserializes link attachment', () {
      final att = AiAttachment(
        id: 'att-2',
        name: 'example.com',
        type: AiAttachmentType.link,
        textContent: 'https://example.com/docs',
        sizeInBytes: 24,
      );

      final json = att.toJson();
      final decoded = AiAttachment.fromJson(json);

      expect(decoded.name, 'example.com');
      expect(decoded.type, AiAttachmentType.link);
      expect(decoded.textContent, 'https://example.com/docs');
    });
  });

  group('AiChatMessage model', () {
    test('serializes and deserializes chat message with attachments', () {
      final msg = AiChatMessage(
        id: 'msg-1',
        role: 'user',
        text: 'What is in this file?',
        attachments: [
          const AiAttachment(
            id: 'att-1',
            name: 'test.py',
            type: AiAttachmentType.file,
            sizeInBytes: 50,
          ),
        ],
      );

      final json = msg.toJson();
      final decoded = AiChatMessage.fromJson(json);

      expect(decoded.id, 'msg-1');
      expect(decoded.role, 'user');
      expect(decoded.text, 'What is in this file?');
      expect(decoded.attachments.length, 1);
      expect(decoded.attachments.first.name, 'test.py');
    });
  });

  group('AiChatSession model', () {
    test('serializes and deserializes chat session with history', () {
      final session = AiChatSession(
        id: 'sess-1',
        title: 'Flutter Architecture Chat',
        messages: [
          AiChatMessage(id: 'm1', role: 'user', text: 'Hello!'),
          AiChatMessage(id: 'm2', role: 'model', text: 'Hi! How can I help?'),
        ],
      );

      final json = session.toJson();
      final decoded = AiChatSession.fromJson(json);

      expect(decoded.id, 'sess-1');
      expect(decoded.title, 'Flutter Architecture Chat');
      expect(decoded.messages.length, 2);
      expect(decoded.messages.first.text, 'Hello!');
      expect(decoded.messages.last.text, 'Hi! How can I help?');
    });
  });

  group('Ad & Spam Redirect Blocker for o2tvseries and isatissalaam.cyou', () {
    test('AdBlockerService blocks isatissalaam.cyou', () {
      final adBlocker = AdBlockerService();
      expect(adBlocker.isBlocked('https://isatissalaam.cyou/redirect?id=123'), isTrue);
      expect(adBlocker.isBlocked('http://isatissalaam.cyou/'), isTrue);
    });

    test('AdBlockerService blocks rogue .cyou domain redirects', () {
      final adBlocker = AdBlockerService();
      expect(adBlocker.isBlocked('https://clicktracking.cyou/affiliate'), isTrue);
      expect(adBlocker.isBlocked('https://roguead.cyou'), isTrue);
      expect(adBlocker.isBlocked('https://ads.monetag.com/pop'), isTrue);
      expect(adBlocker.isBlocked('https://alwingulla.com/show'), isTrue);
    });

    test('AdBlockerService allows trusted platforms and search engines', () {
      final adBlocker = AdBlockerService();
      expect(adBlocker.isBlocked('https://google.com'), isFalse);
      expect(adBlocker.isBlocked('https://github.com/flutter/flutter'), isFalse);
      expect(adBlocker.isBlocked('https://o2tvseries4u.com/series/lowdown'), isFalse);
    });
  });
}
