import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/app/utils/archive.dart';
import 'package:simple_live_app/app/utils/document.dart';
import 'package:simple_live_app/modules/sync/remote_sync/webdav/webdav_client.dart';
import 'package:simple_live_app/services/bilibili_account_service.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/data_import.dart';
import 'package:simple_live_app/services/local_storage_service.dart';

class RemoteSyncWebDAVController extends BaseController {
  // ui
  var passwordVisible = true.obs;
  // ui-用户选择是否同步
  var isSyncFollows = true.obs;
  var isSyncHistories = true.obs;
  var isSyncBlockWord = true.obs;
  var isSyncBilibiliAccount = true.obs;

  late DAVClient davClient;
  var user = "--".obs;
  var lastRecoverTime = "--".obs;
  var lastUploadTime = "--".obs;

  final _userFollowJsonName = 'SimpleLive_follows.json';
  final _userHistoriesJsonName = 'SimpleLive_histories.json';
  final _userBlockedWordJsonName = 'SimpleLive_blocked_word.json';
  final _userBilibiliAccountJsonName = 'SimpleLive_bilibili_account.json';
  final _userSettingsJsonName = 'SimpleLive_Settings.json';
  final _userTagsJsonName = 'SimpleLive_Tags.json';

  @override
  void onInit() {
    doWebDAVInit();
    super.onInit();
  }

  // webDAV 逻辑
  // 初始化webDAV
  void doWebDAVInit() {
    var uri = LocalStorageService.instance.getValue(
      LocalStorageService.kWebDAVUri,
      "",
    );
    if (uri.isEmpty) {
      notLogin.value = true;
    } else {
      user.value = LocalStorageService.instance.getValue(
        LocalStorageService.kWebDAVUser,
        "",
      );
      var password = LocalStorageService.instance.getValue(
        LocalStorageService.kWebDAVPassword,
        "",
      );
      davClient = DAVClient(uri, user.value, password);
      // 从未同步过默认为最新数据
      lastRecoverTime.value = Utils.parseTime(
        DateTime.fromMillisecondsSinceEpoch(
          LocalStorageService.instance.getValue(
            LocalStorageService.kWebDAVLastRecoverTime,
            DateTime.now().millisecondsSinceEpoch,
          ),
        ),
      );
      lastUploadTime.value = Utils.parseTime(
        DateTime.fromMillisecondsSinceEpoch(
          LocalStorageService.instance.getValue(
            LocalStorageService.kWebDAVLastUploadTime,
            DateTime.now().millisecondsSinceEpoch,
          ),
        ),
      );
      checkIsLogin();
    }
  }

  // 检查webDAV登录状态
  Future<void> checkIsLogin() async {
    try {
      // 返回登录结果
      bool value = await davClient.pingCompleter.future;
      notLogin.value = !value;
    } catch (e) {
      Log.e("$e", StackTrace.current);
      notLogin.value = true;
    }
  }

  // WebDAV登录
  void doWebDAVLogin(
    String webDAVUri,
    String webDAVUser,
    String webDAVPassword,
  ) async {
    // 确认登录
    davClient = DAVClient(webDAVUri, webDAVUser, webDAVPassword);
    await checkIsLogin();
    if (!notLogin.value) {
      // 保存到本地
      LocalStorageService.instance.setValue(
        LocalStorageService.kWebDAVUri,
        webDAVUri,
      );
      LocalStorageService.instance.setValue(
        LocalStorageService.kWebDAVUser,
        webDAVUser,
      );
      user.value = webDAVUser;
      LocalStorageService.instance.setValue(
        LocalStorageService.kWebDAVPassword,
        webDAVPassword,
      );
      Get.back();
      SmartDialog.showToast("登录成功！");
    } else {
      SmartDialog.showToast("WebDAV账号密码验证失败，请重新输入！");
    }
  }

  // WebDAV登出
  @override
  Future<void> onLogout() async {
    var result = await Utils.showAlertDialog("确定要登出WebDAV账号？", title: "退出登录");
    if (result) {
      // 清除本地账号数据
      LocalStorageService.instance.setValue(LocalStorageService.kWebDAVUri, "");
      LocalStorageService.instance.setValue(
        LocalStorageService.kWebDAVUser,
        "",
      );
      LocalStorageService.instance.setValue(
        LocalStorageService.kWebDAVPassword,
        "",
      );
      notLogin.value = true;
    }
  }

