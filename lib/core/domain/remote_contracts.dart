abstract interface class RemoteConnection {
  Future<void> connect();
  Future<void> disconnect();
  Future<RemoteSession> openSession();
}

abstract interface class RemoteSession {
  String get remoteId;
  Future<TerminalSession> openTerminal();
  Future<void> close();
}

abstract interface class TerminalSession {
  Stream<List<int>> get output;
  Future<void> send(List<int> input);
  Future<void> resize(int columns, int rows);
  Future<void> close();
}

abstract interface class FileTransferClient {
  Future<List<String>> list(String remotePath);
  Future<List<int>> read(String remotePath);
  Future<void> write(String remotePath, List<int> bytes);
}

abstract interface class SecureCredentialStore {
  Future<void> put(String reference, List<int> secret);
  Future<List<int>?> get(String reference);
  Future<void> delete(String reference);
}
