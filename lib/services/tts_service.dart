// Free TTS via the Edge read-aloud endpoint (no key needed).
// Falls back to gTTS if the endpoint is unreachable.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class TtsVoice {
  const TtsVoice(this.id, this.label);
  final String id;
  final String label;
}

const List<TtsVoice> burmeseVoices = [
  TtsVoice('my-MM-NilarNeural', 'Nilar (မိန်းကလေး)'),
  TtsVoice('my-MM-ThihaNeural', 'Thiha (ယောက်ျားလေး)'),
];

/// Result of a TTS synthesis.
class TtsResult {
  TtsResult(this.path, this.speedBakedIn);
  final String path;

  /// True when the TTS engine already applied [speed] (Edge prosody).
  /// False for the gTTS fallback (always 1.0x) — engine must atempo.
  final bool speedBakedIn;
}

class TtsService {
  static const _edgeWs =
      'wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1';
  static const _tokenUrl =
      'https://edge.microsoft.com/';

  /// Synthesize [text] with [voiceId] at [speed] (e.g. 1.3) into an MP3 file.
  Future<TtsResult> synthesize({
    required String text,
    required String voiceId,
    required double speed,
    required String outName,
  }) async {
    final dir = await getTemporaryDirectory();
    final outPath = '${dir.path}/$outName.mp3';
    try {
      await _edgeTts(text, voiceId, speed, outPath);
      return TtsResult(outPath, true);
    } catch (_) {
      await _gttsFallback(text, speed, outPath);
      return TtsResult(outPath, false);
    }
  }

  String _ssml(String text, String voiceId, double speed) {
    // Edge prosody rate: "+30%" style. Clamp to Edge limits (-50%..+100%).
    final pct = ((speed - 1.0) * 100).round().clamp(-50, 100);
    final rate = pct >= 0 ? '+$pct%' : '$pct%';
    final esc = const HtmlEscape().convert(text);
    return "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='my-MM'>"
        "<voice name='$voiceId'><prosody rate='$rate'>$esc</prosody></voice></speak>";
  }

  Future<void> _edgeTts(
      String text, String voiceId, double speed, String outPath) async {
    // NOTE: implemented over plain HTTPS POST is not supported by Edge;
    // we use the WebSocket protocol via dart:io WebSocket.
    final token = await _edgeToken();
    final ws = await WebSocket.connect(
      '$_edgeWs?TrustedClientToken=$token&ConnectionId=${_connId()}',
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Origin': 'https://www.bing.com',
      },
    );
    final reqId = _connId().replaceAll('-', '');
    final ssml = _ssml(text, voiceId, speed);
    final out = File(outPath).openWrite();
    try {
      ws.add('X-Timestamp:${_ts()}\r\n'
          'Content-Type:application/json; charset=utf-8\r\n'
          'Path:speech.config\r\n\r\n'
          '{"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},"outputFormat":"audio-24khz-96kbitrate-mono-mp3"}}}}');
      ws.add('X-RequestId:$reqId\r\n'
          'Content-Type:application/ssml+xml\r\n'
          'X-Timestamp:${_ts()}\r\n'
          'Path:ssml\r\n\r\n$ssml');
      await for (final msg in ws) {
        if (msg is List<int>) {
          // Binary audio message: header then payload after \r\n\r\n
          final data = msg;
          final sep = _indexOf(data, [13, 10, 13, 10]);
          if (sep > 0 && data.length > sep + 4) {
            out.add(data.sublist(sep + 4));
          }
        } else if (msg is String && msg.contains('Path:turn.end')) {
          break;
        }
      }
    } finally {
      await out.close();
      await ws.close();
    }
    if (await File(outPath).length() < 1000) {
      throw const FormatException('empty edge audio');
    }
  }

  Future<String> _edgeToken() async {
    // The token endpoint returns a trusted client token in page JS; as a
    // lightweight approach we reuse the well-known static handshake.
    final r = await http
        .get(Uri.parse(_tokenUrl))
        .timeout(const Duration(seconds: 15));
    final m = RegExp(r'"token":"([^"]+)"').firstMatch(r.body);
    if (m != null) return m.group(1)!;
    // Fallback: endpoint also accepts requests with a generated UUID token
    // on many builds; otherwise we fall through to gTTS.
    throw const FormatException('no edge token');
  }

  Future<void> _gttsFallback(String text, double speed, String outPath) async {
    // gTTS: single voice, no speed control server-side. We download at 1.0x
    // and apply atempo in the render pipeline.
    final q = Uri.encodeQueryComponent(text);
    final uri = Uri.parse(
        'https://translate.google.com/translate_tts?ie=UTF-8&q=$q&tl=my&client=tw-ob');
    final r = await http.get(uri, headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    }).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200 || r.bodyBytes.length < 1000) {
      throw HttpException('gTTS failed: ${r.statusCode}');
    }
    await File(outPath).writeAsBytes(r.bodyBytes);
  }

  String _connId() {
    final r = Random();
    String h(int n) =>
        List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${h(8)}-${h(4)}-${h(4)}-${h(4)}-${h(12)}';
  }

  String _ts() => DateTime.now().toUtc().toIso8601String();

  int _indexOf(List<int> data, List<int> pattern) {
    outer:
    for (var i = 0; i <= data.length - pattern.length; i++) {
      for (var j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}
