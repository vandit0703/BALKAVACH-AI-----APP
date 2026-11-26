import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';

/// How Panda should look while saying a reply. Sent by the server.
enum PandaReplyMood { talking, happy, curious, sleepy, concerned }

/// Topic chips the server suggests after a reply.
enum PandaSuggestion { mission, video, joke, fact, draw, stars }

/// One reply from `POST /api/v1/companion/chat`
/// (`balkavach-backend/app/schemas/companion.py`).
class PandaChatReply {
  const PandaChatReply({
    required this.text,
    required this.locale,
    required this.mood,
    required this.intent,
    this.followUp,
    this.redirected = false,
    this.suggestions = const [],
  });

  factory PandaChatReply.fromJson(Map<String, dynamic> json) => PandaChatReply(
    text: json['reply'] as String,
    locale: json['locale'] as String,
    mood: PandaReplyMood.values.firstWhere(
      (m) => m.name == json['mood'],
      orElse: () => PandaReplyMood.talking,
    ),
    intent: json['intent'] as String,
    followUp: json['follow_up'] as String?,
    redirected: json['safety'] == 'redirected',
    suggestions: [
      for (final key in (json['suggestions'] as List<dynamic>? ?? const []))
        ...PandaSuggestion.values.where((s) => s.name == key),
    ],
  );

  final String text;
  final String locale;
  final PandaReplyMood mood;
  final String intent;
  final String? followUp;

  /// The server steered away from an unsafe or private topic.
  final bool redirected;
  final List<PandaSuggestion> suggestions;
}

/// Sends what the child said to Panda's server-side conversation engine.
/// No provider key or AI service is involved on the device.
class CompanionChatRepository {
  CompanionChatRepository(this._dio);

  final Dio _dio;

  static const timeout = Duration(seconds: 10);

  Future<PandaChatReply> chat({
    required String text,
    required String locale,
    required String turnId,
    String? contextIntent,
    bool voice = false,
    bool onDevice = false,
  }) => guardApi(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/companion/chat',
      data: {
        'text': text,
        'locale': locale,
        'turn_id': turnId,
        'context_intent': ?contextIntent,
        // Voice turns need a parent's consent; the server refuses them
        // otherwise (403 `panda_voice_consent_required`).
        'input': voice ? 'voice' : 'text',
        // Which recogniser heard it. On-device turns need no consent record
        // (unless a parent turned voice off); cloud turns need consent.
        if (voice) 'speech': onDevice ? 'on_device' : 'cloud',
      },
      options: Options(sendTimeout: timeout, receiveTimeout: timeout),
    );
    return PandaChatReply.fromJson(response.data!);
  });

  /// `GET /api/v1/companion/voice-consent`: whether a parent agreed to the
  /// microphone for this child.
  Future<bool> voiceConsent() async => (await voiceConsentStatus()).granted;

  /// `GET /api/v1/companion/voice-consent`: the parent's agreement (needed for
  /// the cloud recogniser) and whether a parent turned voice off altogether
  /// (which stops the on-device recogniser too). Older servers send no
  /// `refused`; it then reads as false.
  Future<PandaVoiceConsent> voiceConsentStatus() => guardApi(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/companion/voice-consent',
      options: Options(sendTimeout: timeout, receiveTimeout: timeout),
    );
    return PandaVoiceConsent(
      granted: response.data?['granted'] == true,
      refused: response.data?['refused'] == true,
    );
  });
}

/// The server's view of Talk to Panda's microphone for this child.
@immutable
class PandaVoiceConsent {
  const PandaVoiceConsent({required this.granted, this.refused = false});

  /// A parent agreed (needed for the cloud recogniser).
  final bool granted;

  /// A parent turned voice off: no microphone at all.
  final bool refused;
}

/// The server's code when a voice turn arrives without parental consent.
const kPandaVoiceConsentRequired = 'panda_voice_consent_required';

final companionChatRepositoryProvider = Provider<CompanionChatRepository>(
  (ref) => CompanionChatRepository(ref.watch(apiDioProvider)),
);

final _random = Random.secure();

/// A random RFC 4122 version-4 id for one conversation turn.
String newTurnId() {
  final b = List<int>.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
