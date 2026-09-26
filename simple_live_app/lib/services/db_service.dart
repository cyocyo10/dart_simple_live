import 'package:get/get.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/constant.dart';
import 'storage/app_box.dart';
import 'storage/app_data_store.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';

class DBService extends GetxService {
  static DBService get instance => Get.find<DBService>();
  late AppBox<History> historyBox;
  late AppBox<FollowUser> followBox;
  late AppBox<FollowUserTag> tagBox;
  final Uuid uuid = const Uuid();

  Future init() async {
    // 使用泛型 openBox，确保 TypeAdapter 正确序列化
    historyBox = await AppDataStore.instance.openBox<History>(
        "History", (v) => History.fromJson(Map<String, dynamic>.from(v)));
    followBox = await AppDataStore.instance.openBox<FollowUser>(
        "FollowUser", (v) => FollowUser.fromJson(Map<String, dynamic>.from(v)));
    tagBox = await AppDataStore.instance.openBox<FollowUserTag>("FollowUserTag",
        (v) => FollowUserTag.fromJson(Map<String, dynamic>.from(v)));
    Log.d(
      "DBService ready: follow=${followBox.length}, history=${historyBox.length}",
    );
  }

  // follow_user_tag 相关逻辑
  bool getFollowTagExist(String id) {
    return tagBox.containsKey(id);
  }

  Future<void> _editFollows(
      void Function(Map<String, FollowUser>, Map<String, FollowUserTag>)
          edit) async {
    final shared = AppDataStore.instance.shared;
    if (shared != null) {
      await shared.mutateBoxes({'followuser', 'followusertag'}, (boxes) {
        final follows = boxes['followuser']!.map((key, value) => MapEntry(
            key, FollowUser.fromJson(Map<String, dynamic>.from(value))));
        final tags = boxes['followusertag']!.map((key, value) => MapEntry(
            key, FollowUserTag.fromJson(Map<String, dynamic>.from(value))));
        edit(follows, tags);
        boxes['followuser'] =
            follows.map((key, value) => MapEntry(key, value.toJson()));
        boxes['followusertag'] =
            tags.map((key, value) => MapEntry(key, value.toJson()));
      });
    } else {
      final follows = {
        for (final item in followBox.values)
          item.id: FollowUser.fromJson(item.toJson())
      };
      final tags = {
        for (final item in tagBox.values)
          item.id: FollowUserTag.fromJson(item.toJson())
      };
      edit(follows, tags);
      await followBox.replaceAll(follows);
      await tagBox.replaceAll(tags);
      await followBox.flush();
      await tagBox.flush();
    }
    EventBus.instance.emit(Constant.kUpdateFollow, null);
  }

  Future<void> deleteFollowTag(String id) => _editFollows((follows, tags) {
        final tag = tags.remove(id);
        if (tag == null) return;
        for (final follow in follows.values) {
          if (follow.tag == tag.tag) follow.tag = '全部';
        }
      });

  Future<void> renameFollowTag(String id, String name) =>
      _editFollows((follows, tags) {
        final tag = tags[id];
        if (tag == null) throw StateError('标签已被删除，请刷新');
        name = name.trim();
        if (name.isEmpty ||
            name.length > 8 ||
            ['全部', '直播中', '回放中', '未开播'].contains(name))
          throw const FormatException('请输入 1 至 8 个字的标签名称');
        if (tags.values.any((other) => other.id != id && other.tag == name))
          throw const FormatException('标签名重复');
        final oldName = tag.tag;
        tag.tag = name;
        for (final follow in follows.values) {
          if (follow.tag == oldName) follow.tag = name;
        }
      });

  Future<void> setFollowTag(String followId, String? tagId) =>
      _editFollows((follows, tags) {
        final follow = follows[followId];
        if (follow == null) throw StateError('此直播间已取消关注，请刷新');
        final target = tagId == null ? null : tags[tagId];
        if (tagId != null && target == null) throw StateError('标签已被删除，请刷新');
        for (final tag in tags.values) {
          tag.userId.remove(followId);
        }
        target?.userId.add(followId);
        follow.tag = target?.tag ?? '全部';
      });

