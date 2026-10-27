/// Abstract repository for persisting monotonic event sequence cursors per server.
abstract class CompanionCursorRepository {
  /// Returns the highest acknowledged event sequence for [serverId] (default: 0).
  Future<int> getLastSequence(String serverId);

  /// Persists the highest acknowledged event sequence for [serverId].
  Future<void> saveLastSequence(String serverId, int sequence);

  /// Clears the stored sequence cursor for [serverId].
  Future<void> clear(String serverId);

  /// Clears all stored companion sequence cursors.
  Future<void> clearAll();
}
