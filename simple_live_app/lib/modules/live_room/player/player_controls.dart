import 'dart:io';
import 'player_gesture_region.dart';

import 'package:simple_live_app/widgets/platform_choice_button.dart';
import 'package:simple_live_app/widgets/desktop_control_bar.dart';
import 'package:simple_live_app/widgets/desktop_volume_button.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/settings/danmu_settings_page.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/widgets/desktop_refresh_button.dart';
import 'package:simple_live_app/widgets/follow_user_item.dart';
import 'package:window_manager/window_manager.dart';
import 'package:simple_live_app/widgets/superchat_card.dart';

import 'dart:async';

import 'package:simple_live_core/simple_live_core.dart';

Widget playerControls(VideoState videoState, LiveRoomController controller) {
  return Obx(() {
    if (controller.fullScreenState.value) {
      return buildFullControls(videoState, controller);
    }
    return buildControls(
      videoState.context.orientation == Orientation.portrait,
      videoState,
      controller,
    );
  });
}

Widget buildFullControls(VideoState videoState, LiveRoomController controller) {
  var padding = MediaQuery.of(videoState.context).padding;
  final controlsDuration = MediaQuery.disableAnimationsOf(videoState.context)
      ? Duration.zero
      : const Duration(milliseconds: 150);
  return DragToMoveArea(
    child: Stack(
      children: [
        Container(),
        buildDanmuView(videoState, controller),

        // 左下角SC显示
        Obx(
          () => Visibility(
            visible: AppSettingsController.instance.playershowSuperChat.value &&
                ((!Platform.isAndroid && !Platform.isIOS) ||
                    controller.fullScreenState.value),
            child: Positioned(
              left: 24,
              bottom: 24,
              child: PlayerSuperChatOverlay(controller: controller),
            ),
          ),
        ),

        Center(
          child: // 中间
              StreamBuilder(
            stream: videoState.widget.controller.player.stream.buffering,
            initialData: videoState.widget.controller.player.state.buffering,
            builder: (_, s) => Visibility(
              visible: s.data ?? false,
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
        ),
        Positioned.fill(
          child: PlayerGestureRegion(
            controller: controller,
            onLongPress: () {
              if (controller.lockControlsState.value) {
                return;
              }
              showFollowUser(controller);
            },
            child: MouseRegion(
              onHover: (PointerHoverEvent event) {
                controller.onHover(event, videoState.context);
              },
              child: Container(
                width: double.infinity,
                height: double.infinity,
                color: Colors.transparent,
              ),
            ),
          ),
        ),

        // 顶部
        Obx(
          () => AnimatedPositioned(
            left: 0,
            right: 0,
            top: (controller.showControlsState.value &&
                    !controller.lockControlsState.value)
                ? 0
                : -(48 + padding.top),
            duration: controlsDuration,
            child: Container(
              height: 48 + padding.top,
              padding: EdgeInsets.only(
                left: padding.left + 12,
                right: padding.right + 12,
                top: padding.top,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '退出小窗或全屏',
                    onPressed: () {
                      if (controller.smallWindowState.value) {
                        controller.exitSmallWindow();
                      } else {
                        controller.exitFull();
                      }
                    },
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  AppStyle.hGap12,
                  Expanded(
                    child: Text(
                      "${controller.detail.value?.title} - ${controller.detail.value?.userName}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                  AppStyle.hGap12,
                  IconButton(
                    tooltip: '截图',
                    onPressed: () {
                      controller.saveScreenshot();
                    },
                    icon: const Icon(
                      Icons.camera_alt_outlined,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  IconButton(
                    tooltip: '关注列表',
                    onPressed: () {
                      showFollowUser(controller);
                    },
                    icon: const Icon(
                      Remix.play_list_2_line,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  Visibility(
                    visible: Platform.isAndroid,
                    child: IconButton(
                      tooltip: '画中画',
                      onPressed: () {
                        controller.enablePIP();
                      },
                      icon: const Icon(
                        Icons.picture_in_picture,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '播放设置',
                    onPressed: () {
                      showPlayerSettings(controller);
                    },
                    icon: const Icon(
                      Icons.more_horiz,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // 底部
        Obx(
          () => AnimatedPositioned(
            left: 0,
            right: 0,
            bottom: (controller.showControlsState.value &&
                    !controller.lockControlsState.value)
                ? 0
                : -(80 + padding.bottom),
            duration: controlsDuration,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
              padding: EdgeInsets.only(
                left: padding.left + 12,
                right: padding.right + 12,
                bottom: padding.bottom,
              ),
              child: DesktopControlBar(
                  child: Row(
                children: [
                  IconButton(
                    tooltip: '重新连接',
                    onPressed: () {
                      controller.refreshRoom();
                    },
                    icon: const Icon(Remix.refresh_line, color: Colors.white),
                  ),
                  Offstage(
                    offstage: controller.showDanmakuState.value,
                    child: IconButton(
                      tooltip: '显示弹幕',
                      onPressed: () => controller.showDanmakuState.value =
                          !controller.showDanmakuState.value,
                      icon: const ImageIcon(
                        AssetImage('assets/icons/icon_danmaku_open.png'),
                        size: 24,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Offstage(
                    offstage: !controller.showDanmakuState.value,
                    child: IconButton(
                      tooltip: '隐藏弹幕',
                      onPressed: () => controller.showDanmakuState.value =
                          !controller.showDanmakuState.value,
                      icon: const ImageIcon(
                        AssetImage('assets/icons/icon_danmaku_close.png'),
                        size: 24,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '弹幕设置',
                    onPressed: () {
                      showDanmakuSettings(controller);
                    },
                    icon: const ImageIcon(
                      AssetImage('assets/icons/icon_danmaku_setting.png'),
                      size: 24,
                      color: Colors.white,
                    ),
                  ),
                  Obx(
                    () => Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: Text(
                        controller.liveDuration.value,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const Expanded(child: Center()),
                  Visibility(
                    visible: !Platform.isAndroid && !Platform.isIOS,
                    child: buildVolumeButton(controller),
                  ),
                  buildQualityChoice(
                    controller,
                    () => showQualitesInfo(controller),
                  ),
                  buildLineChoice(controller, () => showLinesInfo(controller)),
                  IconButton(
                    tooltip: '退出小窗或全屏',
                    onPressed: () {
                      if (controller.smallWindowState.value) {
                        controller.exitSmallWindow();
                      } else {
                        controller.exitFull();
                      }
                    },
                    icon: const Icon(
                      Remix.fullscreen_exit_fill,
                      color: Colors.white,
                    ),
                  ),
                ],
              )),
            ),
          ),
        ),

        // 右侧锁定
        Obx(
          () => AnimatedPositioned(
            top: 0,
            bottom: 0,
            right: controller.showControlsState.value
                ? padding.right + 12
                : -(64 + padding.right),
            duration: controlsDuration,
            child: buildLockButton(controller),
          ),
        ),
        // 左侧锁定
        Obx(
          () => AnimatedPositioned(
            top: 0,
            bottom: 0,
            left: controller.showControlsState.value
                ? padding.left + 12
                : -(64 + padding.right),
            duration: controlsDuration,
            child: buildLockButton(controller),
          ),
        ),
        Obx(
          () => IgnorePointer(
              child: Offstage(
            offstage: !controller.showGestureTip.value,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  controller.gestureTipText.value,
                  style: const TextStyle(fontSize: 18, color: Colors.white),
                ),
              ),
            ),
          )),
        ),
      ],
    ),
  );
}

Widget buildLockButton(LiveRoomController controller) {
  return Center(
    child: InkWell(
      onTap: () {
        controller.setLockState();
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: AppStyle.radius8,
        ),
        width: 40,
        height: 40,
        child: Center(
          child: Icon(
            controller.lockControlsState.value
                ? Icons.lock_outline_rounded
                : Icons.lock_open_outlined,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    ),
  );
}

Widget buildControls(
  bool isPortrait,
  VideoState videoState,
  LiveRoomController controller,
) {
  final controlsDuration = MediaQuery.disableAnimationsOf(videoState.context)
      ? Duration.zero
      : const Duration(milliseconds: 150);
  return Stack(
    children: [
      Container(),
      buildDanmuView(videoState, controller),

      // 左下角SC显示
      Obx(
        () => Visibility(
          visible: AppSettingsController.instance.playershowSuperChat.value &&
              ((!Platform.isAndroid && !Platform.isIOS) ||
                  controller.fullScreenState.value),
          child: Positioned(
            left: 24,
            bottom: 24,
            child: PlayerSuperChatOverlay(controller: controller),
          ),
        ),
      ),

      // 中间
      Center(
        child: StreamBuilder(
          stream: videoState.widget.controller.player.stream.buffering,
          initialData: videoState.widget.controller.player.state.buffering,
          builder: (_, s) => Visibility(
            visible: s.data ?? false,
            child: const Center(child: CircularProgressIndicator()),
          ),
        ),
      ),
      Positioned.fill(
        child: PlayerGestureRegion(
          controller: controller,
          child: MouseRegion(
            onEnter: controller.onEnter,
            child: Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.transparent,
            ),
          ),
        ),
      ),
      Obx(
        () => AnimatedPositioned(
          left: 0,
          right: 0,
          bottom: controller.showControlsState.value ? 0 : -48,
          duration: controlsDuration,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
              ),
            ),
            child: DesktopControlBar(
                child: Row(
              children: [
                IconButton(
                  tooltip: '重新连接',
                  onPressed: () {
                    controller.refreshRoom();
                  },
                  icon: const Icon(Remix.refresh_line, color: Colors.white),
                ),
                Offstage(
                  offstage: controller.showDanmakuState.value,
                  child: IconButton(
                    tooltip: '显示弹幕',
                    onPressed: () => controller.showDanmakuState.value =
                        !controller.showDanmakuState.value,
                    icon: const ImageIcon(
                      AssetImage('assets/icons/icon_danmaku_open.png'),
                      size: 24,
                      color: Colors.white,
                    ),
                  ),
                ),
                Offstage(
                  offstage: !controller.showDanmakuState.value,
                  child: IconButton(
                    tooltip: '隐藏弹幕',
                    onPressed: () => controller.showDanmakuState.value =
                        !controller.showDanmakuState.value,
                    icon: const ImageIcon(
                      AssetImage('assets/icons/icon_danmaku_close.png'),
                      size: 24,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '弹幕设置',
                  onPressed: () {
                    controller.showDanmuSettingsSheet();
                  },
                  icon: const ImageIcon(
                    AssetImage('assets/icons/icon_danmaku_setting.png'),
                    size: 24,
                    color: Colors.white,
                  ),
                ),
                Obx(
                  () => Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Text(
                      controller.liveDuration.value,
                      style: const TextStyle(fontSize: 14, color: Colors.white),
                    ),
                  ),
                ),
                const Expanded(child: Center()),
                Visibility(
                  visible: !Platform.isAndroid && !Platform.isIOS,
                  child: buildVolumeButton(controller),
                ),
                Offstage(
                  offstage:
                      isPortrait && !isDesktopPlatform(videoState.context),
                  child: buildQualityChoice(
                    controller,
                    controller.showQualitySheet,
                  ),
                ),
                Offstage(
                  offstage:
                      isPortrait && !isDesktopPlatform(videoState.context),
                  child: buildLineChoice(
                    controller,
                    controller.showPlayUrlsSheet,
                  ),
                ),
                Visibility(
                  visible: !Platform.isAndroid && !Platform.isIOS,
                  child: IconButton(
                    tooltip: '置顶小窗',
                    onPressed: () {
                      controller.enterSmallWindow();
                    },
                    icon: const Icon(
                      Icons.picture_in_picture,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
                Visibility(
                  visible: !Platform.isAndroid && !Platform.isIOS,
                  child: IconButton(
                    tooltip: '窗口铺满',
                    onPressed: () {
                      controller.enterWindowFullScreen();
                    },
                    icon: const Icon(Icons.crop_free, color: Colors.white),
                  ),
                ),
                IconButton(
                  tooltip: '全屏',
                  onPressed: () {
                    controller.enterFullScreen();
                  },
                  icon: const Icon(Remix.fullscreen_line, color: Colors.white),
                ),
              ],
            )),
          ),
        ),
      ),
      Obx(
        () => IgnorePointer(
            child: Offstage(
          offstage: !controller.showGestureTip.value,
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                controller.gestureTipText.value,
                style: const TextStyle(fontSize: 18, color: Colors.white),
              ),
            ),
          ),
        )),
      ),
    ],
  );
}

Widget buildDanmuView(VideoState videoState, LiveRoomController controller) {
  var padding = MediaQuery.of(videoState.context).padding;
  controller.danmakuView ??= DanmakuScreen(
    key: controller.globalDanmuKey,
    createdController: controller.initDanmakuController,
    option: controller.currentDanmakuOption,
  );
  return Positioned.fill(
    top: padding.top,
    bottom: padding.bottom,
    child: Obx(
      () => Offstage(
        offstage: !controller.showDanmakuState.value,
        child: Padding(
          padding: controller.fullScreenState.value
              ? EdgeInsets.only(
                  top: AppSettingsController.instance.danmuTopMargin.value,
                  bottom:
                      AppSettingsController.instance.danmuBottomMargin.value,
                )
              : EdgeInsets.zero,
          child: controller.danmakuView!,
        ),
      ),
    ),
  );
}

Widget buildQualityChoice(LiveRoomController controller, VoidCallback mobile) =>
    Obx(() {
      final choices = controller.qualites.toList();
      return PlatformChoiceButton(
        label: controller.currentQualityInfo.value.isEmpty
            ? '清晰度'
            : controller.currentQualityInfo.value,
        options: choices.map((item) => item.quality).toList(),
        selectedIndex: controller.currentQuality,
        onMobilePressed: mobile,
        onOpened: () {
          controller.hideControlsTimer?.cancel();
          controller.showControlsState.value = true;
        },
        onClosed: () {
          if (!controller.isClosed) controller.resetHideControlsTimer();
        },
        onSelected: (i) {
          if (controller.isClosed || i < 0 || i >= choices.length) return;
          final index = controller.qualites
              .indexWhere((item) => identical(item, choices[i]));
          if (index < 0 || index == controller.currentQuality) return;
          controller.currentQuality = index;
          controller.getPlayUrl();
        },
      );
    });

Widget buildLineChoice(LiveRoomController controller, VoidCallback mobile) =>
    Obx(() {
      final choices = controller.playUrls.toList();
      return PlatformChoiceButton(
        label: controller.currentLineInfo.value.isEmpty
            ? '线路'
            : controller.currentLineInfo.value,
        options: [
          for (var i = 0; i < choices.length; i++)
            '线路${i + 1} · ${choices[i].contains('.flv') ? 'FLV' : 'HLS'}'
        ],
        selectedIndex: controller.currentLineIndex,
        onMobilePressed: mobile,
        onOpened: () {
          controller.hideControlsTimer?.cancel();
          controller.showControlsState.value = true;
        },
        onClosed: () {
          if (!controller.isClosed) controller.resetHideControlsTimer();
        },
        onSelected: (i) {
          if (controller.isClosed || i < 0 || i >= choices.length) return;
          final index = controller.playUrls.indexOf(choices[i]);
          if (index < 0 || index == controller.currentLineIndex) return;
          controller.changePlayLine(index);
        },
      );
    });

void showLinesInfo(LiveRoomController controller) {
  if (controller.isVertical.value) {
    controller.showPlayUrlsSheet();
    return;
  }
  Utils.showRightDialog(
    title: "线路",
    useSystem: true,
    child: ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: controller.playUrls.length,
      itemBuilder: (_, i) {
        return ListTile(
          selected: controller.currentLineIndex == i,
          title: Text.rich(
            TextSpan(
              text: "线路${i + 1}",
              children: [
                WidgetSpan(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: AppStyle.radius4,
                      border: Border.all(color: Colors.grey),
                    ),
                    padding: AppStyle.edgeInsetsH4,
                    margin: AppStyle.edgeInsetsL8,
                    child: Text(
                      controller.playUrls[i].contains(".flv") ? "FLV" : "HLS",
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
            style: const TextStyle(fontSize: 14),
          ),
          minLeadingWidth: 16,
          onTap: () {
            Utils.hideRightDialog();
            //controller.currentLineIndex = i;
            //controller.setPlayer();
            controller.changePlayLine(i);
          },
        );
      },
    ),
  );
}

void showQualitesInfo(LiveRoomController controller) {
  if (controller.isVertical.value) {
    controller.showQualitySheet();
    return;
  }
  Utils.showRightDialog(
    title: "清晰度",
    useSystem: true,
    child: ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: controller.qualites.length,
      itemBuilder: (_, i) {
        var item = controller.qualites[i];
        return ListTile(
          selected: controller.currentQuality == i,
          title: Text(item.quality, style: const TextStyle(fontSize: 14)),
          minLeadingWidth: 16,
          onTap: () {
            Utils.hideRightDialog();
            controller.currentQuality = i;
            controller.getPlayUrl();
          },
        );
      },
    ),
  );
}

void showDanmakuSettings(LiveRoomController controller) {
  if (controller.isVertical.value) {
    controller.showDanmuSettingsSheet();
    return;
  }
  Utils.showRightDialog(
    title: "弹幕设置",
    width: 400,
    useSystem: true,
    child: ListView(
      padding: AppStyle.edgeInsetsA12,
      children: [
        DanmuSettingsView(danmakuController: controller.danmakuController),
      ],
    ),
  );
}

void showPlayerSettings(LiveRoomController controller) {
  if (controller.isVertical.value) {
    controller.showPlayerSettingsSheet();
    return;
  }
  Utils.showRightDialog(
    title: "设置",
    width: 320,
    useSystem: true,
    child: Obx(
      () => RadioGroup(
        groupValue: AppSettingsController.instance.scaleMode.value,
        onChanged: (e) {
          AppSettingsController.instance.setScaleMode(e ?? 0);
          controller.updateScaleMode();
        },
        child: ListView(
          padding: AppStyle.edgeInsetsV12,
          children: [
            Padding(
              padding: AppStyle.edgeInsetsH16,
              child: Text("画面尺寸", style: Get.textTheme.titleMedium),
            ),
            const RadioListTile(
              value: 0,
              contentPadding: AppStyle.edgeInsetsH4,
              title: Text("适应"),
              visualDensity: VisualDensity.compact,
            ),
            const RadioListTile(
              value: 1,
              contentPadding: AppStyle.edgeInsetsH4,
              title: Text("拉伸"),
              visualDensity: VisualDensity.compact,
            ),
            const RadioListTile(
              value: 2,
              contentPadding: AppStyle.edgeInsetsH4,
              title: Text("铺满"),
              visualDensity: VisualDensity.compact,
            ),
            const RadioListTile(
              value: 3,
              contentPadding: AppStyle.edgeInsetsH4,
              title: Text("16:9"),
              visualDensity: VisualDensity.compact,
            ),
            const RadioListTile(
              value: 4,
              contentPadding: AppStyle.edgeInsetsH4,
              title: Text("4:3"),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    ),
  );
}

void showFollowUser(LiveRoomController controller) {
  if (controller.isVertical.value) {
    controller.showFollowUserSheet();
    return;
  }

  Utils.showRightDialog(
    title: "关注列表",
    width: 400,
    useSystem: true,
    child: Obx(
      () => Stack(
        children: [
          RefreshIndicator(
            onRefresh: FollowService.instance.loadData,
            child: ListView.builder(
              itemCount: FollowService.instance.liveList.length,
              itemBuilder: (_, i) {
                var item = FollowService.instance.liveList[i];
                return Obx(
                  () => FollowUserItem(
                    item: item,
                    playing: controller.rxSite.value.id == item.siteId &&
                        controller.rxRoomId.value == item.roomId,
                    onTap: () {
                      Utils.hideRightDialog();
                      controller.resetRoom(
                        Sites.allSites[item.siteId]!,
                        item.roomId,
                      );
                    },
                  ),
                );
              },
            ),
          ),
          if (Platform.isLinux || Platform.isWindows || Platform.isMacOS)
            Positioned(
              right: 12,
              bottom: 12,
              child: Obx(
                () => DesktopRefreshButton(
                  refreshing: FollowService.instance.updating.value,
                  onPressed: FollowService.instance.loadData,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class PlayerSuperChatCard extends StatefulWidget {
  final LiveSuperChatMessage message;
  final VoidCallback onExpire;
  final int duration;
  const PlayerSuperChatCard({
    required this.message,
    required this.onExpire,
    required this.duration,
    Key? key,
  }) : super(key: key);
  @override
  State<PlayerSuperChatCard> createState() => _PlayerSuperChatCardState();
}

class _PlayerSuperChatCardState extends State<PlayerSuperChatCard> {
  late Timer timer;
  late int countdown;
  @override
  void initState() {
    super.initState();
    countdown = widget.duration;
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (countdown <= 1) {
        widget.onExpire();
        timer.cancel();
        return;
      }
      setState(() {
        countdown -= 1;
      });
    });
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.65,
      child: SuperChatCard(
        widget.message,
        onExpire: () {},
        customCountdown: countdown,
      ),
    );
  }
}

class LocalDisplaySC {
  final LiveSuperChatMessage sc;
  final DateTime expireAt;
  final int duration;
  LocalDisplaySC(this.sc, this.expireAt, this.duration);
}

class PlayerSuperChatOverlay extends StatefulWidget {
  final LiveRoomController controller;
  const PlayerSuperChatOverlay({required this.controller, Key? key})
      : super(key: key);
  @override
  State<PlayerSuperChatOverlay> createState() => _PlayerSuperChatOverlayState();
}

class _PlayerSuperChatOverlayState extends State<PlayerSuperChatOverlay> {
  final List<LocalDisplaySC> _displayed = [];
  final Map<LocalDisplaySC, Timer> _timers = {};
  late Worker _worker;

  void _addSC(LiveSuperChatMessage sc, {int? customSeconds}) {
    if (_displayed.any((e) => e.sc == sc)) return;
    int showSeconds = customSeconds ?? 15;
    final expireAt = DateTime.now().add(Duration(seconds: showSeconds));
    final localSC = LocalDisplaySC(sc, expireAt, showSeconds);
    _displayed.add(localSC);
    _timers[localSC] = Timer(Duration(seconds: showSeconds), () {
      setState(() {
        _displayed.remove(localSC);
        _timers.remove(localSC)?.cancel();
      });
    });
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    // 首次进房时同步已有SC
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var sc in widget.controller.superChats) {
      int remain = (sc.endTime.millisecondsSinceEpoch - now) ~/ 1000;
      if (remain > 0) {
        _addSC(sc, customSeconds: remain < 15 ? remain : 15);
      }
    }
    // 监听SC列表变化
    _worker = ever<List<LiveSuperChatMessage>>(widget.controller.superChats, (
      list,
    ) {
      // 新增
      for (var sc in list) {
        if (!_displayed.any((e) => e.sc == sc)) {
          _addSC(sc);
        }
      }
      // 移除
      _displayed.removeWhere((e) => !list.contains(e.sc));
      setState(() {});
    });
  }

  @override
  void dispose() {
    _worker.dispose();
    for (var t in _timers.values) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _displayed.toList()
      ..sort((a, b) => a.sc.endTime.compareTo(b.sc.endTime));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var localSC in sorted)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              width: 240,
              child: PlayerSuperChatCard(
                message: localSC.sc,
                onExpire: () {},
                duration: localSC.duration,
              ),
            ),
          ),
      ],
    );
  }
}

Widget buildVolumeButton(LiveRoomController controller) => DesktopVolumeButton(
      volume: controller.playbackVolume,
      onChanged: (value) =>
          controller.setRoomVolume(value, persistDefault: false),
      onChangeEnd: controller.setRoomVolume,
      onMute: controller.toggleMute,
      onOpened: () {
        controller.hideControlsTimer?.cancel();
        controller.showControlsState.value = true;
      },
      onClosed: () {
        if (!controller.isClosed) controller.resetHideControlsTimer();
      },
    );
