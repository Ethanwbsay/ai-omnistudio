import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

// Image gateways may send whitespace heartbeats before the final JSON and keep
// the connection alive afterwards. Consume the complete JSON document instead
// of waiting for an EOF that can be delayed or replaced by a connection reset.
Future<http.Response> readImageResponse(http.StreamedResponse response,
    {int expectedCount = 1, void Function(int)? onBytes}) async {
  if ((response.headers['content-type'] ?? '')
      .toLowerCase()
      .contains('text/event-stream')) {
    return _readImageEvents(response, expectedCount, onBytes);
  }
  final done = Completer<http.Response>();
  final bytes = BytesBuilder(copy: false);
  StreamSubscription<List<int>>? subscription;
  var started = false;
  var quoted = false;
  var escaped = false;
  var depth = 0;
  var scanJson = true;

  http.Response result() =>
      http.Response.bytes(bytes.toBytes(), response.statusCode,
          headers: response.headers,
          request: response.request,
          reasonPhrase: response.reasonPhrase);

  void stop() {
    final active = subscription;
    if (active != null) unawaited(active.cancel().catchError((Object _) {}));
  }

  subscription = response.stream.listen((chunk) {
    if (done.isCompleted) return;
    bytes.add(chunk);
    onBytes?.call(bytes.length);
    if (!scanJson) return;
    for (final byte in chunk) {
      if (!started) {
        if (byte == 32 || byte == 9 || byte == 10 || byte == 13) continue;
        if (byte != 123 && byte != 91) {
          scanJson = false;
          break;
        }
        started = true;
      }
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (byte == 92) {
          escaped = true;
        } else if (byte == 34) {
          quoted = false;
        }
      } else if (byte == 34) {
        quoted = true;
      } else if (byte == 123 || byte == 91) {
        depth++;
      } else if (byte == 125 || byte == 93) {
        depth--;
        if (depth == 0) {
          // Never salvage incomplete JSON or accept a partial Base64 payload.
          try {
            final parsed = jsonDecode(utf8.decode(bytes.toBytes()));
            if (parsed is Map || parsed is List) {
              done.complete(result());
              stop();
              return;
            }
          } catch (_) {
            scanJson = false;
          }
          break;
        }
      }
    }
  }, onError: (Object error, StackTrace stack) {
    if (!done.isCompleted) done.completeError(error, stack);
    stop();
  }, onDone: () {
    if (!done.isCompleted) done.complete(result());
  });
  try {
    return await done.future;
  } finally {
    stop();
  }
}

class ImageStreamException implements Exception {
  const ImageStreamException(this.message);
  final String message;
}

