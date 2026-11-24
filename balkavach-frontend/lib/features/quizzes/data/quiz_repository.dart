import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/json_utils.dart';
import '../../authentication/presentation/session_controller.dart';

List<String> _ids(Object? value) =>
    (value as List<dynamic>? ?? const []).cast<String>();

/// Child-facing quiz status: `pending`, `in_progress`, `attempted`, `passed`.
enum QuizStatus {
  pending,
  inProgress,
  attempted,
  passed;

  static QuizStatus parse(Object? raw) => switch (raw) {
    'in_progress' => inProgress,
    'attempted' => attempted,
    'passed' => passed,
    _ => pending,
  };

  bool get isDone => this == attempted || this == passed;
}

/// `ChildQuizSummary`.
@immutable
class QuizSummary {
  const QuizSummary({
    required this.id,
    required this.title,
    required this.subject,
    required this.difficulty,
    required this.questionCount,
    required this.passPercent,
    required this.starReward,
    required this.xpReward,
    required this.allowRetry,
    required this.status,
    required this.attempts,
    required this.rewardClaimed,
    required this.canStart,
    this.description,
    this.bestScorePercent,
  });

  factory QuizSummary.fromJson(Map<String, dynamic> json) => QuizSummary(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String?,
    subject: json['subject'] as String? ?? 'general',
    difficulty: json['difficulty'] as String? ?? 'easy',
    questionCount: (json['question_count'] as num).toInt(),
    passPercent: (json['pass_percent'] as num).toInt(),
    starReward: (json['star_reward'] as num?)?.toInt() ?? 0,
    xpReward: (json['xp_reward'] as num?)?.toInt() ?? 0,
    allowRetry: json['allow_retry'] as bool? ?? true,
    status: QuizStatus.parse(json['status']),
    attempts: (json['attempts'] as num?)?.toInt() ?? 0,
    bestScorePercent: (json['best_score_percent'] as num?)?.toInt(),
    rewardClaimed: json['reward_claimed'] as bool? ?? false,
    canStart: json['can_start'] as bool? ?? true,
  );

  final String id;
  final String title;
  final String? description;
  final String subject;

  /// `easy`, `medium` or `hard`.
  final String difficulty;
  final int questionCount;
  final int passPercent;
  final int starReward;
  final int xpReward;
  final bool allowRetry;
  final QuizStatus status;
  final int attempts;
  final int? bestScorePercent;

  /// The server already paid this quiz's reward to this child.
  final bool rewardClaimed;
  final bool canStart;

  /// A reward the child could still earn (never shown once claimed).
  bool get hasOpenReward => !rewardClaimed && (starReward > 0 || xpReward > 0);
}

@immutable
class QuizOption {
  const QuizOption({required this.id, required this.text});

  factory QuizOption.fromJson(Map<String, dynamic> json) =>
      QuizOption(id: json['id'] as String, text: json['text'] as String);

  final String id;
  final String text;
}

@immutable
class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.position,
    required this.prompt,
    required this.type,
    required this.options,
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> json) => QuizQuestion(
    id: json['id'] as String,
    position: (json['position'] as num).toInt(),
    prompt: json['prompt'] as String,
    type: json['question_type'] as String,
    options: parseJsonList(
      json['options'] as List<dynamic>?,
      QuizOption.fromJson,
    ),
  );

  final String id;
  final int position;
  final String prompt;

  /// `single`, `multiple` or `true_false`.
  final String type;
  final List<QuizOption> options;

  bool get isMultiple => type == 'multiple';
}

/// `AttemptStarted`: the questions carry no answers.
@immutable
class QuizAttempt {
  const QuizAttempt({
    required this.id,
    required this.quizId,
    required this.title,
    required this.passPercent,
    required this.starReward,
    required this.xpReward,
    required this.questions,
  });

