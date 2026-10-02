import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/core/services/cloud_service.dart';

void main() {
  test('cloud address typing slips are corrected or rejected', () {
    const ok = 'http://10.219.3.116:3001/api';
    for (final typed in [
      'http:10.219.3.116 :3001', 'http://10.219.3.116:3001', 'HTTP://10.219.3.116:3001/',
      'http:/10.219.3.116:3001/api', ' http://10.219.3.116:3001/api/ ',
    ]) {
      expect(CloudService.normaliseUrl(typed), ok, reason: typed);
    }
    expect(CloudService.normaliseUrl('api.example.com'), 'https://api.example.com/api');
    expect(CloudService.normaliseUrl('https://api.example.com'), 'https://api.example.com/api');
    for (final bad in ['', 'http:', 'hello', 'http://']) {
      expect(CloudService.normaliseUrl(bad), '', reason: bad);
    }
  });
}
