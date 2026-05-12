import 'dart:async';
import 'dart:io';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Mock proxy server that intercepts session-replay uploads from the
/// native SDK and persists each captured frame to disk.
///
/// Wiring: set [CXExporterOptions.proxyUrl] to this server's address
/// (the SDK is already wired to proxy uploads through `proxyUrl` —
/// confirmed in CxFlutterPlugin.swift:719 and FlutterPluginManager.kt:152).
/// The SDK appends a `cx_forward` query param with the original URL.
///
/// Per the SDK's wire format (SRNetworkManager.swift):
///   - multipart/form-data
///   - field `metadata`: JSON blob with timestamp/sessionId/segmentIndex/etc.
///   - field `chunk`: raw JPEG bytes (`Content-Type: image/jpeg`)
///
/// We persist each pair as `frame_<seq>.jpg` + `meta_<seq>.json`. The
/// scanner phase OCRs every frame and asserts no sentinel substring.
///
/// We respond 200 to everything so the SDK keeps trying — we are a
/// terminal mock, not a real proxy that forwards to Coralogix.
class MockUploadServer {
  HttpServer? _server;
  int _seq = 0;
  late final Directory _dir;
  final List<String> _frames = <String>[];

  /// Where to bind. Use 0.0.0.0 so both the iOS simulator (which sees
  /// the host as 127.0.0.1) and the Android emulator (which sees the
  /// host as 10.0.2.2) can reach it.
  static const String bindAddress = '0.0.0.0';

  /// Returns the URL string a Flutter app should put in
  /// `CXExporterOptions.proxyUrl`. Differs per platform target.
  static String proxyUrlForCurrentPlatform(int port) {
    if (Platform.isAndroid) return 'http://10.0.2.2:$port';
    return 'http://127.0.0.1:$port';
  }

  Directory get framesDir => _dir;
  List<String> get capturedFrames => List.unmodifiable(_frames);
  int get port => _server!.port;

