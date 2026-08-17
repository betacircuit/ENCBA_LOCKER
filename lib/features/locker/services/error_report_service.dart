import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> sendErrorReport({
  required SupabaseClient client,
  required String body,
}) async {
  await client.functions.invoke('send-error-report', body: {'body': body});
}

Uri buildErrorReportUri({required String body, required bool isWeb}) {
  if (isWeb) {
    return Uri.https('mail.google.com', '/mail/', {
      'view': 'cm',
      'fs': '1',
      'to': 'legojmon@snu.ac.kr',
      'su': 'ENCBA LOCKER 오류 제보',
      'body': body,
    });
  }

  return Uri(
    scheme: 'mailto',
    path: 'legojmon@snu.ac.kr',
    queryParameters: {'subject': 'ENCBA LOCKER 오류 제보', 'body': body},
  );
}
