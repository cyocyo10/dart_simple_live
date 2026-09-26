import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A single authoritative snapshot, shared by independent desktop processes.
/// Every snapshot read/modify/write holds the same OS lock. The backup survives an
/// interruption between moving the previous snapshot and publishing the new one.
class DesktopSharedStore {
  DesktopSharedStore(this.directory);

  final Directory directory;
  static final Map<String, Future<void>> _queues = {};
  final _changes = StreamController<Set<String>>.broadcast();
  Stream<Set<String>> get changes => _changes.stream;
  Map<String, dynamic> _state = {};
  Timer? _poller;
  Future<void>? _pollRefresh;
  FileStat? _snapshotStamp;
  final _fullCheckClock = Stopwatch()..start();
  bool _closing = false;
  bool _closed = false;
  Object? _writeFailure;
  StackTrace? _writeFailureStack;
  int get revision => (_state['revision'] as int?) ?? 0;

  Map<String, dynamic> box(String name) => Map<String, dynamic>.from(
      (_state['boxes'] as Map?)?[name] as Map? ?? const {});

  Future<T> _locked<T>(Future<T> Function() action) {
    final key = directory.absolute.path;
    final previous = _queues[key] ?? Future<void>.value();
    final result = previous.then((_) async {
      await directory.create(recursive: true);
      final lock = await File('${directory.path}/state.lock')
          .open(mode: FileMode.append);
      var locked = false;
      try {
        await lock.lock(FileLock.blockingExclusive);
        locked = true;
        return await action();
      } finally {
        try {
          if (locked) await lock.unlock();
        } finally {
          await lock.close();
        }
      }
    });
    _queues[key] =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<Map<String, dynamic>?> _read() async {
    Object? failure;
    for (final name in ['state.json', 'state.backup.json']) {
      final file = File('${directory.path}/$name');
      if (!await file.exists()) continue;
      try {
        final data = jsonDecode(await file.readAsString());
        if (data is Map && data['schema'] is int && data['schema'] != 1) {
          throw UnsupportedError(
              'Shared storage schema ${data['schema']} requires another app version');
        }
        if (data is! Map<String, dynamic> ||
            data['schema'] != 1 ||
            data['revision'] is! int ||
            data['boxes'] is! Map) {
          throw const FormatException('Unsupported shared storage snapshot');
        }
        if (name == 'state.backup.json') {
          // Restore without overwriting the good backup on the next commit.
          final broken = File('${directory.path}/state.json');
          if (await broken.exists()) {
            await broken.rename(
                '${broken.path}.corrupt.${DateTime.now().microsecondsSinceEpoch}');
          }
          await file.copy(broken.path);
        }
        return data;
      } on UnsupportedError {
        rethrow;
      } catch (error) {
        failure = error;
      }
    }
    if (failure != null) {
      throw StateError(
          'Shared storage cannot be read; original files preserved: $failure');
    }
    return null;
  }

  Future<void> _write(Map<String, dynamic> state) async {
    final current = File('${directory.path}/state.json');
    final backup = File('${directory.path}/state.backup.json');
    final pending = File('${directory.path}/state.pending.json');
    await pending.writeAsString(jsonEncode(state), flush: true);
    if (await current.exists()) {
      if (await backup.exists()) await backup.delete();
      await current.rename(backup.path);
    }
    await pending.rename(current.path);
  }

  void _accept(Map<String, dynamic> state) {
    final oldBoxes = _state['boxes'] as Map? ?? {};
    final newBoxes = state['boxes'] as Map;
    final changed = <String>{};
    for (final name in {...oldBoxes.keys, ...newBoxes.keys}) {
      if (jsonEncode(oldBoxes[name]) != jsonEncode(newBoxes[name])) {
        changed.add(name as String);
      }
    }
    _state = state;
    if (changed.isNotEmpty && !_closed) _changes.add(changed);
  }

  Future<void> initialize(
      Future<Map<String, Map<String, dynamic>>> Function() seed) async {
    await _locked(() async {
      var state = await _read();
      if (state == null) {
        state = {'schema': 1, 'revision': 1, 'boxes': await seed()};
        await _write(state);
      }
      _accept(state);
      await _rememberSnapshot();
    });
  }

  Future<void> _rememberSnapshot() async {
    _snapshotStamp = await File('${directory.path}/state.json').stat();
    _fullCheckClock.reset();
  }

  /// Unchanged windows only stat the snapshot; a forced read bounds stale data
  /// even when a replacement preserves both the file size and timestamp.
  /// The fallback takes at most fullCheckInterval plus one polling tick,
  /// excluding I/O and time spent waiting for another process to release the lock.
  void startPolling({
    required void Function(Object, StackTrace) onError,
    Duration interval = const Duration(milliseconds: 300),
    Duration fullCheckInterval = const Duration(seconds: 3),
  }) {
    if (interval <= Duration.zero || fullCheckInterval <= Duration.zero) {
      throw ArgumentError('Polling intervals must be positive');
    }
    if (_closed || _closing) return;
    _poller ??= Timer.periodic(interval, (_) {
      if (_pollRefresh != null || _closed || _closing) return;
      _pollRefresh = _poll(fullCheckInterval, onError).whenComplete(() {
        _pollRefresh = null;
      });
    });
  }

  Future<void> _poll(Duration fullCheckInterval,
      void Function(Object, StackTrace) onError) async {
    try {
      final stamp = await File('${directory.path}/state.json').stat();
      if (_closed || _closing) return;
      final previous = _snapshotStamp;
      if (stamp.type != FileSystemEntityType.file ||
          previous == null ||
          stamp.type != previous.type ||
          stamp.size != previous.size ||
          stamp.modified != previous.modified ||
          _fullCheckClock.elapsed >= fullCheckInterval) {
        await refresh();
      }
    } catch (error, stack) {
      onError(error, stack);
    }
  }

  /// Explicit refresh always reads under the lock, including backup recovery.
  Future<void> refresh() => _locked(() async {
        final state = await _read();
        if (state != null && state['revision'] != revision) _accept(state);
        await _rememberSnapshot();
      });

  Future<void> mutate(
          String name, void Function(Map<String, dynamic>) mutation) =>
      mutateBoxes({name}, (boxes) => mutation(boxes[name]!));

  /// Commit related namespaces together using the latest snapshot under the lock.
  Future<void> mutateBoxes(Set<String> names,
          void Function(Map<String, Map<String, dynamic>>) mutation) =>
      _locked(() async {
        if (_closed) throw StateError('Shared storage is closed');
        final state = await _read();
        if (state == null) {
          throw StateError('Shared storage is not initialized');
        }
        final boxes = state['boxes'] as Map<String, dynamic>;
        final values = <String, Map<String, dynamic>>{
          for (final name in names)
            name: Map<String, dynamic>.from(boxes[name] as Map? ?? {}),
        };
        mutation(values);
        boxes.addAll(values);
        state['revision'] = (state['revision'] as int) + 1;
        try {
          await _write(state);
          _writeFailure = null;
          _writeFailureStack = null;
          _accept(state);
        } catch (error, stack) {
          _writeFailure = error;
          _writeFailureStack = stack;
          rethrow;
        }
      });

  Future<void> flush() async {
    await (_queues[directory.absolute.path] ?? Future<void>.value());
    if (_writeFailure != null) {
      Error.throwWithStackTrace(_writeFailure!, _writeFailureStack!);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closing = true;
    _poller?.cancel();
    _poller = null;
    try {
      // A stat already in progress must not enqueue a refresh after flush.
      await _pollRefresh;
      await flush();
      _closed = true;
      await _changes.close();
    } finally {
      _closing = false;
    }
  }
}
