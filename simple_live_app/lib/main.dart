import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:logger/logger.dart';
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/sub_window_app.dart';
import 'package:simple_live_app/app/desktop_startup_app.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/app/utils/listen_fourth_button.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/modules/other/debug_log_page.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/routes/app_pages.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/bilibili_account_service.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/services/storage/app_data_store.dart';
import 'package:simple_live_app/services/shared_state_service.dart';
import 'package:simple_live_app/services/desktop_lifecycle_service.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_app/services/sync_service.dart';
import 'package:simple_live_app/widgets/status/app_loadding_widget.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:window_manager/window_manager.dart';

import 'package:dynamic_color/dynamic_color.dart';

void main(List<String> args) {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Log.initialize(detailed: !kReleaseMode);
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      Log.e(details.exception, details.stack ?? StackTrace.current);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      Log.e(error, stack);
      return true;
    };
    try {
      await _startApplication(args);
    } catch (error, stack) {
      Log.e(error, stack);
      if (_isDesktop) {
        runApp(
          DesktopStartupApp(failed: true, onClose: () => windowManager.close()),
        );
      } else {
        runApp(
          const MaterialApp(
            home: Scaffold(
              body: Center(child: Text('启动失败，原有数据已保留。请查看应用数据目录中的日志。')),
            ),
          ),
        );
      }
      await Log.flush();
    }
  }, (error, stack) => Log.e(error, stack));
}

Future<void> _startApplication(List<String> args) async {
  // 桌面端：检查是否为子窗口进程（通过命令行参数 --sub-window 传递）
  if (args.isNotEmpty && args[0] == '--sub-window') {
    await _runSubWindow(args.length > 1 ? args[1] : '{}');
    return;
  }
  if (_isDesktop) {
    runApp(DesktopStartupApp(onClose: () => windowManager.close()));
  }
  await _startupStage('主窗口显示', initWindow);
  await _startupStage('播放器运行库', () async => MediaKit.ensureInitialized());
  await _startupStage('存储路径', initHive);
  await _startupStage('主窗口服务', initServices);
  if (!Platform.isAndroid && !Platform.isIOS) {
    await DesktopLifecycleService.instance.initialize();
  }
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  //设置状态栏为透明
  SystemUiOverlayStyle systemUiOverlayStyle = const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
  );
  SystemChrome.setSystemUIOverlayStyle(systemUiOverlayStyle);
  runApp(const MyApp());
}

/// 初始化 Hive 存储路径
/// - 移动端：Documents（Hive.initFlutter 默认）
/// - 桌面端：Application Support（直接 Hive.init，避免把绝对路径误当 subDir）
Future initHive() async {
  if (Platform.isAndroid || Platform.isIOS) {
    await Hive.initFlutter();
    return;
  }
  final supportDir = await getApplicationSupportDirectory();
  if (!await supportDir.exists()) {
    await supportDir.create(recursive: true);
  }
  Hive.init(supportDir.path);
  Log.d("Hive path: ${supportDir.path}");
}

bool get _isDesktop =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

Future<T> _startupStage<T>(String name, Future<T> Function() action) async {
  final watch = Stopwatch()..start();
  try {
    return await action();
  } finally {
    // Available in release diagnostics without URLs, arguments or credentials.
    Log.w('启动阶段 $name: ${watch.elapsedMilliseconds}ms');
  }
}

Future<void> initWindow({bool subWindow = false, String? title}) async {
  if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    return;
  }
  await windowManager.ensureInitialized();
  final windowOptions = WindowOptions(
    minimumSize: subWindow ? const Size(400, 300) : const Size(280, 280),
    size: subWindow ? const Size(960, 540) : null,
    center: true,
    title: title ?? 'Simple Live',
  );
  // The plugin callback is void and does not await async show/focus actions.
  await windowManager.waitUntilReadyToShow(windowOptions);
  await windowManager.show();
  await windowManager.focus();
}

Future initServices({bool subWindow = false}) async {
  Hive.registerAdapter(FollowUserAdapter());
  Hive.registerAdapter(HistoryAdapter());
  Hive.registerAdapter(FollowUserTagAdapter());

  await _startupStage('共享存储', () => AppDataStore.instance.initialize());

  //包信息
  Utils.packageInfo = await _startupStage('包信息', PackageInfo.fromPlatform);
  //本地存储
  Log.d("Init LocalStorage Service");
  await _startupStage('本地设置', () => Get.put(LocalStorageService()).init());
  await _startupStage('收藏和历史', () => Get.put(DBService()).init());
  //初始化设置控制器
  Get.put(AppSettingsController());

  Get.put(BiliBiliAccountService(refreshProfileOnRestore: !subWindow));

  Get.put(DouyinAccountService());

  if (!subWindow) Get.put(SyncService());

  Get.put(FollowService(backgroundRefresh: !subWindow));

  Get.put(SharedStateService());
  Log.setDetailed(
    !kReleaseMode || AppSettingsController.instance.logEnable.value,
  );

  initCoreLog();
}

void initCoreLog() {
  //日志信息
  CoreLog.enableLog = true;
  CoreLog.requestLogType = RequestLogType.short;
  CoreLog.onPrintLog = (level, msg) {
    switch (level) {
      case Level.debug:
        Log.d(msg);
        break;
      case Level.error:
        Log.e(msg, StackTrace.current);
        break;
      case Level.info:
        Log.i(msg);
        break;
      case Level.warning:
        Log.w(msg);
        break;
      default:
        Log.logPrint(msg);
    }
  };
}

