import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:simple_live_core/src/common/http_client.dart';
import 'package:simple_live_core/src/danmaku/douyu_danmaku.dart';
import 'package:simple_live_core/src/douyu_utils.dart';
import 'package:simple_live_core/src/interface/live_danmaku.dart';
import 'package:simple_live_core/src/interface/live_site.dart';
import 'package:simple_live_core/src/model/live_anchor_item.dart';
import 'package:simple_live_core/src/model/live_category.dart';
import 'package:simple_live_core/src/model/live_message.dart';
import 'package:simple_live_core/src/model/live_play_url.dart';
import 'package:simple_live_core/src/model/live_room_item.dart';
import 'package:simple_live_core/src/model/live_search_result.dart';
import 'package:simple_live_core/src/model/live_room_detail.dart';
import 'package:simple_live_core/src/model/live_play_quality.dart';
import 'package:simple_live_core/src/model/live_category_result.dart';
import 'package:html_unescape/html_unescape.dart';

class DouyuSite implements LiveSite {
  @override
  String id = "douyu";

  @override
  String name = "斗鱼直播";

  @override
  LiveDanmaku getDanmaku() => DouyuDanmaku();

  @override
  Future<List<LiveCategory>> getCategores() async {
    List<LiveCategory> categories = [];
    var result = await HttpClient.instance.getJson(
      "https://m.douyu.com/api/cate/list",
    );
    var cate2Data = result["data"]?["cate2Info"];
    if (cate2Data is! List) return categories;
    var subCateList = cate2Data;
    var cate1Data = result["data"]?["cate1Info"];
    if (cate1Data is! List) return categories;
    for (var item in cate1Data) {
      var cate1Id = item["cate1Id"];
      var cate1Name = item["cate1Name"];
      List<LiveSubCategory> subCategories = [];
      subCateList.where((x) => x["cate1Id"] == cate1Id).forEach((element) {
        subCategories.add(
          LiveSubCategory(
            pic: element["icon"],
            id: element["cate2Id"].toString(),
            parentId: cate1Id.toString(),
            name: element["cate2Name"].toString(),
          ),
        );
      });
      categories.add(
        LiveCategory(
          id: cate1Id.toString(),
          name: cate1Name.toString(),
          children: subCategories,
        ),
      );
    }
    // 根据ID排序
    categories.sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));

    return categories;
  }

  @override
  Future<LiveCategoryResult> getCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async {
    var result = await HttpClient.instance.getJson(
      "https://www.douyu.com/gapi/rkc/directory/mixList/2_${category.id}/$page",
      queryParameters: {},
    );

    var items = <LiveRoomItem>[];
    for (var item in result['data']['rl']) {
      if (item["type"] != 1) {
        continue;
      }
      var roomItem = LiveRoomItem(
        cover: item['rs16'].toString(),
        online: item['ol'],
        roomId: item['rid'].toString(),
        title: item['rn'].toString(),
        userName: item['nn'].toString(),
      );
      items.add(roomItem);
    }
    var hasMore = page < result['data']['pgcnt'];
    return LiveCategoryResult(hasMore: hasMore, items: items);
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites({
    required LiveRoomDetail detail,
  }) async {
    List<LivePlayQuality> qualities = [];
    var playData = await _requestPlayData(detail.roomId, rate: -1);
    var cdns = _parseCdnCodes(playData);

    // 如果cdn以scdn开头，将其放到最后
    cdns.sort((a, b) {
      if (a.startsWith("scdn") && !b.startsWith("scdn")) {
        return 1;
      } else if (!a.startsWith("scdn") && b.startsWith("scdn")) {
        return -1;
      }
      return 0;
    });

    var multirates = playData["multirates"];
    if (multirates is List) {
      for (var item in multirates) {
        qualities.add(
          LivePlayQuality(
            quality: item["name"].toString(),
            data: DouyuPlayData(item["rate"], cdns),
          ),
        );
      }
    }
    return qualities;
  }

  @override
  Future<LivePlayUrl> getPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    var data = quality.data as DouyuPlayData;

    List<String> urls = [];
    for (var item in data.cdns) {
      var url = await getPlayUrl(detail.roomId, data.rate, item);
      if (url.isNotEmpty) {
        urls.add(url);
      }
    }
    // 播放请求头补齐 Referer/Origin/UA/DID Cookie，避免 CDN 403
    return LivePlayUrl(
      urls: urls,
      headers: DouyuUtils.playbackHeaders(detail.roomId),
    );
  }

  Future<String> getPlayUrl(
    String roomId,
    int rate,
    String cdn,
  ) async {
    try {
      var playData = await _requestPlayData(roomId, rate: rate, cdn: cdn);
      return _parsePlayUrl(playData);
    } catch (_) {
      return "";
    }
  }

  /// 请求 getH5PlayV1 取流接口。斗鱼 H5 流地址带 wsAuth 短签名(5 分钟)，
  /// 失败重试时强制刷新加密描述符重新签名。
  Future<Map<String, dynamic>> _requestPlayData(
    String roomId, {
    int rate = -1,
    String cdn = "",
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        var form = await DouyuUtils.buildSignedData(
          roomId: roomId,
          rate: rate,
          cdn: cdn,
          forceRefresh: attempt > 0,
        );
        var result = await HttpClient.instance.postJson(
          "https://www.douyu.com/lapi/live/getH5PlayV1/$roomId",
          data: form,
          header: DouyuUtils.requestHeaders(roomId),
          formUrlEncoded: true,
        );
        if (result is! Map) {
          throw const FormatException("斗鱼取流响应格式错误");
        }
        var errorCode = result["error"] ?? result["code"] ?? -1;
        if (errorCode != 0) {
          throw Exception("斗鱼取流接口返回错误 $errorCode: ${result["msg"]}");
        }
        var data = result["data"];
        if (data is! Map) {
          throw const FormatException("斗鱼取流响应缺少 data");
        }
        return Map<String, dynamic>.from(data);
      } catch (error) {
        lastError = error;
      }
    }
    throw Exception("斗鱼取流请求失败: $lastError");
  }

  static List<String> _parseCdnCodes(Map<String, dynamic> data) {
    var result = <String>[];
    var cdnsWithName = data["cdnsWithName"];
    if (cdnsWithName is List) {
      for (var item in cdnsWithName) {
        var code = item["cdn"]?.toString().trim() ?? "";
        if (code.isNotEmpty && !result.contains(code)) {
          result.add(code);
        }
      }
    }
    var current = data["rtmp_cdn"]?.toString().trim() ?? "";
    if (current.isNotEmpty && !result.contains(current)) {
      result.insert(0, current);
    }
    if (result.isEmpty) {
      result.add("");
    }
    return result;
  }

  /// 解析播放地址。rtmp_live 可能是完整签名地址或相对路径(需与 rtmp_url/flv_url 拼接)，
  /// 裸 CDN 目录不是合法播放输入，必须拦截。
  static String _parsePlayUrl(Map<String, dynamic> data) {
    var unescape = HtmlUnescape();
    String decode(dynamic value) =>
        unescape.convert(value?.toString().trim() ?? "");

    var live = decode(data["rtmp_live"]);
    if (_isPlayableUrl(live)) return live;

    for (var baseKey in const ["rtmp_url", "flv_url"]) {
      var base = decode(data[baseKey]);
      if (base.isEmpty || live.isEmpty) continue;
      var combined =
          "${base.replaceFirst(RegExp(r'/+$'), '')}/${live.replaceFirst(RegExp(r'^/+'), '')}";
      if (_isPlayableUrl(combined)) return combined;
    }

    for (var key in const ["player_1", "stream_url", "url"]) {
      var value = decode(data[key]);
      if (_isPlayableUrl(value)) return value;
    }

    var flvUrl = decode(data["flv_url"]);
    if (_isDirectMediaUrl(flvUrl)) return flvUrl;
    return "";
  }

  static bool _isPlayableUrl(String value) {
    if (value.isEmpty) return false;
    var uri = Uri.tryParse(value);
    return uri != null &&
        uri.host.isNotEmpty &&
        const {"http", "https", "rtmp"}.contains(uri.scheme);
  }

  static bool _isDirectMediaUrl(String value) {
    if (!_isPlayableUrl(value)) return false;
    var path = Uri.parse(value).path.toLowerCase();
    return path.endsWith(".flv") ||
        path.endsWith(".m3u8") ||
        path.endsWith(".mp4");
  }

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async {
    var result = await HttpClient.instance.getJson(
      "https://www.douyu.com/japi/weblist/apinc/allpage/6/$page",
      queryParameters: {},
    );

    var items = <LiveRoomItem>[];
    for (var item in result['data']['rl']) {
      if (item["type"] != 1) {
        continue;
      }
      var roomItem = LiveRoomItem(
        cover: item['rs16'].toString(),
        online: item['ol'],
        roomId: item['rid'].toString(),
        title: item['rn'].toString(),
        userName: item['nn'].toString(),
      );
      items.add(roomItem);
    }
    var hasMore = page < result['data']['pgcnt'];
    return LiveCategoryResult(hasMore: hasMore, items: items);
  }

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    Map roomInfo = await _getRoomInfo(roomId);

    Map h5RoomInfo = await HttpClient.instance.getJson(
      "https://www.douyu.com/swf_api/h5room/$roomId",
      queryParameters: {},
      header: {
        'referer': 'https://www.douyu.com/$roomId',
        'user-agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.43',
      },
    );
    String? showTime = h5RoomInfo["data"]?["show_time"]?.toString();

    if (showTime != null && showTime.isNotEmpty) {
      try {
        int startTimeStamp = int.parse(showTime);
        int currentTimeStamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        int durationInSeconds = currentTimeStamp - startTimeStamp;

        int hours = durationInSeconds ~/ 3600;
        int minutes = (durationInSeconds % 3600) ~/ 60;
        int seconds = durationInSeconds % 60;

        String formattedDuration =
            '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
        print('斗鱼直播间 $roomId 开播时长: $formattedDuration');
      } catch (e) {
        print('计算开播时长出错: $e');
      }
    }

    return LiveRoomDetail(
      cover: roomInfo["room_pic"].toString(),
      online: int.tryParse(roomInfo["room_biz_all"]["hot"].toString()) ?? 0,
      roomId: roomInfo["room_id"].toString(),
      title: roomInfo["room_name"].toString(),
      userName: roomInfo["owner_name"].toString(),
      userAvatar: roomInfo["owner_avatar"].toString(),
      introduction: roomInfo["show_details"].toString(),
      notice: "",
      status: roomInfo["show_status"] == 1 && roomInfo["videoLoop"] != 1,
      danmakuData: roomInfo["room_id"].toString(),
      data: roomInfo["room_id"].toString(),
      url: "https://www.douyu.com/$roomId",
      isRecord: roomInfo["videoLoop"] == 1,
      showTime: showTime,
    );
  }

  @override
  Future<LiveSearchRoomResult> searchRooms(
    String keyword, {
    int page = 1,
  }) async {
    var did = generateRandomString(32);
    var result = await HttpClient.instance.getJson(
      "https://www.douyu.com/japi/search/api/searchShow",
      queryParameters: {"kw": keyword, "page": page, "pageSize": 20},
      header: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.51',
        'referer': 'https://www.douyu.com/search/',
        'Cookie': 'dy_did=$did;acf_did=$did',
      },
    );
    if (result['error'] != 0) {
      throw Exception(result['msg']);
    }
    var items = <LiveRoomItem>[];
    for (var item in result["data"]["relateShow"]) {
      var roomItem = LiveRoomItem(
        roomId: item["rid"].toString(),
        title: item["roomName"].toString(),
        cover: item["roomSrc"].toString(),
        userName: item["nickName"].toString(),
        online: parseHotNum(item["hot"].toString()),
      );
      items.add(roomItem);
    }
    var hasMore = result["data"]["relateShow"].isNotEmpty;
    return LiveSearchRoomResult(hasMore: hasMore, items: items);
  }

  Future<Map> _getRoomInfo(String roomId) async {
    var result = await HttpClient.instance.getJson(
      "https://www.douyu.com/betard/$roomId",
      queryParameters: {},
      header: {
        'referer': 'https://www.douyu.com/$roomId',
        'user-agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.43',
      },
    );
    Map roomInfo;
    if (result is String) {
      var decoded = json.decode(result);
      var room = decoded["room"];
      if (room is! Map) throw Exception("房间数据未找到");
      roomInfo = room;
    } else {
      var room = result["room"];
      if (room is! Map) throw Exception("房间数据未找到");
      roomInfo = room;
    }
    return roomInfo;
  }

  //生成指定长度的16进制随机字符串
  String generateRandomString(int length) {
    var random = Random.secure();
    var values = List<int>.generate(length, (i) => random.nextInt(16));
    StringBuffer stringBuffer = StringBuffer();
    for (var item in values) {
      stringBuffer.write(item.toRadixString(16));
    }
    return stringBuffer.toString();
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(
    String keyword, {
    int page = 1,
  }) async {
    var did = generateRandomString(32);
    var result = await HttpClient.instance.getJson(
      "https://www.douyu.com/japi/search/api/searchUser",
      queryParameters: {
        "kw": keyword,
        "page": page,
        "pageSize": 20,
        "filterType": 1,
      },
      header: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.51',
        'referer': 'https://www.douyu.com/search/',
        'Cookie': 'dy_did=$did;acf_did=$did',
      },
    );

    var items = <LiveAnchorItem>[];
    for (var item in result["data"]["relateUser"]) {
      var liveStatus =
          (int.tryParse(item["anchorInfo"]["isLive"].toString()) ?? 0) == 1;
      var roomType =
          (int.tryParse(item["anchorInfo"]["roomType"].toString()) ?? 0);
      var roomItem = LiveAnchorItem(
        roomId: item["anchorInfo"]["rid"].toString(),
        avatar: item["anchorInfo"]["avatar"].toString(),
        userName: item["anchorInfo"]["nickName"].toString(),
        liveStatus: liveStatus && roomType == 0,
      );
      items.add(roomItem);
    }
    var hasMore = result["data"]["relateUser"].isNotEmpty;
    return LiveSearchAnchorResult(hasMore: hasMore, items: items);
  }

  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    var roomInfo = await _getRoomInfo(roomId);
    return roomInfo["show_status"] == 1 && roomInfo["videoLoop"] != 1;
  }

  @override
  Future<int> getLiveStatusDetail({required String roomId}) async {
    var roomInfo = await _getRoomInfo(roomId);
    if (roomInfo["show_status"] == 1) {
      return roomInfo["videoLoop"] == 1 ? 3 : 2; // 回放 or 直播
    }
    return 1; // 未开播
  }

  int parseHotNum(String hn) {
    try {
      var num = double.parse(hn.replaceAll("万", ""));
      if (hn.contains("万")) {
        num *= 10000;
      }
      return num.round();
    } catch (_) {
      return -999;
    }
  }

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage({
    required String roomId,
  }) {
    //尚不支持
    return Future.value([]);
  }
}

class DouyuPlayData {
  final int rate;
  final List<String> cdns;
  DouyuPlayData(this.rate, this.cdns);
}
