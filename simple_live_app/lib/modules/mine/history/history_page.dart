import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/mine/history/history_controller.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/modules/mine/history/history_row.dart';
import 'package:simple_live_app/modules/mine/history/history_list.dart';
import 'package:simple_live_app/widgets/status/app_empty_widget.dart';
import 'package:simple_live_app/widgets/status/app_error_widget.dart';
import 'package:flutter_easyrefresh/easy_refresh.dart';

class HistoryPage extends GetView<HistoryController> {
  const HistoryPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("观看记录"),
        actions: [
          IconButton(
            tooltip: '刷新观看记录',
            onPressed: controller.refreshData,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: '导入或导出观看记录',
            onSelected: (value) {
              if (value == 'import') {
                controller.importHistory();
              } else {
                controller.exportHistory();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'import', child: Text('导入观看记录（合并）')),
              PopupMenuItem(value: 'export', child: Text('导出观看记录')),
            ],
          ),
          IconButton(
            tooltip: '清空观看记录',
            onPressed: controller.clean,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Obx(
            () => Stack(
              children: [
                HistoryList(
                  wrapList: (list) => EasyRefresh(
                    header: MaterialHeader(
                      completeDuration: const Duration(milliseconds: 400),
                    ),
                    controller: controller.easyRefreshController,
                    scrollController: controller.scrollController,
                    firstRefresh: true,
                    onRefresh: controller.refreshData,
                    child: list,
                  ),
                  controller: controller.scrollController,
                  items: controller.list.toList(),
                  itemBuilder: (_, item) {
                    var site = Sites.allSites[item.siteId];
                    return Dismissible(
                      key: ValueKey(item.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Colors.red,
                        padding: AppStyle.edgeInsetsA12,
                        alignment: Alignment.centerRight,
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      confirmDismiss: (direction) async {
                        if (await Utils.showAlertDialog(
                          "确定要删除此记录吗?",
                          title: "删除记录",
                        )) {
                          await controller.removeItem(item);
                        }
                        // Storage success removes the row; a failure leaves it visible.
                        return false;
                      },
                      child: Obx(
                        () => HistoryRow(
                          item: item,
                          site: site,
                          status: controller.liveStatusMap[item.id] ?? 0,
                          onTap: site == null
                              ? null
                              : () {
                                  AppNavigator.toLiveRoomDetail(
                                    site: site,
                                    roomId: item.roomId,
                                  );
                                },
                          onLongPress: () async {
                            var result = await Utils.showAlertDialog(
                              "确定要删除此记录吗?",
                              title: "删除记录",
                            );
                            if (!result) {
                              return;
                            }
                            controller.removeItem(item);
                          },
                        ),
                      ),
                    );
                  },
                ),
                if (controller.pageEmpty.value)
                  AppEmptyWidget(onRefresh: controller.refreshData),
                if (controller.pageError.value)
                  AppErrorWidget(
                    errorMsg: controller.errorMsg.value,
                    onRefresh: controller.refreshData,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
