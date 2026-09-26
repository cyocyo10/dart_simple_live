// Standalone: dart run test/diagnostics/diagnostic_writer_check.dart
import 'dart:convert';
import 'dart:io';

import '../../lib/app/diagnostics/diagnostic_writer.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args[0] == '--child') {
    final writer = DiagnosticWriter(Future.value(Directory(args[1])));
    writer.write('active child log');
    await writer.flush();
    stdout.writeln('ready');
    await stdin.first;
    await writer.close();
    return;
  }
  final root = await Directory.systemTemp.createTemp(
    'simple-live-diagnostic-check-',
  );
  try {
    final delayed = Future<Directory>.delayed(
      const Duration(milliseconds: 30),
      () => root,
    );
    final writer = DiagnosticWriter(delayed, maxFileBytes: 200, maxSegments: 3);
    writer.write('early line: Cookie: TEST_COOKIE');
    await writer.flush();
    final early = await (await writer.files()).single.readAsString();
    check(early.contains('early line'), 'early initialization logs were lost');
    check(!early.contains('TEST_COOKIE'), 'cookie was leaked');
    for (var i = 0; i < 20; i++) {
      writer.write('entry-$i ${'x' * 120}');
    }
    await writer.flush();
    check((await writer.files()).length == 3, 'rotation limit failed');
    check(await writer.clean(clearAll: true) == 0, 'deleted current session');

    final child = await Process.start(Platform.resolvedExecutable, [
      Platform.script.toFilePath(),
      '--child',
      root.path,
    ]);
    await child.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    check(
      await writer.clean(clearAll: true) == 0,
      'deleted another active process',
    );
    check((await writer.files()).length == 4, 'active child file missing');
    child.stdin.writeln('close');
    await child.stdin.close();
    check(await child.exitCode == 0, 'child failed');
    check(
      await writer.clean(clearAll: true) == 1,
      'inactive child not cleaned',
    );
    await writer.close();
    final cleaner = DiagnosticWriter(Future.value(root));
    await cleaner.flush();
    check(
      await cleaner.clean(clearAll: true) == 3,
      'closed session not cleaned',
    );
    await cleaner.close();

    final retentionDir = await Directory('${root.path}/retention').create();
    final expired = File('${retentionDir.path}/old.log');
    await expired.writeAsString('expired');
    await expired.setLastModified(
      DateTime.now().subtract(const Duration(days: 30)),
    );
    final oversized = File('${retentionDir.path}/inactive.log');
    await oversized.writeAsString('x' * 100);
    final retentionWriter = DiagnosticWriter(
      Future.value(retentionDir),
      maxTotalBytes: 50,
    );
    await retentionWriter.flush();
    check(!await expired.exists(), 'expired log retained');
    check(!await oversized.exists(), 'storage cap failed');
    await retentionWriter.close();
    final unavailable = DiagnosticWriter(
      Future<Directory>.error(FileSystemException('unavailable')),
    );
    unavailable.write('early error');
    await unavailable.flush();
    check(unavailable.failure != null, 'initialization failure not reported');
    await unavailable.close();

    final secrets = [
      'Cookie: TEST_A; SESSDATA=TEST_B',
      'authorization: Bearer TEST_C',
      '{"access_token":"TEST_D", "username":"TEST_E"}',
      'https://example.org/TEST_PATH?key=TEST_QUERY',
      'C:\\Users\\TEST_USER\\logs',
      '/home/TEST_UNIX/logs',
      'acf_auth=TEST_F; bili_jct=TEST_G',
    ];
    for (final text in secrets) {
      check(
        !redactDiagnostic(text).contains('TEST_'),
        'redaction failed: ${redactDiagnostic(text)}',
      );
    }
    stdout.writeln(
      'PASS: initialization queue, redaction, rotation, active-process cleanup, retention, capacity and initialization-failure handling',
    );
  } finally {
    await root.delete(recursive: true);
  }
}