  // webDAV上传到云端
  Future<void> doWebDAVUpload() async {
    SmartDialog.showLoading(msg: "正在上传到云端");
    _backupData().then((value) async {
      SmartDialog.dismiss();
      if (value.isNotEmpty) {
        var result = await davClient.backup(Uint8List.fromList(value));
        if (result) {
          SmartDialog.showToast("上传成功");
          DateTime uploadTime = DateTime.now();
          lastUploadTime.value = Utils.parseTime(uploadTime);
          LocalStorageService.instance.setValue(
            LocalStorageService.kWebDAVLastUploadTime,
            uploadTime.millisecondsSinceEpoch,
          );
        } else {
          Log.e("备份失败", StackTrace.current);
          SmartDialog.showToast("上传失败");
        }
      } else {
        SmartDialog.showToast("上传失败");
      }
    });
  }

  // 备份所有数据
  Future<List<int>> _backupData() async {
    final archive = Archive();
    List<int> zipBytes = [];
    // 获取本地备份路径
    var dir = (await getApplicationSupportDirectory()).path;
    var profile = Directory(join(dir, 'backup'));
    if (!profile.existsSync()) {
      profile.createSync();
    }
    try {
      // archive.add(filepath, data_map) 会导致文件损坏
      // follows
      var userFollowList = DBService.instance.getFollowList();
      var dataFollowsMap = {
        'data': userFollowList.map((e) => e.toJson()).toList(),
      };
      final userFollowJsonFile = File(join(profile.path, _userFollowJsonName));
      await userFollowJsonFile.writeAsString(jsonEncode(dataFollowsMap));
      // 用户自定义标签
      var userTagsList = DBService.instance.getFollowTagList();
      var dataTagsMap = {'data': userTagsList.map((e) => e.toJson()).toList()};
      var userTagsJsonFile = File(join(profile.path, _userTagsJsonName));
      await userTagsJsonFile.writeAsString(jsonEncode(dataTagsMap));
      // histories
      var userHistoriesList = DBService.instance.getHistores();
      var dataHistoriesMap = {
        'data': userHistoriesList.map((e) => e.toJson()).toList(),
      };
      final userHistoriesJsonFile = File(
        join(profile.path, _userHistoriesJsonName),
      );
      await userHistoriesJsonFile.writeAsString(jsonEncode(dataHistoriesMap));

      // blocked_word
      var userShieldList = AppSettingsController.instance.shieldList;
      var dataShieldListMap = {'data': userShieldList.toList()};
      final userBlockedWordJsonFile = File(
        join(profile.path, _userBlockedWordJsonName),
      );
      await userBlockedWordJsonFile.writeAsString(
        jsonEncode(dataShieldListMap),
      );

      // bilibili_account
      var userBiliAccountCookieMap = {
        'data': {'cookie': BiliBiliAccountService.instance.cookie},
      };
      final bilibiliAccountJsonFile = File(
        join(profile.path, _userBilibiliAccountJsonName),
      );
      await bilibiliAccountJsonFile.writeAsString(
        jsonEncode(userBiliAccountCookieMap),
      );
      // settings
      var settingList = LocalStorageService.instance.settingsBox.toMap();
      var dataSettingListMap = {'data': settingList};
      final settingJsonFile = File(join(profile.path, _userSettingsJsonName));
      await settingJsonFile.writeAsString(jsonEncode(dataSettingListMap));

      // 遍历profile路径下的所有文件压缩
      await archive.addDirectoryToArchive(profile.path, profile.path);
      final zipEncoder = ZipEncoder();
      zipBytes = zipEncoder.encode(archive);
      profile.clearSync();
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("备份失败：$e");
    }
    return zipBytes;
  }