  Future<void> start({int port = 0}) async {
    _dir = await Directory.systemTemp.createTemp('cx_leak_harness_');
    _server = await shelf_io.serve(_handle, bindAddress, port);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// Clear captured frames between scenarios. Files on disk are kept
  /// so a leaked sentinel can still be inspected after the test run;
  /// only the in-memory list is reset.
  void resetCounter() {
    _frames.clear();
  }

  Future<Response> _handle(Request req) async {
    // Log every request — diagnostic to confirm proxyUrl wiring works.
    final cxFwd = req.url.queryParameters['cx_forward'] ?? '';
    // ignore: avoid_print
    print(
        '[mock-upload] ${req.method} /${req.url.path} cx_forward=$cxFwd ctype=${req.headers['content-type'] ?? ''}');

    if (req.method != 'POST') return Response.ok('');

    final isSessionReplay = _looksLikeSessionReplay(req);
    if (!isSessionReplay) {
      // Drain and ignore: logs, traces, and any other proxied traffic.
      await req.read().drain<void>();
      return Response.ok('');
    }

    try {
      await _persistMultipart(req);
      // ignore: avoid_print
      print(
          '[mock-upload] persisted frame #${_seq - 1} → ${_frames.isNotEmpty ? _frames.last : "(no chunk?)"}');
    } catch (e, st) {
      // Don't fail the SDK upload — the harness will surface this via
      // a missing-frames assertion if persistence is broken.
      // ignore: avoid_print
      print('[mock-upload] persist failed: $e\n$st');
    }
    return Response.ok('');
  }

  bool _looksLikeSessionReplay(Request req) {
    // Session-replay uploads on both iOS and Android are multipart/form-data
    // POSTs with `metadata` + `chunk` fields. Logs and traces are
    // application/json. Content-type is the cheapest reliable signal —
    // path differs by platform (iOS includes `?cx_forward=...` with the
    // sessionrecording path, Android proxies to `/` without `cx_forward`).
    final ctype = req.headers['content-type'] ?? '';
    return ctype.startsWith('multipart/form-data');
  }

  Future<void> _persistMultipart(Request req) async {
    final contentType = req.headers['content-type'] ?? '';
    final boundary = _extractBoundary(contentType);
    if (boundary == null) {
      throw StateError('No multipart boundary in: $contentType');
    }

    final transformer = MimeMultipartTransformer(boundary);
    // shelf returns Stream<Uint8List>; MimeMultipartTransformer wants
    // Stream<List<int>>. .cast<List<int>>() reconciles the types.
    final parts =
        await req.read().cast<List<int>>().transform(transformer).toList();

    String? metaJson;
    List<int>? jpegBytes;

    for (final part in parts) {
      final disposition = part.headers['content-disposition'] ?? '';
      final name = _extractFieldName(disposition);
      final bytes = await _collect(part);
      if (name == 'metadata') {
        metaJson = String.fromCharCodes(bytes);
      } else if (name == 'chunk') {
        jpegBytes = bytes;
      }
    }

    if (jpegBytes == null) return;

    // The SDK gzip-compresses the JPEG bytes before uploading
    // (SessionReplayModel.swift:494, data.gzipCompressed()). Detect via
    // magic bytes 1f 8b and inflate.
    final decoded = _maybeInflate(jpegBytes);

    final seq = _seq++;
    final framePath = p.join(_dir.path, 'frame_${_pad(seq)}.jpg');
    await File(framePath).writeAsBytes(decoded);
    _frames.add(framePath);

    if (metaJson != null) {
      final metaPath = p.join(_dir.path, 'meta_${_pad(seq)}.json');
      await File(metaPath).writeAsString(metaJson);
    }
  }

  List<int> _maybeInflate(List<int> bytes) {
    if (bytes.length < 3) return bytes;
    final isGzip = bytes[0] == 0x1f && bytes[1] == 0x8b && bytes[2] == 0x08;
    if (!isGzip) return bytes;
    return gzip.decode(bytes);
  }

  Future<List<int>> _collect(Stream<List<int>> s) async {
    final out = <int>[];
    await for (final chunk in s) {
      out.addAll(chunk);
    }
    return out;
  }

  String? _extractBoundary(String contentType) {
    final m = RegExp(r'boundary=([^;]+)').firstMatch(contentType);
    if (m == null) return null;
    var b = m.group(1)!.trim();
    if (b.startsWith('"') && b.endsWith('"')) {
      b = b.substring(1, b.length - 1);
    }
    return b;
  }

  String? _extractFieldName(String disposition) {
    final m = RegExp(r'name="([^"]+)"').firstMatch(disposition);
    return m?.group(1);
  }

  String _pad(int n) => n.toString().padLeft(6, '0');
}

/// Standalone entry — run as a host-side process:
///
///   dart run example/integration_test/leak_harness/mock_upload_server.dart [port]
///
/// Prints two machine-parseable lines on startup:
///
///   CX_MOCK_PORT=<port>
///   CX_MOCK_DIR=<absolute_path>
///
/// …and runs forever until killed (SIGTERM/SIGINT). The wrapper script
/// `tool/run_leak_harness.sh` greps the port out and passes it into
/// `flutter test --dart-define=CX_MOCK_PORT=...`. App's `proxyUrl` is
/// then constructed in the test using that port + the per-platform
/// host alias (10.0.2.2 on Android emulator, 127.0.0.1 elsewhere).
Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? int.parse(args.first) : 0;
  final server = MockUploadServer();
  await server.start(port: port);
  // ignore: avoid_print
  print('CX_MOCK_PORT=${server.port}');
  // ignore: avoid_print
  print('CX_MOCK_DIR=${server.framesDir.path}');
  // ignore: avoid_print
  print('[mock-upload] ready');

  ProcessSignal.sigterm.watch().listen((_) async {
    await server.stop();
    exit(0);
  });
  ProcessSignal.sigint.watch().listen((_) async {
    await server.stop();
    exit(0);
  });

  await Completer<void>().future;
}