  Future<void> canonicalizeFollow(String oldId, FollowUser canonical) =>
      _editFollows((follows, tags) {
        final old = follows.remove(oldId);
        if (old == null) return; // Another window already unfollowed it.
        final target = follows[canonical.id] ??
            FollowUser.fromJson({
              ...old.toJson(),
              'id': canonical.id,
              'roomId': canonical.roomId,
              'userName': canonical.userName,
              'face': canonical.face,
            });
        follows[target.id] = target;
        for (final tag in tags.values) {
          tag.userId.remove(oldId);
          if (tag.tag == target.tag && !tag.userId.contains(target.id)) {
            tag.userId.add(target.id);
          }
        }
      });

  Future<void> importFollows(Map<String, FollowUser> imported) =>
      _editFollows((follows, tags) {
        for (final item in imported.values) {
          final follow = FollowUser.fromJson(item.toJson());
          for (final tag in tags.values) {
            tag.userId.remove(follow.id);
          }
          if (follow.tag != '全部') {
            final tag =
                tags.values.firstWhereOrNull((tag) => tag.tag == follow.tag) ??
                    FollowUserTag(id: uuid.v4(), tag: follow.tag, userId: []);
            if (!tag.userId.contains(follow.id)) tag.userId.add(follow.id);
            tags[tag.id] = tag;
          }
          follows[follow.id] = follow;
        }
      });

  FollowUserTag? getFollowTag(String tag) {
    return tagBox.values.firstWhereOrNull((item) => item.tag == tag);
  }

  // 判断标签名称是否重复
  bool getFollowTagExistByTag(String tag) {
    return tagBox.values.any((item) => item.tag == tag);
  }

  // 获取标签列表
  List<FollowUserTag> getFollowTagList() {
    return tagBox.values.toList();
  }

  // 修改标签
  Future updateFollowTag(FollowUserTag followTag) async {
    await tagBox.put(followTag.id, followTag);
    await tagBox.flush();
  }

  // 添加标签
  Future<FollowUserTag> addFollowTag(String name) async {
    name = name.trim();
    if (name.isEmpty || ['全部', '直播中', '回放中', '未开播'].contains(name))
      throw const FormatException('标签名不能为空或使用内置分类名称');
    if (name.length > 8) name = name.substring(0, 8);
    late FollowUserTag result;
    await _editFollows((follows, tags) {
      result = tags.values.firstWhereOrNull((tag) => tag.tag == name) ??
          FollowUserTag(id: uuid.v4(), tag: name, userId: []);
      tags[result.id] = result;
    });
    return result;
  }

  Future<void> updateFollowTagOrder(List<FollowUserTag> order) =>
      _editFollows((follows, tags) {
        final latest = Map<String, FollowUserTag>.of(tags);
        tags.clear();
        for (final item in order) {
          final current = latest.remove(item.id);
          if (current != null) tags[item.id] = current;
        }
        tags.addAll(latest); // Preserve tags added by another window.
      });

  bool getFollowExist(String id) {
    return followBox.containsKey(id);
  }

  List<FollowUser> getFollowList() {
    return followBox.values.toList();
  }

  Future addFollow(FollowUser follow) async {
    await followBox.put(follow.id, follow);
    // Windows 上确保落盘，避免进程退出后数据丢失
    await followBox.flush();
  }

  Future<void> deleteFollow(String id) => _editFollows((follows, tags) {
        follows.remove(id);
        for (final tag in tags.values) {
          tag.userId.remove(id);
        }
      });

  History? getHistory(String id) {
    if (historyBox.containsKey(id)) {
      return historyBox.get(id);
    }
    return null;
  }

  Future addOrUpdateHistory(History history) async {
    await historyBox.put(history.id, history);
    await historyBox.flush();
  }

  List<History> getHistores() {
    var his = historyBox.values.toList();
    his.sort((a, b) => b.updateTime.compareTo(a.updateTime));
    return his;
  }
}
