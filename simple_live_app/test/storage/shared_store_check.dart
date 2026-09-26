import 'dart:convert';
import 'dart:io';
import '../../lib/services/storage/desktop_shared_store.dart';
import '../../lib/services/storage/app_box.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main(List<String> args) async {
  if (args.isNotEmpty) {
    final store = DesktopSharedStore(Directory(args[0]));
    await store
        .initialize(() async => throw StateError('A child tried to reseed'));
    for (var n = 0; n < 25; n++) {
      await store.mutate('settings', (values) {
        values['${args[1]}-$n'] = n;
        values['counter'] = (values['counter'] as int? ?? 0) + 1;
      });
    }
    await store.close();
    return;
  }
  final dir = await Directory.systemTemp.createTemp('alllive-shared-check-');
  final first = DesktopSharedStore(dir);
  final second = DesktopSharedStore(dir);
  try {
    var seeds = 0;
    await Future.wait([
      first.initialize(() async {
        seeds++;
        return {
          'settings': {'seed': true}
        };
      }),
      second.initialize(() async {
        seeds++;
        return {};
      })
    ]);
    check(seeds == 1, 'Initialization must seed exactly once');
    final observed = <Set<String>>[];
    final subscription = second.changes.listen(observed.add);
    final children = await Future.wait(List.generate(
        3,
        (i) => Process.start(
              Platform.resolvedExecutable,
              [
                '--packages=${Platform.script.resolve('../../.dart_tool/package_config.json').toFilePath()}',
                Platform.script.toFilePath(),
                dir.path,
                '$i'
              ],
            )));
    final results = await Future.wait(children.map((p) async {
      final out = p.stdout.transform(utf8.decoder).join();
      final err = p.stderr.transform(utf8.decoder).join();
      final code = await p.exitCode;
      return '$code|${await out}|${await err}';
    }));
    check(results.every((r) => r == '0||'), 'Child processes failed: $results');
    await second.refresh();
    check(
        second.box('settings')['counter'] == 75, 'Concurrent writes were lost');
    check(
        second.box('settings').length == 77, 'Unrelated keys were overwritten');
    await Future<void>.delayed(Duration.zero);
    check(observed.any((s) => s.contains('settings')),
        'Remote change was not broadcast');

    final settings =
        AppBox<dynamic>.shared(first, 'localstorage', (v) => v, (v) => v);
    final visibleSizes = <dynamic>[];
    final pendingObserver = first.changes.listen((names) {
      if (names.contains('localstorage'))
        visibleSizes.add(settings.get('size'));
    });
    await Future.wait(List.generate(20, (i) => settings.put('size', i)));
    await Future<void>.delayed(Duration.zero);
    check(visibleSizes.isNotEmpty && visibleSizes.every((v) => v == 19),
        'An older commit rewound the latest slider value: $visibleSizes');
    await pendingObserver.cancel();

    final historyA = AppBox<Map<String, dynamic>>.shared(
        first, 'history', (v) => v, (v) => Map<String, dynamic>.from(v));
    final historyB = AppBox<Map<String, dynamic>>.shared(
        second, 'history', (v) => v, (v) => Map<String, dynamic>.from(v));
    await historyA.put('room', {'updateTime': '2026-09-26T12:00:00Z'});
    await historyB.put('room', {'updateTime': '2026-09-25T12:00:00Z'});
    check(historyB.get('room')!['updateTime'] == '2026-09-26T12:00:00Z',
        'Older visit replaced newer one');
    await historyA.replaceAll({
      'other': {'updateTime': '2026-09-26T12:00:00Z'}
    });
    await second.refresh();
    check(!historyB.containsKey('room') && historyB.containsKey('other'),
        'Replace was not atomic/shared');
    await historyB.clear();
    await first.refresh();
    check(historyA.isEmpty, 'Clear did not reach other window');

    var failedFlush = false;
    try {
      await second.mutate('settings', (v) {
        v['invalid'] = double.nan;
      });
    } catch (_) {}
    try {
      await second.flush();
    } catch (_) {
      failedFlush = true;
    }
    check(failedFlush, 'Flush must report an unsuccessful queued write');
    await second.mutate('settings', (v) {
      v['valid'] = true;
    });
    await second.flush();

    // An independent room continues after the original/main window closes.
    await first.close();
    await second.mutate('settings', (v) {
      v['afterMainClose'] = true;
    });
    final reopened = DesktopSharedStore(dir);
    await reopened.initialize(() async => throw StateError('Unexpected seed'));
    check(reopened.box('settings')['afterMainClose'] == true,
        'Data was not durable');
    await reopened.close();
    await subscription.cancel();
    await second.close();

    final backup =
        jsonDecode(await File('${dir.path}/state.backup.json').readAsString());
    await File('${dir.path}/state.json').writeAsString('{broken');
    final recovered = DesktopSharedStore(dir);
    await recovered
        .initialize(() async => throw StateError('Must recover backup'));
    check(recovered.revision == backup['revision'], 'Backup recovery failed');
    await recovered.close();
    check(await dir.list().any((f) => f.path.contains('.corrupt.')),
        'Damaged snapshot was not preserved');
    final futureSnapshot =
        jsonEncode({'schema': 99, 'revision': 100, 'boxes': {}});
    await File('${dir.path}/state.json').writeAsString(futureSnapshot);
    var unsupported = false;
    try {
      await DesktopSharedStore(dir).initialize(() async => {});
    } on UnsupportedError {
      unsupported = true;
    }
    check(unsupported, 'Future schema must not be downgraded to an old backup');
    check(await File('${dir.path}/state.json').readAsString() == futureSnapshot,
        'Future schema was overwritten');
    await File('${dir.path}/state.json').writeAsString('{broken');
    await File('${dir.path}/state.backup.json').writeAsString('{broken');
    var refused = false;
    try {
      await DesktopSharedStore(dir).initialize(() async => {});
    } on StateError {
      refused = true;
    }
    check(refused, 'Unreadable storage must never silently reset user data');
    stdout.writeln(
        'PASS: 3 processes/75 writes; one-time migration; notifications; newest history; replace/clear; parent exit; durability; backup recovery; corruption refusal');
  } finally {
    await dir.delete(recursive: true);
  }
}
