import 'dart:async';
import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/log.dart';
import 'bilibili_account_service.dart';
import 'douyin_account_service.dart';
import 'follow_service.dart';
import 'storage/app_data_store.dart';

/// Refresh reactive projections after either this process or another commits.
/// Reloading never writes the snapshot back, so it cannot echo stale settings.
class SharedStateService extends GetxService {
  StreamSubscription<Set<String>>? _subscription;

  @override
  void onInit() {
    super.onInit();
    final store = AppDataStore.instance.shared;
    if (store == null) return;
    _subscription = store.changes.listen((names) {
      if (names.contains('localstorage') || names.contains('danmushield')) {
        final settings = AppSettingsController.instance;
        final previousRefresh = settings.autoUpdateFollowEnable.value;
        final previousInterval = settings.autoUpdateFollowDuration.value;
        settings.reloadFromStorage();
        if (previousRefresh != settings.autoUpdateFollowEnable.value ||
            previousInterval != settings.autoUpdateFollowDuration.value) {
          FollowService.instance.initTimer();
        }
      }
      if (names.contains('localstorage')) {
        BiliBiliAccountService.instance.reloadFromStorage();
        DouyinAccountService.instance.reloadFromStorage();
      }
      if (names.contains('followuser') || names.contains('followusertag')) {
        EventBus.instance.emit(Constant.kUpdateFollow, null);
      }
      if (names.contains('history')) {
        EventBus.instance.emit(Constant.kUpdateHistory, null);
      }
    }, onError: (Object error, StackTrace stack) => Log.e(error, stack));
    store.startPolling(onError: (error, stack) => Log.e(error, stack));
  }

  @override
  void onClose() {
    _subscription?.cancel();
    AppDataStore.instance.shared?.close();
    super.onClose();
  }
}
