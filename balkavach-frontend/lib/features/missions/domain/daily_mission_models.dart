import 'package:flutter/foundation.dart';

import 'mission_titles.dart';

@immutable
class DailyMissionContent {
  const DailyMissionContent({
    required this.title,
    required this.description,
    required this.instructions,
    required this.requiredMaterials,
    required this.durationMinutes,
    required this.safetyInstructions,
    required this.completionCriteria,
    required this.missionType,
    required this.theme,
    required this.starReward,
    required this.xpReward,
    required this.isSurprise,
    required this.locale,
    this.learningObjective,
    this.steps = const [],
    this.materials = const [],
    this.observationGuidance,
    this.submissionRequirements,
    this.instructionStatus = 'incomplete',
  });

  factory DailyMissionContent.fromJson(Map<String, dynamic> json) =>
      DailyMissionContent(
        title: json['title'] as String,
        description: json['description'] as String,
        instructions: json['instructions'] as String,
        requiredMaterials: (json['required_materials'] as List<dynamic>? ?? [])
            .map((item) => '$item')
            .toList(),
        durationMinutes: json['duration_minutes'] as int,
        safetyInstructions: json['safety_instructions'] as String,
        completionCriteria: json['completion_criteria'] as String,
        missionType: json['mission_type'] as String,
        theme: json['theme'] as String,
        starReward: json['star_reward'] as int,
        xpReward: json['xp_reward'] as int,
        isSurprise: json['is_surprise'] as bool? ?? false,
        locale: json['locale'] as String? ?? 'en',
        learningObjective: _text(json['learning_objective']),
        steps: _steps(json),
        materials: json['materials'] is List
            ? (json['materials'] as List<dynamic>)
                  .map((item) => '$item'.trim())
                  .where((item) => item.isNotEmpty)
                  .toList()
            : (json['required_materials'] as List<dynamic>? ?? [])
                  .map((item) => '$item'.trim())
                  .where((item) => item.isNotEmpty)
                  .toList(),
        observationGuidance: _text(json['observation_guidance']),
        submissionRequirements: _text(json['submission_requirements']),
        instructionStatus:
            json['instruction_status'] as String? ??
            (_steps(json).length >= 2 ? 'ready' : 'incomplete'),
      );

  static String? _text(Object? value) {
    final text = value is String ? value.trim() : '';
    return text.isEmpty ? null : text;
  }

  static final _numbered = RegExp(r'^\s*\d{1,2}[.)]\s+(.+?)\s*$');

  /// The server's `steps`; for an older server the numbered lines already in
  /// `instructions` are extracted (nothing is invented, so placeholder text
  /// yields no steps).
  static List<String> _steps(Map<String, dynamic> json) {
    final raw = json['steps'];
    if (raw is List) {
      return raw
          .whereType<String>()
          .map((step) => step.trim())
          .where((step) => step.isNotEmpty)
          .toList();
    }
    return [
      for (final line in ((json['instructions'] as String?) ?? '').split('\n'))
        if (_numbered.firstMatch(line) case final match?) match.group(1)!,
    ];
  }

  final String title;

  /// The title as a child reads it (no age range). [title] stays as stored.
  String get childTitle => childFacingMissionTitle(title);
  final String description;
  final String instructions;
  final List<String> requiredMaterials;
  final int durationMinutes;
  final String safetyInstructions;
  final String completionCriteria;
  final String missionType;
  final String theme;
  final int starReward;
  final int xpReward;
  final bool isSurprise;
  final String locale;

  /// "What you will learn": null when none was written (never filler text).
  final String? learningObjective;

  /// The numbered actions, in order. Empty when the mission has no real steps.
  final List<String> steps;

  /// What the child needs (may be the explicit "Nothing needed").
  final List<String> materials;
  final String? observationGuidance;
  final String? submissionRequirements;

  /// `ready` or `incomplete`; incomplete missions show an honest notice
  /// instead of pretending to explain the activity.
  final String instructionStatus;

  bool get instructionsReady =>
      instructionStatus == 'ready' && steps.isNotEmpty;
}

@immutable
class DailyMissionAssignment {
  const DailyMissionAssignment({
    required this.id,
    required this.localDate,
    required this.choiceSlot,
    required this.ageBand,
    required this.status,
    required this.content,
    this.taskId,
  });

  factory DailyMissionAssignment.fromJson(Map<String, dynamic> json) =>
      DailyMissionAssignment(
        id: json['id'] as String,
        localDate: DateTime.parse(json['local_date'] as String),
        choiceSlot: json['choice_slot'] as int,
        ageBand: json['age_band'] as String,
        status: json['status'] as String,
        taskId: json['task_id'] as String?,
        content: DailyMissionContent.fromJson(
          json['content'] as Map<String, dynamic>,
        ),
      );

  final String id;
  final DateTime localDate;
  final int choiceSlot;
  final String ageBand;
  final String status;
  final String? taskId;
  final DailyMissionContent content;

  bool get isSelectable => status == 'available';
}

@immutable
class DailyMissionChoices {
  const DailyMissionChoices({
    required this.localDate,
    required this.timezone,
    required this.ageBand,
    required this.choices,
    this.selectedAssignmentId,
  });

  factory DailyMissionChoices.fromJson(Map<String, dynamic> json) =>
      DailyMissionChoices(
        localDate: DateTime.parse(json['local_date'] as String),
        timezone: json['timezone'] as String,
        ageBand: json['age_band'] as String,
        selectedAssignmentId: json['selected_assignment_id'] as String?,
        choices: (json['choices'] as List<dynamic>)
            .map(
              (item) =>
                  DailyMissionAssignment.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
      );

  final DateTime localDate;
  final String timezone;
  final String ageBand;
  final String? selectedAssignmentId;
  final List<DailyMissionAssignment> choices;
}
