import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

import 'live_room_lifecycle_test.dart'
    show FakeDB, FakeSettings, FakeSite, TestRoomController, site;

class ChatController extends TestRoomController {
  ChatController() : super(site(FakeSite()), 'chat');
  int scrollCalls = 0;

  @override
  void chatScrollToBottom() {
    scrollCalls++;
    super.chatScrollToBottom();
  }
}

LiveMessage chat(int index) => LiveMessage(
      type: LiveMessageType.chat,
      userName: 'viewer',
      message: '$index',
      color: LiveMessageColor.white,
    );

void receive(ChatController controller, int start, int end) {
  for (var i = start; i < end; i++) {
    controller.onWSMessage(chat(i));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ChatController controller;
  setUp(() {
    Get.testMode = true;
    Get.put<AppSettingsController>(FakeSettings());
    Get.put<DBService>(FakeDB());
    controller = ChatController();
  });
  tearDown(() {
    controller.preparePlayerClose();
    Get.reset();
  });

  testWidgets('live chat retains exactly the newest 200 and coalesces frames', (
    tester,
  ) async {
    receive(controller, 0, 10000);
    expect(controller.messages.length, LiveRoomController.maxChatMessages);
    expect(controller.messages.first.message, '9800');
    expect(controller.messages.last.message, '9999');
    expect(controller.pendingChatMessageCount, 0);
    expect(controller.scrollCalls, 0);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(controller.scrollCalls, 1);
  });

  testWidgets('reading snapshot stays still while arrivals stay bounded', (
    tester,
  ) async {
    receive(controller, 0, 200);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 300,
          child: Obx(
            () => ListView(
              controller: controller.scrollController,
              children: controller.messages
                  .map(
                    (message) =>
                        SizedBox(height: 40, child: Text(message.message)),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
    controller.disableAutoScroll.value = true;
    controller.scrollController.jumpTo(400);
    final snapshot = controller.messages.toList();
    receive(controller, 200, 10200);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(controller.messages, orderedEquals(snapshot));
    expect(controller.scrollController.offset, 400);
    expect(controller.pendingChatMessageCount, 200);
    controller.resumeChatAutoScroll();
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(controller.disableAutoScroll.value, isFalse);
    expect(controller.messages.first.message, '10000');
    expect(controller.messages.last.message, '10199');
    expect(controller.pendingChatMessageCount, 0);
    expect(
      controller.scrollController.offset,
      controller.scrollController.position.maxScrollExtent,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'short pause preserves older history and repeated resume is safe',
    (tester) async {
      receive(controller, 0, 200);
      for (var i = 200; i < 220; i++) {
        controller.disableAutoScroll.value = true;
        controller.onWSMessage(chat(i));
        controller.resumeChatAutoScroll();
        controller.resumeChatAutoScroll();
      }
      expect(controller.messages.length, 200);
      expect(controller.messages.first.message, '20');
      expect(controller.messages.last.message, '219');
      tester.binding.scheduleFrame();
      await tester.pump();
      expect(controller.scrollCalls, 1);
    },
  );

  testWidgets(
    'background arrivals do not enqueue scrolling and remain bounded',
    (tester) async {
      controller.isBackground = true;
      receive(controller, 0, 10000);
      tester.binding.scheduleFrame();
      await tester.pump();
      expect(controller.messages.length, 200);
      expect(controller.scrollCalls, 0);
      controller.disableAutoScroll.value = true;
      receive(controller, 10000, 20000);
      expect(controller.messages.length, 200);
      expect(controller.pendingChatMessageCount, 200);
      controller.isBackground = false;
      controller.resumeChatAutoScroll();
      tester.binding.scheduleFrame();
      await tester.pump();
      expect(controller.messages.first.message, '19800');
      expect(controller.scrollCalls, 1);
    },
  );

  testWidgets('blocked messages do not evict history or enter pending buffer', (
    tester,
  ) async {
    receive(controller, 0, 200);
    AppSettingsController.instance.shieldList.add('blocked');
    final blocked = LiveMessage(
      type: LiveMessageType.chat,
      userName: 'viewer',
      message: 'blocked',
      color: LiveMessageColor.white,
    );
    controller.onWSMessage(blocked);
    expect(controller.messages.first.message, '0');
    expect(controller.messages.length, 200);
    controller.disableAutoScroll.value = true;
    controller.onWSMessage(blocked);
    expect(controller.pendingChatMessageCount, 0);
    tester.binding.scheduleFrame();
    await tester.pump();
  });

  testWidgets('system messages share both limits', (tester) async {
    for (var i = 0; i < 1000; i++) {
      controller.addSysMsg('system $i');
    }
    expect(controller.messages.length, 200);
    controller.disableAutoScroll.value = true;
    for (var i = 1000; i < 2000; i++) {
      controller.addSysMsg('system $i');
    }
    expect(controller.messages.first.message, 'system 800');
    expect(controller.pendingChatMessageCount, 200);
    controller.resumeChatAutoScroll();
    expect(controller.messages.first.message, 'system 1800');
    tester.binding.scheduleFrame();
    await tester.pump();
  });

  testWidgets('room switch clears frozen and pending history', (tester) async {
    receive(controller, 0, 200);
    controller.disableAutoScroll.value = true;
    receive(controller, 200, 400);
    final next = FakeSite();
    // Loading remains pending; reset must discard the old buffers immediately.
    controller.resetRoom(site(next), 'next');
    expect(controller.messages, isEmpty);
    expect(controller.pendingChatMessageCount, 0);
    expect(controller.disableAutoScroll.value, isFalse);
    tester.binding.scheduleFrame();
    await tester.pump();
  });

  testWidgets('closing discards buffers and makes queued scroll harmless', (
    tester,
  ) async {
    receive(controller, 0, 200);
    controller.disableAutoScroll.value = true;
    receive(controller, 200, 400);
    controller.preparePlayerClose();
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(controller.messages, isEmpty);
    expect(controller.pendingChatMessageCount, 0);
    expect(controller.scrollCalls, 0);
    controller.addSysMsg('late');
    controller.onWSMessage(chat(401));
    expect(controller.messages, isEmpty);
    expect(controller.pendingChatMessageCount, 0);
  });
}
