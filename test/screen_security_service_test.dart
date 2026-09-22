import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linka/services/screen_security_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('linka/screen_security');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'isCaptured' ? false : null;
    });
  });

  test('secure flag follows the outermost protect/release pair', () async {
    await ScreenSecurityService.protect();
    await ScreenSecurityService.protect(); // nested screen: no second call
    await ScreenSecurityService.release();
    expect(calls.where((c) => c.method == 'setSecure').map((c) => c.arguments),
        [
          {'secure': true},
        ]);
    await ScreenSecurityService.release();
    expect(calls.last.arguments, {'secure': false});
  });

  test('capture events from iOS update the notifier', () async {
    await ScreenSecurityService.protect();
    Future<void> send(bool on) => messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(MethodCall('captureChanged', on)),
          (_) {},
        );
    await send(true);
    expect(ScreenSecurityService.captured.value, isTrue);
    await send(false);
    expect(ScreenSecurityService.captured.value, isFalse);
    await ScreenSecurityService.release();
  });
}
