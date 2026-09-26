import 'dart:convert';
import 'dart:io';

/// All sinks (file, console, UI and exports) use the same redaction boundary.
String redactDiagnostic(String value) {
  var text = value.replaceAllMapped(
    RegExp(r'(?:https?|wss?|rtmp)://[^\s<>"\x27]+', caseSensitive: false),
    (match) {
      final uri = Uri.tryParse(match[0]!);
      if (uri == null) return '[URL]';
      // Paths may contain account IDs and signed stream keys as well as queries.
      return '${uri.scheme}://${uri.host}/[REDACTED]';
    },
  );
  text = text.replaceAllMapped(
    RegExp(
      r'''["']?(?:cookie|set-cookie|authorization|proxy-authorization)["']?\s*[:=]\s*[^\r\n]+''',
      caseSensitive: false,
    ),
    (_) => '[REDACTED HEADER]',
  );
  text = text.replaceAllMapped(
    RegExp(
      r'''(["']?(?:[\w-]*(?:token|secret|password|passwd|cookie)|signature|sign|x-bogus|dedeuserid|acf_uid|ttwid|buvid3|sessdata|bili_jct|acf_auth|access_key|api_key|credential|uid|user_id|userid|username|user_name|uname|nickname|nick|account|email|phone|device_id|uuid)["']?\s*[:=]\s*)(?:"[^"\r\n]*"|'[^'\r\n]*'|[^\s,;}\r\n]+)''',
      caseSensitive: false,
    ),
    (match) => '${match[1]}[REDACTED]',
  );
  text = text.replaceAll(
    RegExp(r'Bearer\s+[^\s,;"\x27}]+', caseSensitive: false),
    'Bearer [REDACTED]',
  );
  // Do not expose the OS account in stack traces and file paths.
  text = text.replaceAll(
    RegExp(r'[A-Z]:\\Users\\[^\\\r\n]+', caseSensitive: false),
    r'C:\Users\[USER]',
  );
  text = text.replaceAll(RegExp(r'/(?:home|Users)/[^/\r\n]+'), '/home/[USER]');
  return text;
}

/// Serialized writes also queue logs emitted before directory initialization.
/// Each process owns a locked session marker; cleanup skips all active sessions.
class DiagnosticWriter {
  DiagnosticWriter(
    Future<Directory> directory, {
    this.maxFileBytes = 2 * 1024 * 1024,
    this.maxSegments = 5,
    this.retention = const Duration(days: 14),
    this.maxTotalBytes = 50 * 1024 * 1024,
  }) {
    _queue = _initialize(directory);
  }

  final int maxFileBytes;
  final int maxSegments;
  final Duration retention;
  final int maxTotalBytes;
  final String session =
      '${DateTime.now().toUtc().microsecondsSinceEpoch}-$pid';
  late Future<void> _queue;
  Directory? directory;
  RandomAccessFile? _marker;
  RandomAccessFile? _file;
  int _bytes = 0;
  int _segment = 0;
  int _pending = 0;
  bool _closed = false;
  String? failure;

  Future<void> _initialize(Future<Directory> target) async {
    try {
      directory = await target;
      await directory!.create(recursive: true);
      _marker = await File('${directory!.path}/$session.active')
          .open(mode: FileMode.write);
      // Non-blocking lock permits other processes to probe active sessions.
      await _marker!.lock(FileLock.exclusive);
      await _openSegment();
      await clean();
    } catch (error) {
      failure = redactDiagnostic(error.toString());
    }
  }

  Future<void> _openSegment() async {
    _file = await File('${directory!.path}/$session.$_segment.log')
        .open(mode: FileMode.write);
    _bytes = 0;
  }

  void write(String text) {
    if (_closed) return;
    if (_pending >= 2000) {
      failure = 'Diagnostic queue overflow: some messages were dropped.';
      return;
    }
    _pending++;
    var safe = redactDiagnostic(text);
    if (safe.length > 32000) safe = '${safe.substring(0, 32000)} [TRUNCATED]';
    final bytes = utf8.encode('$safe\r\n');
    _queue = _queue.then((_) async {
      try {
        if (_file == null) return;
        if (_bytes + bytes.length > maxFileBytes) {
          await _file!.close();
          _segment++;
          await _openSegment();
          final old = _segment - maxSegments;
          if (old >= 0) {
            final expired = File('${directory!.path}/$session.$old.log');
            if (await expired.exists()) await expired.delete();
          }
        }
        await _file!.writeFrom(bytes);
        _bytes += bytes.length;
      } catch (error) {
        failure = redactDiagnostic(error.toString());
      } finally {
        _pending--;
      }
    });
  }

  Future<void> flush() async {
    await _queue;
    try {
      await _file?.flush();
    } catch (error) {
      failure = redactDiagnostic(error.toString());
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await flush();
    try {
      await _file?.close();
      await _marker?.close();
      if (directory != null) {
        final marker = File('${directory!.path}/$session.active');
        if (await marker.exists()) await marker.delete();
      }
    } catch (error) {
      failure = redactDiagnostic(error.toString());
    }
  }

  Future<bool> _active(String name) async {
    if (name.split('.').first == session && !_closed) return true;
    final marker = File('${directory!.path}/${name.split('.').first}.active');
    if (!await marker.exists()) return false;
    RandomAccessFile? probe;
    try {
      probe = await marker.open(mode: FileMode.append);
      await probe.lock(FileLock.exclusive);
      return false;
    } on FileSystemException {
      return true;
    } finally {
      await probe?.close();
    }
  }

  Future<List<File>> files() async {
    if (directory == null) return [];
    return directory!
        .list()
        .where((entry) => entry is File && entry.path.endsWith('.log'))
        .cast<File>()
        .toList();
  }

  /// clearAll applies only to inactive files, including logs from other windows.
  Future<int> clean({bool clearAll = false}) async {
    if (directory == null) return 0;
    final logs = await files();
    logs.sort((a, b) => a.path.compareTo(b.path));
    var total = 0;
    for (final file in logs) {
      total += await file.length();
    }
    var removed = 0;
    final cutoff = DateTime.now().subtract(retention);
    for (final file in logs) {
      try {
        if (await _active(file.uri.pathSegments.last)) continue;
        final stat = await file.stat();
        if (clearAll ||
            stat.modified.isBefore(cutoff) ||
            total > maxTotalBytes) {
          await file.delete();
          total -= stat.size;
          removed++;
        }
      } on FileSystemException {
        /* Another window may already have cleaned it. */
      }
    }
    // Remove abandoned markers after their logs have expired.
    await for (final entry in directory!.list()) {
      if (entry is! File || !entry.path.endsWith('.active')) continue;
      final name = entry.uri.pathSegments.last;
      if (!await _active(name) &&
          (clearAll || (await entry.lastModified()).isBefore(cutoff))) {
        try {
          await entry.delete();
        } on FileSystemException {
          /* Concurrent cleanup. */
        }
      }
    }
    return removed;
  }
}
