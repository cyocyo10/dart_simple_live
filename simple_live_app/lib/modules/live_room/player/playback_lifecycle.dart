/// Request ownership and serialized native-player commands for a single room.
/// Network work may overlap, but only the current request can reach the player.
class PlaybackLifecycle {
  int _room = 0;
  int _selection = 0;
  bool _closed = false;
  bool _suspended = false;
  Future<void> _commands = Future<void>.value();

  int beginRoom() {
    _selection++;
    return ++_room;
  }

  PlaybackRequest beginPlayback() => PlaybackRequest(_room, ++_selection);
  PlaybackRequest get current => PlaybackRequest(_room, _selection);
  bool ownsRoom(int room) => !_closed && !_suspended && room == _room;
  bool owns(PlaybackRequest request) =>
      ownsRoom(request.room) && request.selection == _selection;

  /// Keep stop/open/jump in order even when a previous native call is pending.
  Future<bool> command(
    PlaybackRequest request,
    Future<void> Function() operation,
  ) async {
    var executed = false;
    final task = _commands.then((_) async {
      if (!owns(request)) return;
      await operation();
      executed = owns(request);
    });
    // A failed native call must not prevent the next room from stopping/opening.
    _commands = task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    await task;
    return executed;
  }

  /// Initialization can itself await native properties. Recheck ownership
  /// before open so a room closed during initialization cannot start playback.
  Future<bool> open(
    PlaybackRequest request, {
    required Future<void> Function() initialize,
    required Future<void> Function() open,
  }) =>
      command(request, () async {
        await initialize();
        if (owns(request)) await open();
      });

  /// Cancelled closing starts fresh requests; old generations stay invalid.
  void suspend() {
    if (_closed || _suspended) return;
    _suspended = true;
    _room++;
    _selection++;
  }

  void resume() {
    if (!_closed) _suspended = false;
  }

  void close() {
    _closed = true;
    _room++;
    _selection++;
  }

  Future<void> get drained => _commands;
}

class PlaybackRequest {
  final int room;
  final int selection;
  const PlaybackRequest(this.room, this.selection);
}