  factory QuizAttempt.fromJson(Map<String, dynamic> json) => QuizAttempt(
    id: json['attempt_id'] as String,
    quizId: json['quiz_id'] as String,
    title: json['title'] as String,
    passPercent: (json['pass_percent'] as num).toInt(),
    starReward: (json['star_reward'] as num?)?.toInt() ?? 0,
    xpReward: (json['xp_reward'] as num?)?.toInt() ?? 0,
    questions: parseJsonList(
      json['questions'] as List<dynamic>?,
      QuizQuestion.fromJson,
    ),
  );

  final String id;
  final String quizId;
  final String title;
  final int passPercent;
  final int starReward;
  final int xpReward;
  final List<QuizQuestion> questions;
}

@immutable
class ReviewOption {
  const ReviewOption({
    required this.id,
    required this.text,
    required this.isCorrect,
  });

  factory ReviewOption.fromJson(Map<String, dynamic> json) => ReviewOption(
    id: json['id'] as String,
    text: json['text'] as String,
    isCorrect: json['is_correct'] as bool? ?? false,
  );

  final String id;
  final String text;
  final bool isCorrect;
}

@immutable
class ReviewItem {
  const ReviewItem({
    required this.questionId,
    required this.position,
    required this.prompt,
    required this.selectedOptionIds,
    required this.isCorrect,
    required this.options,
    this.explanation,
  });

  factory ReviewItem.fromJson(Map<String, dynamic> json) => ReviewItem(
    questionId: json['question_id'] as String,
    position: (json['position'] as num).toInt(),
    prompt: json['prompt'] as String,
    explanation: json['explanation'] as String?,
    selectedOptionIds: _ids(json['selected_option_ids']),
    isCorrect: json['is_correct'] as bool? ?? false,
    options: parseJsonList(
      json['options'] as List<dynamic>?,
      ReviewOption.fromJson,
    ),
  );

  final String questionId;
  final int position;
  final String prompt;
  final String? explanation;
  final List<String> selectedOptionIds;
  final bool isCorrect;
  final List<ReviewOption> options;
}

/// `AttemptResult`: everything shown on the result screen comes from the
/// server; the app never computes a score or a reward.
@immutable
class QuizResult {
  const QuizResult({
    required this.attemptId,
    required this.quizId,
    required this.quizTitle,
    required this.totalQuestions,
    required this.correctCount,
    required this.incorrectCount,
    required this.scorePercent,
    required this.passed,
    required this.passPercent,
    required this.starsAwarded,
    required this.xpAwarded,
    required this.canRetry,
    this.review,
  });

  factory QuizResult.fromJson(Map<String, dynamic> json) => QuizResult(
    attemptId: json['attempt_id'] as String,
    quizId: json['quiz_id'] as String,
    quizTitle: json['quiz_title'] as String,
    totalQuestions: (json['total_questions'] as num).toInt(),
    correctCount: (json['correct_count'] as num).toInt(),
    incorrectCount: (json['incorrect_count'] as num).toInt(),
    scorePercent: (json['score_percent'] as num).toInt(),
    passed: json['passed'] as bool? ?? false,
    passPercent: (json['pass_percent'] as num).toInt(),
    starsAwarded: (json['stars_awarded'] as num?)?.toInt() ?? 0,
    xpAwarded: (json['xp_awarded'] as num?)?.toInt() ?? 0,
    canRetry: json['can_retry'] as bool? ?? false,
    review: json['review'] == null
        ? null
        : parseJsonList(json['review'] as List<dynamic>?, ReviewItem.fromJson),
  );

  final String attemptId;
  final String quizId;
  final String quizTitle;
  final int totalQuestions;
  final int correctCount;
  final int incorrectCount;
  final int scorePercent;
  final bool passed;
  final int passPercent;

  /// What the server paid for *this* attempt: zero on a retake.
  final int starsAwarded;
  final int xpAwarded;
  final bool canRetry;

  /// Null when the quiz changed after the attempt.
  final List<ReviewItem>? review;
}

