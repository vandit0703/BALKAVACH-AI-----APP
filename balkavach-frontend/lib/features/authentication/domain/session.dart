import 'package:flutter/foundation.dart';

enum UserRole {
  parent,
  child,
  admin,
  staff,
  unknown;

  static UserRole parse(String? value) => UserRole.values.firstWhere(
    (role) => role.name == value,
    orElse: () => UserRole.unknown,
  );
}

/// `UserPublic` from the backend.
@immutable
class AppUser {
  const AppUser({
    required this.id,
    required this.fullName,
    required this.role,
    required this.preferredLanguage,
    this.email,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String,
    fullName: json['full_name'] as String,
    email: json['email'] as String?,
    role: UserRole.parse(json['role'] as String?),
    preferredLanguage: json['preferred_language'] as String? ?? 'en',
  );

  final String id;
  final String fullName;
  final String? email;
  final UserRole role;
  final String preferredLanguage;

  Map<String, dynamic> toJson() => {
    'id': id,
    'full_name': fullName,
    'email': email,
    'role': role.name,
    'preferred_language': preferredLanguage,
  };

  @override
  bool operator ==(Object other) =>
      other is AppUser &&
      other.id == id &&
      other.fullName == fullName &&
      other.email == email &&
      other.role == role &&
      other.preferredLanguage == preferredLanguage;

  @override
  int get hashCode => Object.hash(id, fullName, email, role, preferredLanguage);
}

/// An authenticated session on this device.
///
/// [childId] is set only in child mode: it is the `ChildProfile.id` the parent
/// started the session for (the token's subject is the child's *user* id).
@immutable
class Session {
  const Session({
    required this.accessToken,
    required this.expiresAt,
    required this.user,
    this.childId,
  });

  /// Parses the backend `TokenResponse`.
  factory Session.fromTokenResponse(
    Map<String, dynamic> json, {
    String? childId,
  }) => Session(
    accessToken: json['access_token'] as String,
    expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
    user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
    childId: childId,
  );

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    accessToken: json['access_token'] as String,
    expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
    user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
    childId: json['child_id'] as String?,
  );

  final String accessToken;
  final DateTime expiresAt;
  final AppUser user;
  final String? childId;

  bool get isParent => user.role == UserRole.parent;
  bool get isChild => user.role == UserRole.child && childId != null;

  bool isExpiredAt(DateTime now) => !now.toUtc().isBefore(expiresAt);

  Session copyWith({AppUser? user}) => Session(
    accessToken: accessToken,
    expiresAt: expiresAt,
    user: user ?? this.user,
    childId: childId,
  );

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'expires_at': expiresAt.toIso8601String(),
    'user': user.toJson(),
    'child_id': childId,
  };

  @override
  bool operator ==(Object other) =>
      other is Session &&
      other.accessToken == accessToken &&
      other.expiresAt == expiresAt &&
      other.user == user &&
      other.childId == childId;

  @override
  int get hashCode => Object.hash(accessToken, expiresAt, user, childId);
}
