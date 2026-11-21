import 'dart:math';

/// A stable, privacy-preserving installation identifier for the mobile app.
///
/// Generated from 128 bits of `Random.secure()`; it is NOT a hardware UDID or any
/// other device identifier. Format: `inst_` + 32 lowercase hex characters.
/// Identities created by earlier builds (`inst_` + 16 hex characters) remain valid
/// and are never regenerated.
class InstallationIdentity {
  const InstallationIdentity({
    required this.id,
    required this.createdAt,
  });

  final String id;
  final DateTime createdAt;

  static final _currentFormat = RegExp(r'^inst_[0-9a-f]{32}$');
  static final _legacyFormat = RegExp(r'^inst_[0-9a-f]{16}$');

  /// True for the current 128-bit format and the legacy 64-bit-hash format.
  static bool isValidId(String id) =>
      _currentFormat.hasMatch(id) || _legacyFormat.hasMatch(id);

  /// Creates a new identity. [random] is injectable so tests can be deterministic;
  /// production code must use the default [Random.secure].
  factory InstallationIdentity.generate({DateTime? now, Random? random}) {
    final rng = random ?? Random.secure();
    final hex = List.generate(
        16, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    return InstallationIdentity(
      id: 'inst_$hex',
      createdAt: now ?? DateTime.now().toUtc(),
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