@immutable
class QuizHistoryItem {
  const QuizHistoryItem({
    required this.attemptId,
    required this.quizId,
    required this.quizTitle,
    required this.scorePercent,
    required this.correctCount,
    required this.totalQuestions,
    required this.passed,
    required this.submittedAt,
  });

  factory QuizHistoryItem.fromJson(Map<String, dynamic> json) =>
      QuizHistoryItem(
        attemptId: json['attempt_id'] as String,
        quizId: json['quiz_id'] as String,
        quizTitle: json['quiz_title'] as String,
        scorePercent: (json['score_percent'] as num).toInt(),
        correctCount: (json['correct_count'] as num).toInt(),
        totalQuestions: (json['total_questions'] as num).toInt(),
        passed: json['passed'] as bool? ?? false,
        submittedAt: DateTime.parse(json['submitted_at'] as String),
      );

  final String attemptId;
  final String quizId;
  final String quizTitle;
  final int scorePercent;
  final int correctCount;
  final int totalQuestions;
  final bool passed;
  final DateTime submittedAt;
}

/// Verified contract: `app/api/v1/quizzes.py`.
class QuizRepository {
  QuizRepository(this._dio);

  final Dio _dio;

  /// `GET /api/v1/quizzes`.
  Future<List<QuizSummary>> list() => guardApi(() async {
    final response = await _dio.get<List<dynamic>>('/api/v1/quizzes');
    return parseJsonList(response.data, QuizSummary.fromJson);
  });

  /// `GET /api/v1/quizzes/{id}`.
  Future<QuizSummary> get(String quizId) => guardApi(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/quizzes/$quizId',
    );
    return QuizSummary.fromJson(response.data!);
  });

  /// `POST /api/v1/quizzes/{id}/attempts`: starts, or resumes, the open
  /// attempt. 409 `retry_not_allowed`.
  Future<QuizAttempt> start(String quizId) => guardApi(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/quizzes/$quizId/attempts',
    );
    return QuizAttempt.fromJson(response.data!);
  });

  /// `POST /api/v1/quizzes/attempts/{id}/submit`: only option ids go up; the
  /// server grades. 409 `quiz_changed` / `quiz_unavailable`.
  Future<QuizResult> submit(
    String attemptId,
    Map<String, List<String>> answers,
  ) => guardApi(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/quizzes/attempts/$attemptId/submit',
      data: {
        'answers': [
          for (final entry in answers.entries)
            {'question_id': entry.key, 'option_ids': entry.value},
        ],
      },
    );
    return QuizResult.fromJson(response.data!);
  });

  /// `GET /api/v1/quizzes/attempts/{id}`.
  Future<QuizResult> result(String attemptId) => guardApi(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/quizzes/attempts/$attemptId',
    );
    return QuizResult.fromJson(response.data!);
  });

  /// `GET /api/v1/quizzes/history`, newest first.
  Future<List<QuizHistoryItem>> history() => guardApi(() async {
    final response = await _dio.get<List<dynamic>>('/api/v1/quizzes/history');
    return parseJsonList(response.data, QuizHistoryItem.fromJson);
  });
}

final quizRepositoryProvider = Provider<QuizRepository>(
  (ref) => QuizRepository(ref.watch(apiDioProvider)),
);

final quizzesProvider = FutureProvider<List<QuizSummary>>((ref) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(quizRepositoryProvider).list();
});

final quizProvider = FutureProvider.family<QuizSummary, String>((ref, id) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(quizRepositoryProvider).get(id);
});

final quizHistoryProvider = FutureProvider<List<QuizHistoryItem>>((ref) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(quizRepositoryProvider).history();
});

/// A stored result, for reopening one from the history. Reading it never pays
/// anything: rewards are granted only by the submit call.
final quizResultProvider = FutureProvider.family<QuizResult, String>((
  ref,
  attemptId,
) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(quizRepositoryProvider).result(attemptId);
});
