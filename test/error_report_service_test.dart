import 'package:encba_locker/features/locker/services/error_report_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('웹 오류 제보는 Gmail 작성창에 수신자·제목·본문을 채운다', () {
    final uri = buildErrorReportUri(body: '재현 단계', isWeb: true);

    expect(uri.scheme, 'https');
    expect(uri.host, 'mail.google.com');
    expect(uri.path, '/mail/');
    expect(uri.queryParameters['to'], 'legojmon@snu.ac.kr');
    expect(uri.queryParameters['su'], 'ENCBA LOCKER 오류 제보');
    expect(uri.queryParameters['body'], '재현 단계');
  });

  test('앱 오류 제보는 기본 메일 앱용 mailto 링크를 만든다', () {
    final uri = buildErrorReportUri(body: '재현 단계', isWeb: false);

    expect(uri.scheme, 'mailto');
    expect(uri.path, 'legojmon@snu.ac.kr');
    expect(uri.queryParameters['subject'], 'ENCBA LOCKER 오류 제보');
    expect(uri.queryParameters['body'], '재현 단계');
  });
}
