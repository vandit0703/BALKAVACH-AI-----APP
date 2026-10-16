import 'package:flutter/foundation.dart';

/// `FamilyPublic`.
@immutable
class Family {
  const Family({
    required this.id,
    required this.familyName,
    required this.createdBy,
    required this.createdAt,
  });

  factory Family.fromJson(Map<String, dynamic> json) => Family(
    id: json['id'] as String,
    familyName: json['family_name'] as String,
    createdBy: json['created_by'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String id;
  final String familyName;
  final String createdBy;
  final DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      other is Family && other.id == id && other.familyName == familyName;

  @override
  int get hashCode => Object.hash(id, familyName);
}

/// `ChildPublic`.
@immutable
class ChildProfile {
  const ChildProfile({
    required this.id,
    required this.userId,
    required this.familyId,
    required this.displayName,
    required this.isActive,
    required this.createdAt,
    this.dateOfBirth,
    this.avatarUrl,
  });

  factory ChildProfile.fromJson(Map<String, dynamic> json) => ChildProfile(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    familyId: json['family_id'] as String,
    displayName: json['display_name'] as String,
    dateOfBirth: json['date_of_birth'] == null
        ? null
        : DateTime.parse(json['date_of_birth'] as String),
    avatarUrl: json['avatar_url'] as String?,
    isActive: json['is_active'] as bool? ?? true,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String id;
  final String userId;
  final String familyId;
  final String displayName;
  final DateTime? dateOfBirth;
  final String? avatarUrl;
  final bool isActive;
  final DateTime createdAt;

  int? ageOn(DateTime today) {
    final dob = dateOfBirth;
    if (dob == null) return null;
    var age = today.year - dob.year;
    if (today.month < dob.month ||
        (today.month == dob.month && today.day < dob.day)) {
      age--;
    }
    return age;
  }

  @override
  bool operator ==(Object other) =>
      other is ChildProfile &&
      other.id == id &&
      other.displayName == displayName &&
      other.dateOfBirth == dateOfBirth &&
      other.isActive == isActive;

  @override
  int get hashCode => Object.hash(id, displayName, dateOfBirth, isActive);
}

@immutable
class ChildCredentials {
  const ChildCredentials({required this.username, required this.password});

  factory ChildCredentials.fromJson(Map<String, dynamic> json) =>
      ChildCredentials(
        username: json['username'] as String,
        password: json['password'] as String,
      );

  final String username;
  final String password;
}

/// `ConsentPublic`.
@immutable
class ConsentRecord {
  const ConsentRecord({
    required this.id,
    required this.familyId,
    required this.consentType,
    required this.documentVersion,
    required this.accepted,
    this.childId,
    this.acceptedAt,
    this.revokedAt,
  });

  factory ConsentRecord.fromJson(Map<String, dynamic> json) => ConsentRecord(
    id: json['id'] as String,
    familyId: json['family_id'] as String,
    childId: json['child_id'] as String?,
    consentType: json['consent_type'] as String,
    documentVersion: json['document_version'] as String,
    accepted: json['accepted'] as bool,
    acceptedAt: json['accepted_at'] == null
        ? null
        : DateTime.parse(json['accepted_at'] as String),
    revokedAt: json['revoked_at'] == null
        ? null
        : DateTime.parse(json['revoked_at'] as String),
  );

  final String id;
  final String familyId;
  final String? childId;
  final String consentType;
  final String documentVersion;
  final bool accepted;
  final DateTime? acceptedAt;
  final DateTime? revokedAt;

  bool get isActive => accepted && revokedAt == null;
}

/// Input for `POST /families/{id}/children`.
@immutable
class NewChildProfile {
  const NewChildProfile({
    required this.displayName,
    required this.preferredLanguage,
    required this.username,
    required this.password,
    this.dateOfBirth,
  });

  final String displayName;
  final String preferredLanguage;
  final String username;
  final String password;
  final DateTime? dateOfBirth;

  Map<String, dynamic> toJson() => {
    'display_name': displayName.trim(),
    'username': username.trim().toLowerCase(),
    'password': password,
    'preferred_language': preferredLanguage,
    if (dateOfBirth != null) 'date_of_birth': formatIsoDate(dateOfBirth!),
  };
}

/// `YYYY-MM-DD` for Pydantic `date` fields.
String formatIsoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
