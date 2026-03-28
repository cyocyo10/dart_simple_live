import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/live_room_page.dart';
import 'package:simple_live_app/widgets/status/app_loadding_widget.dart';

class SubWindowApp extends StatelessWidget {
  final int windowId;
  final String argument;

  const SubWindowApp({
    super.key,
    required this.windowId,
    required this.argument,
  });

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> params;
    try {
      params = jsonDecode(argument) as Map<String, dynamic>;
    } catch (_) {
      return const MaterialApp(home: Scaffold(body: Center(child: Text('参数解析失败'))));
    }

    final siteId = params['siteId'] as String?;
    final roomId = params['roomId'] as String?;
    final site = siteId != null ? Sites.allSites[siteId] : null;
    if (site == null || roomId == null) {
      return const MaterialApp(home: Scaffold(body: Center(child: Text('无效的直播间参数'))));
    }

    final styleColor =
        Color(AppSettingsController.instance.styleColor.value);
    final lightColorScheme = ColorScheme.fromSeed(
      seedColor: styleColor,
      brightness: Brightness.light,
    );
    final darkColorScheme = ColorScheme.fromSeed(
      seedColor: styleColor,
      brightness: Brightness.dark,
    );

    return GetMaterialApp(
      title: '${site.name} - $roomId',
      theme: AppStyle.lightTheme.copyWith(colorScheme: lightColorScheme),
      darkTheme: AppStyle.darkTheme.copyWith(colorScheme: darkColorScheme),
      themeMode:
          ThemeMode.values[AppSettingsController.instance.themeMode.value],
      locale: const Locale("zh", "CN"),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale("zh", "CN")],
      debugShowCheckedModeBanner: false,
      navigatorObservers: [FlutterSmartDialog.observer],
      builder: FlutterSmartDialog.init(
        loadingBuilder: ((msg) => const AppLoaddingWidget()),
      ),
      initialBinding: BindingsBuilder(() {
        Get.put(LiveRoomController(pSite: site, pRoomId: roomId));
      }),
      home: const LiveRoomPage(),
    );
  }
}
