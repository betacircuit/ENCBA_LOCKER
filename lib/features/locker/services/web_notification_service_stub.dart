class WebNotificationService {
  Future<bool> enableAndTest() async => false;
  Future<bool> isEnabled() async => false;
  Future<void> disable() async {}
  Future<bool> show(String title, String body) async => false;
  Future<bool> scheduleAt(
    String id,
    String title,
    String body,
    DateTime scheduledAt,
  ) async => false;
}