  // Read and validate every selected file before the first write. Legacy
  // backup files are independent boxes, so a storage failure after a commit
  // is reported as a partial restore rather than as successful synchronization.
  Future<void> doWebDAVRecovery() async {
    SmartDialog.showLoading(msg: "正在恢复到本地");
    final completed = <String>[];
    var writesStarted = false;
    try {
      final data = await davClient.recovery();
      final archive = await Isolate.run<Archive>(() {
        return ZipDecoder().decodeBytes(data);
      });
      final prepared = <String, Future<void> Function()>{};
      for (final file in archive) {
        final operation = _prepareRecovery(file);
        if (operation != null) {
          if (prepared.containsKey(file.name)) {
            throw const FormatException('备份中有重复的数据文件');
          }
          prepared[file.name] = operation;
        }
      }
      if (prepared.isEmpty) {
        throw const FormatException('备份中没有选定的可恢复数据');
      }
      // Settings may include an account cookie. An explicitly selected account
      // file is restored after settings so its value does not get overwritten.
      writesStarted = true;
      final settings = prepared.remove(_userSettingsJsonName);
      if (settings != null) {
        await settings();
        completed.add(_userSettingsJsonName);
      }
      for (final entry in prepared.entries) {
        await entry.value();
        completed.add(entry.key);
      }
      final recoverTime = DateTime.now();
      await LocalStorageService.instance.settingsBox.put(
        LocalStorageService.kWebDAVLastRecoverTime,
        recoverTime.millisecondsSinceEpoch,
      );
      lastRecoverTime.value = Utils.parseTime(recoverTime);
      SmartDialog.showToast('同步完成');
    } catch (error, stack) {
      Log.e('WebDAV 恢复失败（${error.runtimeType}），已提交 ${completed.length} 个数据文件',
          stack);
      SmartDialog.showToast(
        !writesStarted
            ? '恢复失败，未写入本地数据：${error is FormatException ? error.message : "请检查连接及备份文件"}'
            : '恢复未完成，已完整写入 ${completed.length} 个数据文件，请重试',
      );
    } finally {
      // A partial storage failure must still refresh the visible committed data.
      try {
        if (writesStarted) {
          AppSettingsController.instance.reloadFromStorage();
          BiliBiliAccountService.instance.reloadFromStorage();
          EventBus.instance.emit(Constant.kUpdateFollow, 0);
          EventBus.instance.emit(Constant.kUpdateHistory, 0);
        }
      } finally {
        SmartDialog.dismiss();
      }
    }
  }

  Future<void> Function()? _prepareRecovery(ArchiveFile file) {
    if (!file.isFile) return null;
    final selected = file.name == _userSettingsJsonName ||
        (isSyncFollows.value &&
            (file.name == _userFollowJsonName ||
                file.name == _userTagsJsonName)) ||
        (isSyncHistories.value && file.name == _userHistoriesJsonName) ||
        (isSyncBlockWord.value && file.name == _userBlockedWordJsonName) ||
        (isSyncBilibiliAccount.value &&
            file.name == _userBilibiliAccountJsonName);
    if (!selected) return null;
    Object? wrapper;
    try {
      wrapper = jsonDecode(utf8.decode(file.content));
    } catch (_) {
      throw const FormatException('备份 JSON 数据格式错误');
    }
    if (wrapper is! Map || !wrapper.containsKey('data')) {
      throw const FormatException('备份数据格式错误');
    }
    final data = wrapper['data'];
    if (file.name == _userFollowJsonName) {
      final entries = DataImport.decodeFollowUsers(data);
      return () => DataImport.apply(
            DBService.instance.followBox,
            entries,
            overlay: true,
          );
    }
    if (file.name == _userTagsJsonName) {
      final entries = DataImport.decodeTags(data);
      return () =>
          DataImport.apply(DBService.instance.tagBox, entries, overlay: true);
    }
    if (file.name == _userHistoriesJsonName) {
      final entries = DataImport.decodeHistory(data);
      return () => DataImport.apply(
            DBService.instance.historyBox,
            entries,
            overlay: false,
          );
    }
    if (file.name == _userBlockedWordJsonName) {
      final entries = DataImport.decodeShieldWords(data);
      return () => DataImport.apply(
            LocalStorageService.instance.shieldBox,
            entries,
            overlay: false,
          );
    }
    if (file.name == _userSettingsJsonName) {
      final entries = DataImport.decodeSettings(data);
      return () => DataImport.apply(
            LocalStorageService.instance.settingsBox,
            entries,
            overlay: true,
          );
    }
    final cookie = DataImport.decodeCookie(data);
    return () async {
      await BiliBiliAccountService.instance.setCookie(cookie);
      await LocalStorageService.instance.settingsBox.flush();
    };
  }

  // ui控制--密码可见控制
  void changePasswordVisible() {
    passwordVisible.value = !passwordVisible.value;
  }

  void changeIsSyncFollows() {
    isSyncFollows.value = !isSyncFollows.value;
  }

  void changeIsSyncHistories() {
    isSyncHistories.value = !isSyncHistories.value;
  }

  void changeIsSyncBlockWord() {
    isSyncBlockWord.value = !isSyncBlockWord.value;
  }

  void changeIsSyncBilibiliAccount() {
    isSyncBilibiliAccount.value = !isSyncBilibiliAccount.value;
  }
}
