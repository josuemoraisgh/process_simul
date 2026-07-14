import 'package:flutter_test/flutter_test.dart';
import 'package:process_simul/application/notifiers/settings_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('settings reject invalid service ports and simulation periods', () {
    expect(
      () => const AppSettings(hartServerPort: 0).validate(),
      throwsRangeError,
    );
    expect(
      () => const AppSettings(modbusPort: 65536).validate(),
      throwsRangeError,
    );
    expect(
      () => const AppSettings(tfStepMs: 9).validate(),
      throwsRangeError,
    );
    expect(
      () => const AppSettings(hartTcpHost: 'not an ip').validate(),
      throwsFormatException,
    );
    expect(
      () => const AppSettings(hartTcpHost: '0.0.0.0').validate(),
      returnsNormally,
    );
    expect(() => const AppSettings().validate(), returnsNormally);
  });

  test('load replaces unsafe persisted numeric settings with defaults',
      () async {
    SharedPreferences.setMockInitialValues({
      'hart_server_port': -1,
      'modbus_port': 70000,
      'tf_step_ms': 0,
      'hart_tcp_host': 'invalid',
    });
    final notifier = SettingsNotifier();

    await notifier.load();

    expect(notifier.state.hartServerPort, 5094);
    expect(notifier.state.modbusPort, 502);
    expect(notifier.state.tfStepMs, 50);
    expect(notifier.state.hartTcpHost, '127.0.0.1');
  });
}
