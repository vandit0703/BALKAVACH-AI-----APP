import 'package:flutter/foundation.dart';

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
      );

  final String title;
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
              (item) => DailyMissionAssignment.fromJson(
                item as Map<String, dynamic>,
              ),
            )
            .toList(),
      );

  final DateTime localDate;
  final String timezone;
  final String ageBand;
  final String? selectedAssignmentId;
  final List<DailyMissionAssignment> choices;
}
