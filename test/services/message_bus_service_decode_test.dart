import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/message_bus_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('decodeMessageBusMessages preserves order on sync path', () async {
    final chunk = jsonEncode([
      {
        'channel': '/topic/1',
        'message_id': 10,
        'data': {'type': 'created', 'id': 100},
      },
      {
        'channel': '/topic/1',
        'message_id': 11,
        'data': {'type': 'liked', 'id': 100},
      },
    ]);

    final messages = await decodeMessageBusMessages(
      chunk,
      isolateDecodeThreshold: chunk.length + 1,
    );

    expect(messages.map((message) => message.messageId), [10, 11]);
  });

  test(
    'decodeMessageBusMessages matches sync path when forced to isolate',
    () async {
      final chunk = jsonEncode([
        {
          'channel': '/topic/2',
          'message_id': 20,
          'data': {'type': 'revised', 'id': 200},
        },
        {
          'channel': '/__status',
          'message_id': 21,
          'data': {'/topic/2': 20},
        },
      ]);

      final messages = await decodeMessageBusMessages(
        chunk,
        isolateDecodeThreshold: 0,
      );

      expect(messages.map((message) => message.channel), [
        '/topic/2',
        '/__status',
      ]);
      expect(messages.map((message) => message.messageId), [20, 21]);
    },
  );
}
