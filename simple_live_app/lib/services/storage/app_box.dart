import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'desktop_shared_store.dart';

/// Small box API used by the app; mobile keeps Hive, desktop commits to the
/// shared store. No caller needs to send an additional synchronization event.
class AppBox<T> {
  AppBox.hive(Box<T> box)
      : _hive = box,
        _store = null,
        _name = '',
        _encode = null,
        _decode = null;
  AppBox.shared(this._store, this._name, this._encode, this._decode)
      : _hive = null;

  final Box<T>? _hive;
  final DesktopSharedStore? _store;
  final String _name;
  final dynamic Function(T)? _encode;
  final T Function(dynamic)? _decode;
  final Map<String, T> _cache = {};
  final Map<String, dynamic> _pendingSettings = {};
  final Map<String, int> _pendingVersions = {};
  int _nextVersion = 0;
  final Map<String, String> _fingerprints = {};

  Map<dynamic, T> toMap() {
    if (_hive != null) return _hive!.toMap();
    final data = _store!.box(_name)..addAll(_pendingSettings);
    _cache.removeWhere((key, _) => !data.containsKey(key));
    _fingerprints.removeWhere((key, _) => !data.containsKey(key));
    for (final entry in data.entries) {
      final fingerprint = jsonEncode(entry.value);
      if (_fingerprints[entry.key] != fingerprint) {
        _cache[entry.key] = _decode!(entry.value);
        _fingerprints[entry.key] = fingerprint;
      }
    }
    return {for (final key in data.keys) key: _cache[key] as T};
  }

  T? get(dynamic key, {T? defaultValue}) => _hive != null
      ? _hive!.get(key, defaultValue: defaultValue)
      : toMap()[key.toString()] ?? defaultValue;
  bool containsKey(dynamic key) => _hive != null
      ? _hive!.containsKey(key)
      : _store!.box(_name).containsKey(key.toString());
  Iterable<T> get values => toMap().values;
  int get length => _hive?.length ?? _store!.box(_name).length;
  bool get isEmpty => length == 0;
  bool get isNotEmpty => length != 0;

  void _put(Map<String, dynamic> data, String key, dynamic value) {
    // A delayed history write must not replace a newer visit from another room.
    if (_name == 'history' && data[key] is Map && value is Map) {
      final previous = DateTime.tryParse(data[key]['updateTime'].toString());
      final next = DateTime.tryParse(value['updateTime'].toString());
      if (previous != null && next != null && previous.isAfter(next)) return;
    }
    data[key] = value;
  }

  Future<void> put(dynamic key, T value) async {
    if (_hive != null) {
      final previous = _hive!.get(key);
      if (previous is History &&
          value is History &&
          previous.updateTime.isAfter(value.updateTime)) return;
      await _hive!.put(key, value);
      return;
    }
    final id = key.toString();
    final encoded = _encode!(value);
    final version = ++_nextVersion;
    if (_name == 'localstorage') {
      // Keep the latest slider/input value visible while older commits finish.
      // Otherwise a local commit notification can rewind the user's control.
      _pendingSettings[id] = encoded;
      _pendingVersions[id] = version;
    }
    try {
      await _store!.mutate(_name, (data) => _put(data, id, encoded));
    } finally {
      if (_pendingVersions[id] == version) {
        _pendingSettings.remove(id);
        _pendingVersions.remove(id);
      }
    }
  }

  Future<void> putAll(Map<dynamic, T> entries) => _hive != null
      ? _hive!
          .putAll(Map<dynamic, T>.fromEntries(entries.entries.where((entry) {
          final previous = _hive!.get(entry.key);
          final value = entry.value;
          return !(previous is History &&
              value is History &&
              previous.updateTime.isAfter(value.updateTime));
        })))
      : _store!.mutate(_name, (data) {
          for (final entry in entries.entries) {
            _put(data, entry.key.toString(), _encode!(entry.value));
          }
        });
  Future<void> delete(dynamic key) => _hive != null
      ? _hive!.delete(key)
      : _store!.mutate(_name, (data) {
          data.remove(key.toString());
        });
  Future<int> clear() async {
    if (_hive != null) return _hive!.clear();
    var count = 0;
    await _store!.mutate(_name, (data) {
      count = data.length;
      data.clear();
    });
    return count;
  }

  Future<void> replaceAll(Map<dynamic, T> entries) async {
    if (_hive != null) {
      // Validate/encode the incoming batch before dropping any old rows.
      final stale =
          _hive!.keys.where((key) => !entries.containsKey(key)).toList();
      await _hive!.putAll(entries);
      await _hive!.deleteAll(stale);
      return;
    }
    await _store!.mutate(_name, (data) {
      data.clear();
      for (final entry in entries.entries) {
        data[entry.key.toString()] = _encode!(entry.value);
      }
    });
  }

  Future<void> flush() => _hive?.flush() ?? _store!.flush();
}
