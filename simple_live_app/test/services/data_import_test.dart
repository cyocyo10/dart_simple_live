import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/services/data_import.dart';
import 'package:simple_live_app/services/storage/app_box.dart';
import 'package:simple_live_app/services/storage/desktop_shared_store.dart';

Map<String, dynamic> follow(String room) => {
      'id': 'huya_$room',
      'roomId': room,
      'siteId': 'huya',
      'userName': null,
      'face': null,
      'addTime': '2026-01-01T12:00:00Z',
    };

Map<String, dynamic> history(String room, String time) => {
      ...follow(room),
      'updateTime': time,
    };

class DelayedBox<T> implements AppBox<T> {
  final committed = Completer<void>();
  bool called = false;
  @override
  Future<void> putAll(Map<dynamic, T> entries) {
    called = true;
    return committed.future;
  }

  @override
  Future<void> replaceAll(Map<dynamic, T> entries) => putAll(entries);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory directory;
  late DesktopSharedStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('data-import-');
    store = DesktopSharedStore(directory);
    await store.initialize(() async => {});
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test('bad final favorite never clears an existing overlay target', () async {
    final box = AppBox<FollowUser>.shared(
      store,
      'followuser',
      (value) => value.toJson(),
      (value) => FollowUser.fromJson(Map<String, dynamic>.from(value)),
    );
    await box.putAll(DataImport.decodeFollowUsers([follow('old')]));
    final previousRevision = store.revision;
    Future<void> receive() async {
      final entries = DataImport.decodeFollowUsers([
        follow('new'),
        {...follow('bad'), 'id': 'douyu_bad'},
      ]);
      await DataImport.apply(box, entries, overlay: true);
    }

    await expectLater(receive(), throwsFormatException);
    expect(store.revision, previousRevision);
    expect(box.toMap().keys, ['huya_old']);
  });

  test('bad final history and tag are rejected before any replacement', () {
    expect(
      () => DataImport.decodeHistory([
        history('one', '2026-01-01T12:00:00Z'),
        history('two', 'not-a-date'),
      ]),
      throwsFormatException,
    );
    expect(
      () => DataImport.decodeTags([
        {
          'id': 'one',
          'tag': '一',
          'userId': ['huya_one'],
        },
        {
          'id': 'two',
          'tag': '二',
          'userId': ['invalid'],
        },
      ]),
      throwsFormatException,
    );
  });

  test('AllLive null text is normalized without discarding tag/time', () {
    final users = DataImport.decodeFollowUsers([follow('one')]);
    expect(users['huya_one']!.userName, '');
    expect(users['huya_one']!.face, '');
    expect(users['huya_one']!.tag, '全部');
    expect(users['huya_one']!.addTime, DateTime.utc(2026, 1, 1, 12));
  });

  test('history merge uses authoritative latest time from another window',
      () async {
    final box = AppBox<History>.shared(
      store,
      'history',
      (value) => value.toJson(),
      (value) => History.fromJson(Map<String, dynamic>.from(value)),
    );
    final otherStore = DesktopSharedStore(directory);
    await otherStore.initialize(() async => {});
    final otherBox = AppBox<History>.shared(
      otherStore,
      'history',
      (value) => value.toJson(),
      (value) => History.fromJson(Map<String, dynamic>.from(value)),
    );
    await otherBox.putAll(
      DataImport.decodeHistory([history('one', '2026-02-01T12:00:00Z')]),
    );
    // First window has not refreshed its cache before the stale import arrives.
    await DataImport.apply(
      box,
      DataImport.decodeHistory([
        history('one', '2026-01-01T12:00:00Z'),
        history('two', '2026-01-03T12:00:00Z'),
      ]),
      overlay: false,
    );
    expect(box.get('huya_one')!.updateTime, DateTime.utc(2026, 2, 1, 12));
    expect(box.containsKey('huya_two'), isTrue);
    await otherStore.close();
  });

  for (final overlay in [true, false]) {
    test(
      'apply awaits ${overlay ? 'replaceAll' : 'putAll'} and propagates errors',
      () async {
        final target = DelayedBox<String>();
        var completed = false;
        final pending = DataImport.apply(
                target,
                {
                  'key': 'value',
                },
                overlay: overlay)
            .then((_) => completed = true);
        expect(target.called, isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(completed, isFalse);
        target.committed.complete();
        await pending;
        expect(completed, isTrue);

        final failedTarget = DelayedBox<String>();
        final failed = DataImport.apply(failedTarget, <String, String>{},
            overlay: overlay);
        final assertion = expectLater(failed, throwsStateError);
        failedTarget.committed.completeError(StateError('write failed'));
        await assertion;
      },
    );
  }

  test('malformed credential JSON never appears in validation error', () {
    const secret = 'very-private-cookie';
    try {
      DataImport.decodeCookie('{"cookie":"$secret"');
      fail('must reject malformed JSON');
    } on FormatException catch (error) {
      expect(error.toString(), isNot(contains(secret)));
    }
  });

  test('duplicate histories retain newest input independently of order', () {
    final rows = [
      history('one', '2026-02-01T12:00:00Z'),
      history('one', '2026-01-01T12:00:00Z'),
    ];
    expect(
      DataImport.decodeHistory(rows)['huya_one']!.updateTime,
      DataImport.decodeHistory(rows.reversed.toList())['huya_one']!.updateTime,
    );
  });
}
