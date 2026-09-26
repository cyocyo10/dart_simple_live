import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:simple_live_core/src/common/web_socket_util.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _AnonymousBili extends BiliBiliSite {
  @override
  Future<Map<String, String>> getHeader() async => {};
}

class _DirectDouyin extends DouyinSite {
  final requested = <String>[];
  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    requested.add(roomId);
    return _detail(roomId);
  }
}

LiveRoomDetail _detail(String id) => LiveRoomDetail(
  roomId: id,
  title: '直播',
  cover: '',
  userName: '主播',
  userAvatar: '',
  online: 5,
  status: true,
  url: '',
);

class _SocketSink implements WebSocketSink {
  final sent = <dynamic>[];
  bool closed = false;
  @override
  void add(dynamic event) => sent.add(event);
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Socket implements WebSocketChannel {
  final controller = StreamController<dynamic>();
  final readiness = Completer<void>();
  @override
  final _SocketSink sink = _SocketSink();
  @override
  Stream<dynamic> get stream => controller.stream;
  @override
  Future<void> get ready => readiness.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _tick() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  late Dio originalDio;
  setUp(() {
    CoreLog.enableLog = false;
    originalDio = HttpClient.instance.dio;
  });
  tearDown(() {
    HttpClient.instance.dio = originalDio;
  });

  void mockHttp(dynamic Function(RequestOptions) response) {
    HttpClient.instance.dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            try {
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: response(options),
                  statusCode: 200,
                ),
              );
            } catch (error) {
              handler.reject(
                DioException(requestOptions: options, error: error),
              );
            }
          },
        ),
      );
  }

  test('虎牙字符串三态，未知状态不会误认为直播', () async {
    for (final entry in {'ON': 2, 'REPLAY': 3, 'OFF': 1, 'new': 1}.entries) {
      mockHttp((request) {
        expect(request.uri.host, 'mp.huya.com');
        expect(request.queryParameters['do'], 'profileRoom');
        expect(request.queryParameters['roomid'], '123');
        return {
          'status': 200,
          'data': {'liveStatus': entry.key},
        };
      });
      final site = HuyaSite();
      expect(await site.getLiveStatusDetail(roomId: '123'), entry.value);
      expect(await site.getLiveStatus(roomId: '123'), entry.value == 2);
    }
  });

  test('虎牙回放详情携带回放标记且不误标直播', () async {
    mockHttp((request) {
      if (request.uri.host == 'mp.huya.com') {
        return {
          'status': 200,
          'data': {'liveStatus': 'REPLAY'},
        };
      }
      return 'window.HNF_GLOBAL_INIT = ${jsonEncode({
        'roomInfo': {
          'eLiveStatus': 2,
          'tLiveInfo': {'lProfileRoom': 123, 'sIntroduction': '回放', 'lYyid': 0, 'lTotalCount': '5'},
          'tProfileInfo': {'sNick': '主播', 'sAvatar180': ''},
        },
        'roomProfile': {'liveLineUrl': ''},
      })}</script>';
    });
    final detail = await HuyaSite().getRoomDetail(roomId: '123');
    expect(detail.isRecord, isTrue);
    expect(detail.status, isFalse);
    expect(detail.online, 5);
  });

  test('虎牙接口失败不写成离线', () async {
    mockHttp((_) => {'status': 500});
    await expectLater(
      HuyaSite().getLiveStatusDetail(roomId: '123'),
      throwsException,
    );
  });

  test('抖音房间号和可信链接直达，第二页不会重复', () async {
    final site = _DirectDouyin();
    for (final input in [
      '123456',
      'https://live.douyin.com/123456?x=1',
      '分享 https://webcast.amemv.com/reflow/123456?x=1',
    ]) {
      final result = await site.searchRooms(input);
      expect(result.items.single.roomId, '123456');
      expect(result.hasMore, isFalse);
    }
    expect(site.requested, ['123456', '123456', '123456']);
    expect((await site.searchRooms('123456', page: 2)).items, isEmpty);
    expect(DouyinSite.parseDirectRoomId('游戏直播'), isNull);
    expect(DouyinSite.parseDirectRoomId('https://evil.com/123456'), isNull);
  });

  test('抖音短链接无 Cookie 解析，拒绝非平台重定向', () async {
    final site = _DirectDouyin()..searchCookie = 'sensitive=secret';
    HttpClient.instance.dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.uri.host, 'v.douyin.com');
            expect(
              options.headers.keys.map((e) => e.toLowerCase()),
              isNot(contains('cookie')),
            );
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 302,
                headers: Headers.fromMap({
                  'location': ['https://live.douyin.com/123456'],
                }),
              ),
            );
          },
        ),
      );
    expect(
      (await site.searchRooms('https://v.douyin.com/abc/')).items.single.roomId,
      '123456',
    );
    HttpClient.instance.dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.uri.host, 'v.douyin.com');
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 302,
                headers: Headers.fromMap({
                  'location': ['https://evil.com/123456'],
                }),
              ),
            );
          },
        ),
      );
    await expectLater(
      site.searchRooms('https://v.douyin.com/abc/'),
      throwsException,
    );
  });

  test('B站匿名现代接口失败回退旧接口，传递所选清晰度', () async {
    final requests = <RequestOptions>[];
    mockHttp((request) {
      requests.add(request);
      if (request.path.contains('getRoomPlayInfo')) return {'code': -400};
      expect(request.uri.path, '/room/v1/Room/playUrl');
      expect(request.queryParameters['cid'], '7');
      return {
        'code': 0,
        'data': {
          'accept_quality': [10000, 400],
          'quality_description': [
            {'qn': 10000, 'desc': '原画'},
            {'qn': 400, 'desc': '蓝光'},
          ],
          'durl': [
            {'url': 'https://cdn.example/live.flv'},
          ],
        },
      };
    });
    final site = _AnonymousBili();
    final qualities = await site.getPlayQualites(detail: _detail('7'));
    expect(qualities.map((e) => e.quality), ['原画', '蓝光']);
    final urls = await site.getPlayUrls(
      detail: _detail('7'),
      quality: qualities.last,
    );
    expect(urls.urls, ['https://cdn.example/live.flv']);
    expect(requests.last.queryParameters['qn'], 400);
  });

  test('B站现代接口所有线路保留，成功时不调用旧接口', () async {
    mockHttp((request) {
      expect(request.path.contains('getRoomPlayInfo'), isTrue);
      return {
        'data': {
          'playurl_info': {
            'playurl': {
              'g_qn_desc': [
                {'qn': 400, 'desc': '蓝光'},
              ],
              'stream': [
                {
                  'format': [
                    {
                      'codec': [
                        {
                          'accept_qn': [400],
                          'base_url': '/live.flv',
                          'url_info': [
                            {'host': 'https://mcdn.example', 'extra': '?x=1'},
                            {'host': 'https://cdn.example', 'extra': '?x=2'},
                          ],
                        },
                      ],
                    },
                  ],
                },
              ],
            },
          },
        },
      };
    });
    final site = _AnonymousBili();
    final qualities = await site.getPlayQualites(detail: _detail('7'));
    final urls = await site.getPlayUrls(
      detail: _detail('7'),
      quality: qualities.single,
    );
    expect(urls.urls, [
      'https://cdn.example/live.flv?x=2',
      'https://mcdn.example/live.flv?x=1',
    ]);
  });

  test('WebSocket error/onDone只安排一次重连并切备用端点', () async {
    final sockets = <_Socket>[];
    final endpoints = <String>[];
    var reconnects = 0;
    final client = WebScoketUtils(
      url: 'wss://primary',
      backupUrl: 'wss://backup',
      heartBeatTime: 0,
      reconnectDelay: const Duration(milliseconds: 1),
      onReconnect: () => reconnects++,
      connector: (endpoint, _) {
        endpoints.add(endpoint);
        final socket = _Socket();
        sockets.add(socket);
        return socket;
      },
    );
    client.connect();
    sockets.first.readiness.complete();
    await _tick();
    sockets.first.controller.addError(Exception('断开'));
    await sockets.first.controller.close();
    await _tick();
    expect(reconnects, 1);
    expect(endpoints, ['wss://primary', 'wss://backup']);
    client.close();
    sockets.last.readiness.complete();
    await _tick();
    expect(client.status, SocketStatus.closed);
    expect(sockets.last.sink.closed, isTrue);
    await sockets.last.controller.close();
  });

  test('WebSocket握手未完成手动关闭，迟到ready不能复活', () async {
    final socket = _Socket();
    var ready = 0;
    final client = WebScoketUtils(
      url: 'wss://primary',
      heartBeatTime: 1,
      onReady: () => ready++,
      connector: (_, _) => socket,
    );
    client.connect();
    client.close();
    socket.readiness.complete();
    await _tick();
    expect(ready, 0);
    expect(client.status, SocketStatus.closed);
    expect(client.heartBeatTimer, isNull);
    await socket.controller.close();
  });

  test('WebSocket手动关闭会取消已经安排的重连', () async {
    var connects = 0;
    final socket = _Socket();
    final client = WebScoketUtils(
      url: 'wss://primary',
      heartBeatTime: 0,
      reconnectDelay: const Duration(milliseconds: 20),
      connector: (_, _) {
        connects++;
        return socket;
      },
    );
    client.connect();
    socket.readiness.complete();
    await _tick();
    socket.controller.addError(Exception('断开'));
    await _tick();
    expect(client.reconnectTimer, isNotNull);
    client.close();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(connects, 1);
    await socket.controller.close();
  });

  test('WebSocket重连次数有界', () async {
    final sockets = <_Socket>[];
    var closed = 0;
    final client = WebScoketUtils(
      url: 'wss://primary',
      heartBeatTime: 0,
      reconnectDelay: const Duration(milliseconds: 1),
      onClose: (_) => closed++,
      connector: (_, _) {
        final socket = _Socket();
        sockets.add(socket);
        scheduleMicrotask(
          () => socket.readiness.completeError(Exception('握手失败')),
        );
        return socket;
      },
    )..maxReconnectTime = 2;
    client.connect();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(sockets.length, 3);
    expect(closed, 1);
    expect(client.reconnectTimer, isNull);
    client.close();
    for (final socket in sockets) {
      await socket.controller.close();
    }
  });
}
