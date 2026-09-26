import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Direct SDK execution intentionally does not require a package resolution.
// ignore: avoid_relative_lib_imports
import '../../lib/services/storage/desktop_shared_store.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

class CountedStore extends DesktopSharedStore {
  CountedStore(super.directory);
  int reads = 0;
  Completer<void>? pauseRefresh;
  Completer<void>? enteredRefresh;

  @override
  Future<void> refresh() async {
    reads++;
    enteredRefresh?.complete();
    enteredRefresh = null;
    await pauseRefresh?.future;
    await super.refresh();
  }
}

Future<void> until(bool Function() condition, String message,
    {Duration timeout = const Duration(seconds: 2)}) async {
  final clock = Stopwatch()..start();
  while (!condition()) {
    if (clock.elapsed >= timeout) throw StateError(message);
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

// Publish fixtures as a real external writer: readers must never observe the
// truncate/write gap and mistake an unfinished fixture for corrupt storage.
Future<void> writeFixture(Directory directory, String contents,
    {DateTime? modified}) async {
  final process = await Process.start(Platform.resolvedExecutable,
      [Platform.script.toFilePath(), '--write-fixture', directory.path]);
  final output = process.stdout.transform(utf8.decoder).join();
  final errors = process.stderr.transform(utf8.decoder).join();
  process.stdin.write(jsonEncode({
    'contents': contents,
    'modified': modified?.microsecondsSinceEpoch,
  }));
  await process.stdin.close();
  final code = await process.exitCode;
  final diagnostic = '${await output}${await errors}';
  check(code == 0, 'External fixture writer failed ($code): $diagnostic');
}

Future<void> writeFixtureChild(String path) async {
  final input = jsonDecode(await stdin.transform(utf8.decoder).join()) as Map;
  final lock = await File('$path/state.lock').open(mode: FileMode.append);
  var locked = false;
  try {
    await lock.lock(FileLock.blockingExclusive);
    locked = true;
    final file = File('$path/state.json');
    await file.writeAsString(input['contents'] as String, flush: true);
    if (input['modified'] != null) {
      await file.setLastModified(
          DateTime.fromMicrosecondsSinceEpoch(input['modified'] as int));
    }
  } finally {
    try {
      if (locked) await lock.unlock();
    } finally {
      await lock.close();
    }
  }
}

Future<void> main(List<String> args) async {
  if (args.length == 2 && args.first == '--write-fixture') {
    await writeFixtureChild(args[1]);
    return;
  }
  final directory = await Directory.systemTemp.createTemp('shared-poll-check-');
  final stores = <CountedStore>[];
  final errors = <Object>[];
  try {
    final writer = CountedStore(directory);
    stores.add(writer);
    await writer.initialize(() async => {
          'settings': {'value': 'a', 'payload': 'x' * 1000000}
        });
    final readers = List.generate(3, (_) => CountedStore(directory));
    stores.addAll(readers);
    for (final reader in readers) {
      await reader.initialize(() async => throw StateError('Unexpected seed'));
      reader.startPolling(onError: (error, _) => errors.add(error));
    }
    final clock = Stopwatch()..start();
    await Future<void>.delayed(const Duration(milliseconds: 3400));
    final idleReads = readers.fold(0, (n, store) => n + store.reads);
    check(readers.every((reader) => reader.reads <= 2) && idleReads > 0,
        'Idle polling performed unnecessary locked reads: $idleReads');
    final legacyReads = clock.elapsedMilliseconds ~/ 300 * readers.length;
    stdout.writeln('Idle 3 windows, 1 MB snapshot, '
        '${clock.elapsedMilliseconds} ms: $idleReads full reads; '
        'previous 300 ms polling would schedule $legacyReads full reads');

    final changed = Stopwatch()..start();
    await writer.mutate('settings', (values) => values['value'] = 'b');
    await until(() => readers.every((r) => r.box('settings')['value'] == 'b'),
        'Ordinary external write was not synchronized',
        timeout: const Duration(seconds: 4));
    stdout.writeln('External transactional write synchronized to all windows '
        'in ${changed.elapsedMilliseconds} ms');

    // Simulate a replacement that preserves every metadata field we compare.
    final file = File('${directory.path}/state.json');
    final original = await file.stat();
    final snapshot = jsonDecode(await file.readAsString()) as Map;
    snapshot['revision'] = (snapshot['revision'] as int) + 1;
    (snapshot['boxes']['settings'] as Map)['value'] = 'c';
    final replacement = jsonEncode(snapshot);
    check(utf8.encode(replacement).length == original.size,
        'Fixture changed snapshot size');
    await writeFixture(directory, replacement, modified: original.modified);
    final replaced = await file.stat();
    check(
        replaced.size == original.size &&
            replaced.modified == original.modified &&
            replaced.type == original.type,
        'Fixture did not preserve polling metadata');
    final fallback = Stopwatch()..start();
    // Process startup can consume part of the forced-check interval. Metadata
    // equality was verified above; only eventual synchronization is required.
    await until(() => readers.every((r) => r.box('settings')['value'] == 'c'),
        'Same-size/same-mtime replacement was never found',
        timeout: const Duration(seconds: 6));
    stdout.writeln('Same-size/same-mtime replacement found by forced check '
        'in ${fallback.elapsedMilliseconds} ms');

    // Explicit refresh does not use the metadata fast path.
    final beforeExplicit = readers.first.reads;
    await readers.first.refresh();
    check(readers.first.reads == beforeExplicit + 1,
        'Explicit refresh was not forced');

    // Closing during a full read waits for that read and leaves no active timer.
    final closingReader = readers.first;
    final enteredRefresh = Completer<void>();
    closingReader.enteredRefresh = enteredRefresh;
    closingReader.pauseRefresh = Completer<void>();
    await writer.mutate('settings', (values) => values['value'] = 'd');
    await enteredRefresh.future.timeout(const Duration(seconds: 4));
    var closed = false;
    final close = closingReader.close().then((_) => closed = true);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    check(!closed, 'Close returned before an in-flight read completed');
    closingReader.pauseRefresh!.complete();
    await close;
    final readsAfterClose = closingReader.reads;
    closingReader.startPolling(onError: (error, _) => errors.add(error));
    await writer.mutate('settings', (values) => values['value'] = 'e');
    await Future<void>.delayed(const Duration(milliseconds: 650));
    check(closingReader.reads == readsAfterClose,
        'Closed window retained/restarted a polling timer');

    // Wait for the pre-corruption state, rather than assuming 650 ms is enough
    // on every file system. Otherwise an old 'd' would falsely signal recovery.
    final activeReaders = readers.skip(1).toList();
    await until(
        () => activeReaders.every((r) => r.box('settings')['value'] == 'e'),
        'Active readers did not reach the pre-corruption snapshot',
        timeout: const Duration(seconds: 6));

    // Corruption still uses the same locked recovery path and preserves evidence.
    await writeFixture(directory, '{broken');
    await until(
        () => activeReaders.every((r) => r.box('settings')['value'] == 'd'),
        'Polling did not recover the backup',
        timeout: const Duration(seconds: 6));
    check(await directory.list().any((f) => f.path.contains('.corrupt.')),
        'Polling recovery did not preserve the corrupt file');
    check(errors.isEmpty, 'Unexpected polling errors: $errors');
    final futureSnapshot =
        jsonEncode({'schema': 99, 'revision': 99, 'boxes': {}});
    await writeFixture(directory, futureSnapshot);
    await until(() => errors.isNotEmpty,
        'Polling silently swallowed an unsupported schema',
        timeout: const Duration(seconds: 4));
    check(errors.every((error) => error is UnsupportedError),
        'Polling reported the wrong storage error: $errors');
    check(await file.readAsString() == futureSnapshot,
        'Polling overwrote an unsupported schema with the old backup');
    stdout.writeln('PASS: idle reads; ordinary/same-metadata synchronization; '
        'forced refresh; in-flight close; no retained timer; backup recovery; '
        'unsupported schema error propagation');
  } finally {
    for (final store in stores) {
      final paused = store.pauseRefresh;
      if (paused != null && !paused.isCompleted) paused.complete();
      await store.close();
    }
    await directory.delete(recursive: true);
  }
}
