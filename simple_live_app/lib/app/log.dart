import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simple_live_app/app/diagnostics/diagnostic_writer.dart';

class Log {
  static LogFileWriter? logFileWriter;
  static bool detailed = !kReleaseMode;
  static bool _shuttingDown = false;
  static final RxList<DebugLogModel> debugLogs = <DebugLogModel>[].obs;

  /// Call once after WidgetsFlutterBinding initialization, in every window.
  static Future<void> initialize({bool detailed = false}) async {
    _shuttingDown = false;
    Log.detailed = detailed;
    logFileWriter ??= LogFileWriter();
    await logFileWriter!.flush();
  }

  /// Compatibility for callers that used this to enable detailed logging.
  static void initWriter() {
    if (_shuttingDown) return;
    detailed = true;
    logFileWriter ??= LogFileWriter();
  }

  static void setDetailed(bool enabled) {
    if (_shuttingDown) return;
    if (detailed == enabled && logFileWriter != null) return;
    detailed = enabled;
    logFileWriter ??= LogFileWriter();
    writeLog('Detailed logging: $enabled', Level.warning);
  }

  static Future<void> disposeWriter() async {
    final writer = logFileWriter;
    logFileWriter = null;
    await writer?.close();
  }

  static Future<void> shutdown() async {
    _shuttingDown = true;
    // Timeout does not cancel close; freeze every lazy writer creation path so
    // late callbacks cannot reopen a file while the old writer drains.
    await disposeWriter().timeout(const Duration(milliseconds: 500),
        onTimeout: () {
      w('日志关闭超过500ms，继续退出（用户数据已保存）', false);
    });
  }

  static void resume() => _shuttingDown = false;
  static Future<void> flush() async => await logFileWriter?.flush();

  static void writeLog(dynamic content, [Level level = Level.info]) {
    if (_shuttingDown) return;
    // Warnings and errors remain available in release without verbose traffic.
    if (!detailed &&
        level != Level.warning &&
        level != Level.error &&
        level != Level.fatal) return;
    logFileWriter ??= LogFileWriter();
    logFileWriter!.write(
      '[${level.name.toUpperCase()}] ${DateTime.now().toIso8601String()} $content',
    );
  }

  static void addDebugLog(String content, Color? color) {
    debugLogs.insert(
      0,
      DebugLogModel(DateTime.now(), redactDiagnostic(content), color: color),
    );
    if (debugLogs.length > 500) debugLogs.removeRange(500, debugLogs.length);
  }

  static final Logger logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.none,
    ),
  );

  static void d(String message, [bool writeFile = true]) {
    if (!detailed) return;
    final safe = redactDiagnostic(message);
    addDebugLog(safe, Colors.orange);
    if (kDebugMode) logger.d(safe);
    if (writeFile) writeLog(safe, Level.debug);
  }

  static void i(String message, [bool writeFile = true]) {
    if (!detailed) return;
    final safe = redactDiagnostic(message);
    addDebugLog(safe, Colors.blue);
    if (kDebugMode) logger.i(safe);
    if (writeFile) writeLog(safe, Level.info);
  }

  static void e(
    Object message,
    StackTrace stackTrace, [
    bool writeFile = true,
  ]) {
    final safe = redactDiagnostic('$message\n$stackTrace');
    addDebugLog(safe, Colors.red);
    if (kDebugMode) logger.e(safe);
    if (writeFile) writeLog(safe, Level.error);
  }

  static void w(String message, [bool writeFile = true]) {
    final safe = redactDiagnostic(message);
    addDebugLog(safe, Colors.pink);
    if (kDebugMode) logger.w(safe);
    if (writeFile) writeLog(safe, Level.warning);
  }

  static void logPrint(dynamic obj, [bool writeFile = true]) {
    if (obj is Error) {
      e(obj.toString(), obj.stackTrace ?? StackTrace.current, writeFile);
    } else if (obj is Exception) {
      e(obj.toString(), StackTrace.current, writeFile);
    } else {
      i(obj.toString(), writeFile);
    }
  }

  static Future<Directory> logDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/log');
  }

  static Future<List<File>> logFiles() async {
    if (_shuttingDown) return [];
    logFileWriter ??= LogFileWriter();
    await flush();
    return logFileWriter!.writer.files();
  }

  static Future<int> cleanLogs() async {
    await flush();
    return await logFileWriter?.writer.clean(clearAll: true) ?? 0;
  }

  /// Exports only sanitized logs and non-identifying runtime metadata.
  static Future<File> exportDiagnostics() async {
    final archive = Archive();
    archive.addFile(
      ArchiveFile.string(
        'diagnostics.json',
        jsonEncode({
          'createdUtc': DateTime.now().toUtc().toIso8601String(),
          'platform': Platform.operatingSystem,
          'osVersion': redactDiagnostic(Platform.operatingSystemVersion),
          'locale': Platform.localeName,
          'detailedLogging': detailed,
          'writerFailure': logFileWriter?.writer.failure,
        }),
      ),
    );
    var exportedBytes = 0;
    final files = await logFiles();
    files.sort((a, b) => b.path.compareTo(a.path));
    for (final file in files) {
      try {
        final size = await file.length();
        if (size > 2 * 1024 * 1024 + 128000 ||
            exportedBytes + size > 20 * 1024 * 1024) continue;
        final content = redactDiagnostic(
          utf8.decode(await file.readAsBytes(), allowMalformed: true),
        );
        exportedBytes += size;
        archive.addFile(
          ArchiveFile.string('logs/${file.uri.pathSegments.last}', content),
        );
      } on FileSystemException {
        /* Concurrent rotation: skip the removed segment. */
      }
    }
    final memory = debugLogs
        .map((item) => '${item.datetime.toIso8601String()} ${item.content}')
        .join('\n');
    archive.addFile(
      ArchiveFile.string('current-window.log', redactDiagnostic(memory)),
    );
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/simple-live-diagnostics-${DateTime.now().microsecondsSinceEpoch}.zip',
    );
    await file.writeAsBytes(ZipEncoder().encode(archive), flush: true);
    return file;
  }
}

class LogFileWriter {
  LogFileWriter() : writer = DiagnosticWriter(Log.logDirectory()) {
    write(
      'Session: ${writer.session}; Platform: ${Platform.operatingSystem}; Locale: ${Platform.localeName}',
    );
  }
  final DiagnosticWriter writer;
  String get fileName => '${writer.session}.log';
  void write(String content) => writer.write(content);
  Future<void> flush() => writer.flush();
  Future<void> close() => writer.close();
}

class DebugLogModel {
  final String content;
  final DateTime datetime;
  final Color? color;
  DebugLogModel(this.datetime, this.content, {this.color});
}