// Only completed Images events are final outputs. Comments, progress and
// partial previews keep the connection active but must never be saved as works.
Future<http.Response> _readImageEvents(http.StreamedResponse response,
    int expectedCount, void Function(int)? onBytes) async {
  final done = Completer<http.Response>();
  final images = <Map<String, dynamic>>[];
  final data = <String>[];
  var event = '';
  var received = 0;
  var skippedEvents = 0;
  var invalidEvents = 0;
  String? lastInvalidFinal;
  StreamSubscription<String>? subscription;

  void stop() {
    final active = subscription;
    if (active != null) unawaited(active.cancel().catchError((Object _) {}));
  }

  void fail(String message) {
    if (done.isCompleted) return;
    done.completeError(ImageStreamException(message));
    stop();
  }

  void finish() {
    if (done.isCompleted) return;
    if (images.length < expectedCount) {
      if (lastInvalidFinal != null) {
        fail(lastInvalidFinal!);
        return;
      }
      fail('仅收到 ${images.length}/$expectedCount 张最终图片'
          '（HTTP ${response.statusCode}，已接收 $received 字节，'
          '跳过 $skippedEvents 个非图片事件、$invalidEvents 个无法解析事件）');
      return;
    }
    done.complete(http.Response(
        jsonEncode({'data': images}), response.statusCode,
        headers: {...response.headers, 'content-type': 'application/json'},
        request: response.request,
        reasonPhrase: response.reasonPhrase));
    stop();
  }

  void dispatch() {
    if (done.isCompleted) return;
    if (data.isEmpty) {
      event = '';
      return;
    }
    final payload = data.join('\n');
    data.clear();
    final name = event;
    event = '';
    if (payload.trim().isEmpty) {
      skippedEvents++;
      return;
    }
    if (payload.trim() == '[DONE]') {
      finish();
      return;
    }
    final isFinal =
        name == 'image_edit.completed' || name == 'image_generation.completed';
    final isError = name == 'error' || name == 'response.failed';
    // SSE data is arbitrary text, not necessarily JSON. Ignore explicitly
    // named progress/keepalive events before attempting to decode their data.
    if (name.isNotEmpty && !isFinal && !isError) {
      skippedEvents++;
      return;
    }
    dynamic decoded;
    String? decodedPayload;
    // Preserve JSON whitespace and prompt strings. Only normalize physical
    // line breaks inside an explicitly identified Base64 image field.
    final candidates = <String>[
      payload,
      _normalizeImageBase64Lines(payload),
    ];
    int? parseOffset;
    for (final candidate in candidates) {
      try {
        decoded = jsonDecode(candidate);
        decodedPayload = candidate;
        break;
      } on FormatException catch (e) {
        parseOffset ??= e.offset;
        // Try the next representation; only report an error after all safe
        // normalization forms have failed.
      }
    }
    if (decodedPayload == null) {
      if (isFinal || isError) {
        final kind = isError ? '错误事件' : '最终图片事件';
        lastInvalidFinal = '$kind内容不是完整 JSON'
            '（HTTP ${response.statusCode}，已接收 $received 字节，'
            '事件 ${payload.length} 字符，错误位置 ${parseOffset ?? -1}，'
            '数据行 ${payload.split('\n').length}）';
        // Retain a possibly split final event until another data fragment,
        // terminal marker, a new event or EOF arrives. Never save incomplete
        // Base64 and never resubmit the paid generation request.
        data.add(payload);
        event = name;
      } else {
        // Unnamed text heartbeats and unrecognized frames must not close a
        // paid request before a later valid completed image can arrive.
        invalidEvents++;
      }
      return;
    }
    if (decoded is! Map) {
      if (isFinal || isError) {
        fail('最终图片或错误事件格式无法识别');
      } else {
        skippedEvents++;
      }
      return;
    }
    lastInvalidFinal = null;
    final type = decoded['type'] ?? name;
    if (isError ||
        type == 'error' ||
        type == 'response.failed' ||
        decoded['error'] != null) {
      final error = decoded['error'];
      final message =
          (error is Map ? error['message'] : error) ?? decoded['message'];
      final reason = message?.toString() ?? '服务商返回错误事件';
      fail(reason.length > 180 ? reason.substring(0, 180) : reason);
      return;
    }
    // Some gateways envelope a completed Images response in an unnamed SSE
    // message. Accept only explicit image result fields, never preview fields.
    if (name.isEmpty && decoded['type'] == null && decoded['data'] is List) {
      final results = decoded['data'] as List;
      for (final item in results) {
        if (item is! Map ||
            !((item['b64_json'] is String &&
                    (item['b64_json'] as String).isNotEmpty) ||
                (item['url'] is String &&
                    (item['url'] as String).isNotEmpty))) {
          fail('图片结果事件包含无效图片');
          return;
        }
        images.add(Map<String, dynamic>.from(item));
      }
      if (images.length >= expectedCount) finish();
      return;
    }
    if (type != 'image_edit.completed' &&
        type != 'image_generation.completed') {
      skippedEvents++;
      return;
    }
    if ((decoded['b64_json'] is! String ||
            (decoded['b64_json'] as String).isEmpty) &&
        (decoded['url'] is! String || (decoded['url'] as String).isEmpty)) {
      fail('完成事件未包含图片');
      return;
    }
    images.add(Map<String, dynamic>.from(decoded));
    if (images.length >= expectedCount) finish();
  }

  subscription = response.stream
      .map((chunk) {
        received += chunk.length;
        onBytes?.call(received);
        return chunk;
      })
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        if (done.isCompleted) return;
        if (line.isEmpty) {
          dispatch();
          return;
        }
        if (line.startsWith(':')) return;
        final colon = line.indexOf(':');
        final field = colon < 0 ? line : line.substring(0, colon);
        var value = colon < 0 ? '' : line.substring(colon + 1);
        if (value.startsWith(' ')) value = value.substring(1);
        if (field == 'event') {
          // A new explicitly named event cannot be part of an earlier broken
          // frame. Discard its fragments, retaining only the safe diagnostic.
          data.clear();
          event = value;
        }
        if (field == 'data') {
          if (value.trim() == '[DONE]') {
            finish();
            return;
          }
          data.add(value);
        }
        if (!['event', 'data', 'id', 'retry'].contains(field) &&
            (event == 'image_edit.completed' ||
                event == 'image_generation.completed' ||
                event == 'error' ||
                event == 'response.failed') &&
            line.isNotEmpty &&
            data.isNotEmpty) {
          // Non-standard continuation lines emitted by some SSE proxies.
          data.add(line);
        }
      }, onError: (Object error, StackTrace stack) {
        if (!done.isCompleted) done.completeError(error, stack);
        stop();
      }, onDone: () {
        // Accept a complete final JSON document even when a gateway omits the
        // trailing SSE blank line. Incomplete JSON still fails on EOF.
        if (!done.isCompleted && data.isNotEmpty) dispatch();
        finish();
      });
  try {
    return await done.future;
  } finally {
    stop();
  }
}

String _normalizeImageBase64Lines(String payload) =>
    payload.replaceAllMapped(RegExp(r'"(b64_json|url)"\s*:\s*"([^"\\]*)"'),
        (match) {
      final value = match[2]!;
      if (!value.contains('\n') && !value.contains('\r')) return match[0]!;
      final start =
          value.startsWith('data:image/') ? value.indexOf(',') + 1 : 0;
      if (match[1] == 'url' && start == 0) return match[0]!;
      final encoded = value.substring(start);
      if (!RegExp(r'^[A-Za-z0-9+/=\r\n]+$').hasMatch(encoded)) return match[0]!;
      return match[0]!.replaceAll(RegExp(r'[\r\n]+'), '');
    });
