import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';

class PendingPage extends BasePageController<String> {
  final requests = <Completer<List<String>>>[];
  final pages = <int>[];
  @override
  Future<List<String>> getData(int page, int pageSize) {
    pages.add(page);
    final pending = Completer<List<String>>();
    requests.add(pending);
    return pending.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('refresh rejects an older search result without releasing the new gate',
      () async {
    final controller = PendingPage();
    final old = controller.refreshData();
    final fresh = controller.refreshData();
    controller.requests[0].complete(['old']);
    await old;
    expect(controller.list, isEmpty);
    expect(controller.loadding, isTrue);
    await controller.loadData();
    expect(controller.requests.length, 2);
    controller.requests[1].complete(['new']);
    await fresh;
    expect(controller.list, ['new']);
    expect(controller.currentPage, 2);
    controller.onClose();
  });
  test('duplicate load-more cannot release the in-flight request', () async {
    final controller = PendingPage();
    final first = controller.loadData();
    await controller.loadData();
    await controller.loadData();
    expect(controller.requests.length, 1);
    controller.requests.single.complete(['one']);
    await first;
    final more = controller.loadData();
    final refresh = controller.refreshData();
    controller.requests[2].complete(['fresh']);
    await refresh;
    controller.requests[1].complete(['stale page two']);
    await more;
    expect(controller.pages, [1, 2, 1]);
    expect(controller.list, ['fresh']);
    controller.onClose();
  });
  test('clear or dispose prevents late list mutations', () async {
    final controller = PendingPage();
    final pending = controller.refreshData();
    controller.cancelPendingLoad();
    controller.requests.single.complete(['cancelled']);
    await pending;
    expect(controller.list, isEmpty);
    final closed = controller.loadData();
    controller.onClose();
    controller.requests.last.complete(['closed']);
    await closed;
    expect(controller.list, isEmpty);
  });
}
