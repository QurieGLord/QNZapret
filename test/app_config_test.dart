import 'package:flutter_test/flutter_test.dart';
import 'package:nzapret_desktop/src/models/app_config.dart';

void main() {
  test('builds a profile with bundled list and payload paths', () {
    final profile = AppConfig.defaults.buildProfile('/tmp/nzapret-runtime');

    expect(profile, contains('--qnum=200'));
    expect(profile, contains('/tmp/nzapret-runtime/lists/list-general.txt'));
    expect(profile, contains('/tmp/nzapret-runtime/lists/list-google.txt'));
    expect(
      profile,
      contains(
        '/tmp/nzapret-runtime/payloads/tls_clienthello_www_google_com.bin',
      ),
    );
  });
}
