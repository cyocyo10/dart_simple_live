import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/modules/mine/parse/room_link_parser.dart';

class ParseController extends GetxController {
  final TextEditingController roomJumpToController = TextEditingController();
  final TextEditingController getUrlController = TextEditingController();

  bool _jumping = false;
  bool _readingUrl = false;

  Future<void> jumpToRoom(String text) async {
    if (_jumping || isClosed) return;
    if (text.trim().isEmpty) {
      SmartDialog.showToast('链接不能为空');
      return;
    }
    _jumping = true;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final result = await parse(text);
      if (isClosed) return;
      if (result.isEmpty || (result.first as String).isEmpty) {
        SmartDialog.showToast('无法解析此链接');
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (isClosed) return;
      AppNavigator.toLiveRoomDetail(
          site: result[1] as Site, roomId: result.first);
    } catch (_) {
      if (!isClosed) SmartDialog.showToast('链接解析失败，请检查网络后重试');
    } finally {
      _jumping = false;
    }
  }

  Future<void> getPlayUrl(String text) async {
    if (_readingUrl || isClosed) return;
    if (text.trim().isEmpty) {
      SmartDialog.showToast('链接不能为空');
      return;
    }
    _readingUrl = true;
    var loading = false;
    try {
      final parseResult = await parse(text);
      if (isClosed) return;
      if (parseResult.isEmpty || (parseResult.first as String).isEmpty) {
        SmartDialog.showToast('无法解析此链接');
        return;
      }
      final site = parseResult[1] as Site;
      SmartDialog.showLoading(msg: "");
      loading = true;
      var detail = await site.liveSite.getRoomDetail(roomId: parseResult.first);
      if (isClosed) return;
      var qualites = await site.liveSite.getPlayQualites(detail: detail);
      if (isClosed) return;
      SmartDialog.dismiss(status: SmartStatus.loading);
      loading = false;
      if (qualites.isEmpty) {
        SmartDialog.showToast("读取直链失败,无法读取清晰度");

        return;
      }
      var result = await Get.dialog(SimpleDialog(
        title: const Text("选择清晰度"),
        children: qualites
            .map(
              (e) => ListTile(
                title: Text(
                  e.quality,
                  textAlign: TextAlign.center,
                ),
                onTap: () {
                  Get.back(result: e);
                },
              ),
            )
            .toList(),
      ));
      if (isClosed || result == null) {
        return;
      }
      SmartDialog.showLoading(msg: "");
      loading = true;
      var playUrl =
          await site.liveSite.getPlayUrls(detail: detail, quality: result);
      SmartDialog.dismiss(status: SmartStatus.loading);
      loading = false;
      if (isClosed) return;
      if (playUrl.urls.isEmpty) {
        SmartDialog.showToast("读取直链失败，没有可用线路");
        return;
      }
      await Get.dialog(SimpleDialog(
        title: const Text("选择线路"),
        children: playUrl.urls
            .map(
              (e) => ListTile(
                title: Text(
                  "线路${playUrl.urls.indexOf(e) + 1}",
                ),
                subtitle: Text(
                  e,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: e));
                  Get.back();
                  SmartDialog.showToast("已复制直链");
                },
              ),
            )
            .toList(),
      ));
    } catch (e) {
      if (!isClosed) SmartDialog.showToast("读取直链失败");
    } finally {
      if (loading) SmartDialog.dismiss(status: SmartStatus.loading);
      _readingUrl = false;
    }
  }

  Future<List> parse(String text) async {
    final link = await RoomLinkParser(redirect: (uri) async {
      if (isClosed) return null;
      final location = await getLocation(uri.toString());
      return location.isEmpty ? null : Uri.tryParse(location);
    }).parse(text);
    if (link == null) return [];
    final siteId = switch (link.platform) {
      RoomLinkPlatform.bilibili => Constant.kBiliBili,
      RoomLinkPlatform.douyu => Constant.kDouyu,
      RoomLinkPlatform.huya => Constant.kHuya,
      RoomLinkPlatform.douyin => Constant.kDouyin,
    };
    return [link.roomId, Sites.allSites[siteId]!];
  }

  Future<String> getLocation(String url) async {
    if (isClosed) return '';
    final uri = Uri.tryParse(url);
    if (uri == null || !RoomLinkParser.isTrustedUri(uri)) return '';
    final client = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ));
    try {
      final response = await client.getUri(uri,
          options: Options(
            followRedirects: false,
            validateStatus: (_) => true,
          ));
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        return response.headers.value('location') ?? '';
      }
    } on DioException {
      // Includes network failures without an HTTP response.
      return '';
    } catch (_) {
      return '';
    } finally {
      client.close(force: true);
    }
    return '';
  }

  @override
  void onClose() {
    roomJumpToController.dispose();
    getUrlController.dispose();
    super.onClose();
  }
}
