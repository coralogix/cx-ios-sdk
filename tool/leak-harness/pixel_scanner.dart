import 'dart:io';

import 'package:path/path.dart' as p;

/// Default location of the Swift pixel counter: same directory as this
/// scanner script. Lets the harness be self-contained — no cwd or
/// sibling-repo path assumptions.
String _defaultScriptPath() {
  // Platform.script is the URI of the entry-point Dart file, which is
  // this scanner when run via `dart run pixel_scanner.dart`.
  final scriptDir = p.dirname(Platform.script.toFilePath());
  return p.join(scriptDir, 'count_magenta.swift');
}

/// One frame's leak signal.
class FrameLeak {
  final String frame;
  final int magentaPixelCount;
  const FrameLeak(this.frame, this.magentaPixelCount);
}

/// Scans every `frame_*.jpg` in [dir] for magenta sentinel pixels.
/// Returns the list of frames where the count is non-zero, sorted by
/// count descending (worst leaks first).
///
/// Shells out to `tool/count_magenta.swift`. The script prints one
/// integer per invocation: number of matching pixels. Any non-zero
/// count means the SDK's mask rect missed part of a sentinel — i.e.
/// the frame-skew bug leaked text.
///
/// A single leaked character renders ~30+ matching pixels. The scanner
/// applies a small noise floor (`> 0` by default) — bump it to 5 if we
/// observe single-pixel false positives from JPEG quantisation around
/// other colors.
Future<List<FrameLeak>> scanForLeaks(
  Directory dir, {
  String swiftBinary = 'swift',
  String? scriptPath,
  int noiseFloor = 0,
}) async {
  final resolvedScriptPath = scriptPath ?? _defaultScriptPath();
  if (!await dir.exists()) {
    throw ArgumentError('Frames directory does not exist: ${dir.path}');
  }

  final frames = await dir
      .list()
      .where((e) => e is File && e.path.endsWith('.jpg'))
      .cast<File>()
      .toList();
  frames.sort((a, b) => a.path.compareTo(b.path));

  final leaks = <FrameLeak>[];
  var skipped = 0;
  for (final frame in frames) {
    final result = await Process.run(
      swiftBinary,
      [resolvedScriptPath, frame.path],
      stdoutEncoding: systemEncoding,
      stderrEncoding: systemEncoding,
    );
    if (result.exitCode != 0) {
      throw StateError(
        'count_magenta failed on ${frame.path}: ${result.stderr}',
      );
    }
    final out = (result.stdout as String).trim();
    if (out == 'SKIP') {
      skipped++;
      continue;
    }
    final count = int.parse(out);
    if (count > noiseFloor) {
      leaks.add(FrameLeak(frame.path, count));
    }
  }
  if (skipped > 0) {
    // ignore: avoid_print
    print('[leak-check] skipped $skipped non-image file(s) '
        '(likely multi-chunk fragments; harness does not yet reassemble)');
  }
  leaks.sort((a, b) => b.magentaPixelCount.compareTo(a.magentaPixelCount));
  return leaks;
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: pixel_scanner.dart <frames_dir>');
    exit(2);
  }
  final dir = Directory(args.first);
  final leaks = await scanForLeaks(dir);
  if (leaks.isEmpty) {
    stdout.writeln('[leak-check] OK — 0 leaks in ${dir.path}');
    exit(0);
  }
  stdout.writeln(
      '[leak-check] FAIL — ${leaks.length} frame(s) with magenta pixels:');
  for (final leak in leaks) {
    stdout.writeln('  ${leak.frame}  ${leak.magentaPixelCount} px');
  }
  exit(1);
}
