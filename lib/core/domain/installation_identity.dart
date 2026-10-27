import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Represents a stable, privacy-preserving installation identifier for the mobile app.
/// This is an application-generated random UUID, NOT a hardware UDID or private device identifier.
class InstallationIdentity {
  const InstallationIdentity({
    required this.id,
    required this.createdAt,
  });

  final String id;
  final DateTime createdAt;

  factory InstallationIdentity.generate({DateTime? now}) {
    final dt = now ?? DateTime.now().toUtc();
    final randomNonce = sha256
        .convert(
            utf8.encode('${dt.microsecondsSinceEpoch}_${dt.timeZoneOffset}'))
        .toString()
        .substring(0, 16);
    return InstallationIdentity(
      id: 'inst_$randomNonce',
      createdAt: dt,
    );
  }

  factory InstallationIdentity.fromJson(Map<String, dynamic> json) =>
      InstallationIdentity(
        id: json['id'] as String? ?? '',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String) ??
                DateTime.now().toUtc()
            : DateTime.now().toUtc(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
      };
}

/// Repository contract for persistent installation identity.
abstract class InstallationIdentityRepository {
  Future<InstallationIdentity> getIdentity();
}
