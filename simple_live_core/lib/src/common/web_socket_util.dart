import 'dart:async';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum SocketStatus { connected, failed, closed }

typedef SocketConnector =
    WebSocketChannel Function(String url, Map<String, dynamic>? headers);

class WebScoketUtils {
  SocketStatus status = SocketStatus.closed;
  final String url;
  final String? backupUrl;
  final int heartBeatTime;
  final Function(dynamic)? onMessage;
  final Function(String msg)? onClose;
  final Function()? onReconnect;
  final Function()? onReady;
  final Function()? onHeartBeat;
  Map<String, dynamic>? headers;
  final SocketConnector _connector;
  final Duration reconnectDelay;

  WebScoketUtils({
    required this.url,
    required this.heartBeatTime,
    this.onMessage,
    this.onClose,
    this.onReconnect,
    this.onReady,
    this.onHeartBeat,
    this.headers,
    this.backupUrl,
    SocketConnector? connector,
    this.reconnectDelay = const Duration(seconds: 5),
  }) : _connector =
           connector ??
           ((url, headers) => IOWebSocketChannel.connect(
             url,
             connectTimeout: const Duration(seconds: 10),
             headers: headers,
           ));

  WebSocketChannel? webSocket;
  Timer? heartBeatTimer;
  int reconnectTime = 0;
  Timer? reconnectTimer;
  int maxReconnectTime = 5;
  StreamSubscription<dynamic>? streamSubscription;
  int _generation = 0;
  bool _stopped = true;

  /// An explicit connect starts a new session and resets its retry budget.
  void connect({bool retry = false}) {
    close();
    _stopped = false;
    reconnectTime = 0;
    unawaited(_connect(retry));
  }

  Future<void> _connect(bool useBackup) async {
    final generation = ++_generation;
    try {
      final endpoint = useBackup && (backupUrl?.isNotEmpty ?? false)
          ? backupUrl!
          : url;
      final channel = _connector(endpoint, headers);
      webSocket = channel;
      // Listen before ready: handshake failures can also arrive on the stream.
      streamSubscription = channel.stream.listen(
        (data) {
          if (_active(generation)) receiveMessage(data);
        },
        onError: (Object error, StackTrace stack) {
          _fail(generation, error.toString());
        },
        onDone: () => _fail(generation, '服务器已断开连接'),
      );
      await channel.ready;
      if (!_active(generation)) return;
      status = SocketStatus.connected;
      onReady?.call();
      if (!_active(generation)) return;
      if (heartBeatTime > 0) {
        heartBeatTimer = Timer.periodic(Duration(milliseconds: heartBeatTime), (
          _,
        ) {
          if (_active(generation)) onHeartBeat?.call();
        });
      }
    } catch (error) {
      _fail(generation, error.toString());
    }
  }

  bool _active(int generation) => !_stopped && generation == _generation;

  void _disposeConnection() {
    heartBeatTimer?.cancel();
    heartBeatTimer = null;
    final subscription = streamSubscription;
    streamSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    final channel = webSocket;
    webSocket = null;
    if (channel != null) {
      unawaited(channel.sink.close().catchError((Object _) {}));
    }
  }

  void _fail(int generation, String reason) {
    if (!_active(generation)) return;
    ++_generation; // Ignore onDone/error/ready callbacks from the old socket.
    status = SocketStatus.failed;
    _disposeConnection();
    if (reconnectTime >= maxReconnectTime) {
      _stopped = true;
      onClose?.call('重连超过最大次数，与服务器断开连接：$reason');
      return;
    }
    reconnectTime++;
    final retryGeneration = _generation;
    onReconnect?.call();
    if (!_active(retryGeneration)) return;
    reconnectTimer = Timer(reconnectDelay, () {
      reconnectTimer = null;
      if (!_active(retryGeneration)) return;
      // Alternate the primary and backup endpoints across bounded attempts.
      unawaited(_connect(reconnectTime.isOdd));
    });
  }

  void receiveMessage(dynamic data) {
    // Only actual traffic proves that a connection has recovered.
    reconnectTime = 0;
    onMessage?.call(data);
  }

  void sendMessage(dynamic message) {
    if (status != SocketStatus.connected) return;
    try {
      webSocket?.sink.add(message);
    } catch (error) {
      _fail(_generation, error.toString());
    }
  }

  void close() {
    _stopped = true;
    ++_generation;
    status = SocketStatus.closed;
    reconnectTimer?.cancel();
    reconnectTimer = null;
    _disposeConnection();
  }

  void onError(dynamic error, dynamic stack) =>
      _fail(_generation, error.toString());
  void onDone() => _fail(_generation, '服务器已断开连接');
  void reconnect() => _fail(_generation, '正在重新连接');
}