Future<void> _runSubWindow(String argument) async {
  runApp(
    DesktopStartupApp(liveWindow: true, onClose: () => windowManager.close()),
  );
  String title = '直播间';
  try {
    final params = jsonDecode(argument) as Map<String, dynamic>;
    final siteId = params['siteId'] as String?;
    final roomId = params['roomId'] as String?;
    if (siteId != null && roomId != null) {
      final site = Sites.allSites[siteId];
      title = '${site?.name ?? siteId} - $roomId';
    }
  } catch (_) {
    // Invalid room arguments are handled by the ready application's route.
  }
  await _startupStage(
    '直播窗口显示',
    () => initWindow(subWindow: true, title: title),
  );
  await _startupStage('播放器运行库', () async => MediaKit.ensureInitialized());
  await _startupStage('存储路径', initHive);
  await _startupStage('直播窗口服务', () => initServices(subWindow: true));
  await DesktopLifecycleService.instance.initialize();
  // Room routing begins only after shared settings and accounts are ready.
  runApp(SubWindowApp(argument: argument));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => Obx(_buildApp);

  Widget _buildApp() {
    bool isDynamicColor = AppSettingsController.instance.isDynamic.value;
    Color styleColor = Color(AppSettingsController.instance.styleColor.value);
    return DynamicColorBuilder(
        builder: ((ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
      ColorScheme? lightColorScheme;
      ColorScheme? darkColorScheme;
      if (lightDynamic != null && darkDynamic != null && isDynamicColor) {
        lightColorScheme = lightDynamic;
        darkColorScheme = darkDynamic;
      } else {
        lightColorScheme = ColorScheme.fromSeed(
          seedColor: styleColor,
          brightness: Brightness.light,
        );
        darkColorScheme = ColorScheme.fromSeed(
            seedColor: styleColor, brightness: Brightness.dark);
      }
      return GetMaterialApp(
        title: "Simple Live",
        theme: AppStyle.themeFor(lightColorScheme),
        darkTheme: AppStyle.themeFor(darkColorScheme),
        themeMode:
            ThemeMode.values[Get.find<AppSettingsController>().themeMode.value],
        initialRoute: RoutePath.kIndex,
        getPages: AppPages.routes,
        //国际化
        locale: const Locale("zh", "CN"),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale("zh", "CN")],
        logWriterCallback: (text, {bool? isError}) {
          Log.addDebugLog(text, (isError ?? false) ? Colors.red : Colors.grey);
          Log.writeLog(text, (isError ?? false) ? Level.error : Level.info);
        },
        // 升级后Android页面过渡动画似乎有BUG
        defaultTransition: Platform.isAndroid ? Transition.cupertino : null,
        //debugShowCheckedModeBanner: false,
        navigatorObservers: [FlutterSmartDialog.observer],
        builder: FlutterSmartDialog.init(
          loadingBuilder: ((msg) => const AppLoaddingWidget()),
          //字体大小不跟随系统变化
          builder: (context, child) {
            // Fix for HyperOS windowed-mode Flutter bug:
            // - Values > 50 indicate the bug (windowed mode on HyperOS)
            // - Values == 0 are valid for fullscreen/immersive mode and must NOT be treated as abnormal
            const fallbackPadding = EdgeInsets.only(top: 25, bottom: 35);
            const maxNormalPadding = 50.0;

            final mediaQueryData = MediaQuery.of(context);
            final hasAbnormalPadding =
                mediaQueryData.viewPadding.top > maxNormalPadding;

            final fixedMediaQueryData = hasAbnormalPadding
                ? mediaQueryData.copyWith(
                    viewPadding: fallbackPadding,
                    padding: fallbackPadding,
                    textScaler: const TextScaler.linear(1.0),
                  )
                : mediaQueryData.copyWith(
                    textScaler: const TextScaler.linear(1.0));

            return MediaQuery(
              data: fixedMediaQueryData,
              child: Stack(
                children: [
                  //侧键返回
                  RawGestureDetector(
                    excludeFromSemantics: true,
                    gestures: <Type, GestureRecognizerFactory>{
                      FourthButtonTapGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                              FourthButtonTapGestureRecognizer>(
                        () => FourthButtonTapGestureRecognizer(),
                        (FourthButtonTapGestureRecognizer instance) {
                          instance.onTapDown = (TapDownDetails details) async {
                            //如果处于全屏状态，退出全屏
                            if (!Platform.isAndroid && !Platform.isIOS) {
                              if (Get.isRegistered<LiveRoomController>()) {
                                final room = Get.find<LiveRoomController>();
                                if (room.fullScreenState.value ||
                                    room.smallWindowState.value) {
                                  await room.exitFull();
                                  return;
                                }
                              }
                              if (await windowManager.isFullScreen()) {
                                await windowManager.setFullScreen(false);
                                return;
                              }
                            }
                            Get.back();
                          };
                        },
                      ),
                    },
                    child: child!,
                  ),

                  //查看DEBUG日志按钮
                  //只在Debug、Profile模式显示
                  Visibility(
                    visible: !kReleaseMode,
                    child: Positioned(
                      right: 12,
                      bottom: 100 + context.mediaQueryViewPadding.bottom,
                      child: Opacity(
                        opacity: 0.4,
                        child: ElevatedButton(
                          child: const Text("DEBUG LOG"),
                          onPressed: () {
                            Get.bottomSheet(
                              const DebugLogPage(),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }));
  }
}
