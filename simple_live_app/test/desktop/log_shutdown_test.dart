import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:simple_live_app/app/log.dart';

void main() {
  test('terminal shutdown prevents every lazy writer creation path', () async {
    await Log.shutdown();
    expect(Log.logFileWriter, isNull);
    Log.writeLog('late native error', Level.error);
    Log.initWriter();
    Log.setDetailed(true);
    expect(await Log.logFiles(), isEmpty);
    expect(Log.logFileWriter, isNull);
    // Failed window destruction can explicitly permit logging again; ordinary
    // callbacks cannot unfreeze logging themselves.
    Log.resume();
  });
}
