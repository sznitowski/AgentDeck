import '../../../core/domain/events.dart';

/// Deduplicates domain events based on stable fingerprint within a time window.
class EventDeduplicator {
  EventDeduplicator({
    this.window = const Duration(minutes: 10),
  });

  final Duration window;
  final Map<String, DateTime> _seenFingerprints = {};

  /// Checks if an event has already been seen within the active deduplication window.
  bool isDuplicate(AgentDeckEvent event, {DateTime? now}) {
    if (event.fingerprint.isEmpty) return false;

    final current = now ?? DateTime.now();
    final lastSeen = _seenFingerprints[event.fingerprint];

    if (lastSeen != null && current.difference(lastSeen) < window) {
      return true;
    }

    _seenFingerprints[event.fingerprint] = current;
    _pruneOldEntries(current);
    return false;
  }

  /// Filters a list of events, returning only those that are not duplicates.
  List<AgentDeckEvent> filterDuplicates(
    List<AgentDeckEvent> events, {
    DateTime? now,
  }) {
    final result = <AgentDeckEvent>[];
    for (final event in events) {
      if (!isDuplicate(event, now: now)) {
        result.add(event);
      }
    }
    return result;
  }

  void _pruneOldEntries(DateTime current) {
    _seenFingerprints.removeWhere(
      (_, timestamp) => current.difference(timestamp) >= window,
    );
  }

  void clear() {
    _seenFingerprints.clear();
  }
}
