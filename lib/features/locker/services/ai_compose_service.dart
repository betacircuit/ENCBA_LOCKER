import 'package:encba_locker/features/locker/domain/locker_models.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// AI가 채워 준 값 가운데, 요청에 없어서 사람이 정해 줘야 하는 항목.
@immutable
class AiFollowUpQuestion {
  const AiFollowUpQuestion({required this.field, required this.question});

  final String field;
  final String question;

  static AiFollowUpQuestion? tryParse(Object? value) {
    if (value is! Map) return null;
    final field = value['field'];
    final question = value['question'];
    if (field is! String || field.isEmpty) return null;
    return AiFollowUpQuestion(
      field: field,
      question: question is String && question.isNotEmpty
          ? question
          : '$field 값을 정해 주세요.',
    );
  }
}

/// AI가 만든 일정 하나. 저장 전에 화면에서 확인·수정할 수 있게 값만 담는다.
@immutable
class AiEventDraft {
  const AiEventDraft({
    required this.kind,
    required this.title,
    required this.start,
    required this.end,
    required this.place,
    required this.targetTeam,
    required this.memo,
  });

  final EventKind kind;
  final String title;
  final DateTime start;
  final DateTime end;
  final String place;
  final String targetTeam;
  final String memo;

  static AiEventDraft? tryParse(Object? value) {
    if (value is! Map) return null;
    final start = DateTime.tryParse(value['start'] as String? ?? '');
    final end = DateTime.tryParse(value['end'] as String? ?? '');
    if (start == null || end == null || !end.isAfter(start)) return null;
    final kind = EventKind.values
        .where((item) => item.name == (value['kind'] as String? ?? ''))
        .firstOrNull;
    if (kind == null) return null;
    final targetTeam = value['targetTeam'] as String? ?? '전체';
    return AiEventDraft(
      kind: kind,
      title: (value['title'] as String? ?? '').trim(),
      start: start,
      end: end,
      place: (value['place'] as String? ?? '').trim(),
      targetTeam: const ['전체', 'ENCBA', 'BEN', '신입생'].contains(targetTeam)
          ? targetTeam
          : '전체',
      memo: (value['memo'] as String? ?? '').trim(),
    );
  }
}

/// 일정 채우기 결과.
@immutable
class AiEventPlan {
  const AiEventPlan({
    required this.summary,
    required this.events,
    required this.questions,
  });

  final String summary;
  final List<AiEventDraft> events;
  final List<AiFollowUpQuestion> questions;
}

/// 공지 채우기 결과. 값이 비어 있는 항목은 AI가 정하지 못한 것이다.
@immutable
class AiAnnouncementDraft {
  const AiAnnouncementDraft({
    required this.summary,
    required this.title,
    required this.body,
    required this.pinned,
    required this.pollQuestion,
    required this.pollOptions,
    required this.questions,
  });

  final String summary;
  final String title;
  final String body;
  final bool pinned;
  final String pollQuestion;
  final List<String> pollOptions;
  final List<AiFollowUpQuestion> questions;
}

/// AI 채우기 실패 사유. 화면에 그대로 보여 줄 수 있는 한국어 문장이다.
class AiComposeException implements Exception {
  const AiComposeException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// `ai-compose` 엣지 함수를 부른다. OpenRouter API 키는 그 함수의 환경변수에만
/// 있고 앱에는 들어오지 않는다. 앱 빌드에 키를 넣으면 브라우저에서 그대로
/// 읽히기 때문이다.
class AiComposeService {
  AiComposeService([SupabaseClient? client])
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<AiEventPlan> composeEvents({
    required String prompt,
    Map<String, dynamic> context = const {},
  }) async {
    final result = await _invoke(
      kind: 'events',
      prompt: prompt,
      context: context,
    );
    final events = <AiEventDraft>[
      for (final raw in (result['events'] as List? ?? const []))
        ?AiEventDraft.tryParse(raw),
    ];
    if (events.isEmpty) {
      throw const AiComposeException('만들 수 있는 일정을 찾지 못했습니다. 조금 더 구체적으로 적어 주세요.');
    }
    return AiEventPlan(
      summary: result['summary'] as String? ?? '',
      events: events..sort((a, b) => a.start.compareTo(b.start)),
      questions: _questions(result),
    );
  }

  Future<AiAnnouncementDraft> composeAnnouncement({
    required String prompt,
    Map<String, dynamic> context = const {},
  }) async {
    final result = await _invoke(
      kind: 'announcement',
      prompt: prompt,
      context: context,
    );
    final poll = result['poll'];
    final options = <String>[
      for (final option in (poll is Map ? poll['options'] as List? : null) ??
          const [])
        if (option is String && option.trim().isNotEmpty) option.trim(),
    ];
    return AiAnnouncementDraft(
      summary: result['summary'] as String? ?? '',
      title: (result['title'] as String? ?? '').trim(),
      body: (result['body'] as String? ?? '').trim(),
      pinned: result['pinned'] as bool? ?? false,
      pollQuestion: poll is Map
          ? (poll['question'] as String? ?? '').trim()
          : '',
      pollOptions: options.length >= 2 ? options : const [],
      questions: _questions(result),
    );
  }

  List<AiFollowUpQuestion> _questions(Map<String, dynamic> result) => [
    for (final raw in (result['questions'] as List? ?? const []))
      ?AiFollowUpQuestion.tryParse(raw),
  ];

  Future<Map<String, dynamic>> _invoke({
    required String kind,
    required String prompt,
    required Map<String, dynamic> context,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'ai-compose',
        body: {'kind': kind, 'prompt': prompt, 'context': context},
      );
      final data = response.data;
      if (data is Map && data['result'] is Map) {
        return Map<String, dynamic>.from(data['result'] as Map);
      }
      final message = data is Map ? data['error'] : null;
      throw AiComposeException(
        message is String && message.isNotEmpty
            ? message
            : 'AI 응답을 받지 못했습니다.',
      );
    } on FunctionException catch (error) {
      final details = error.details;
      final message = details is Map ? details['error'] : null;
      throw AiComposeException(
        message is String && message.isNotEmpty
            ? message
            : 'AI 채우기를 사용할 수 없습니다. 잠시 뒤 다시 시도해 주세요.',
      );
    } on AiComposeException {
      rethrow;
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA ai compose failed: $error\n$stackTrace');
      throw const AiComposeException('AI 채우기 요청이 실패했습니다. 연결 상태를 확인해 주세요.');
    }
  }
}
