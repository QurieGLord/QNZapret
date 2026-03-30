class ResourceInfo {
  const ResourceInfo({
    required this.name,
    required this.path,
    required this.bytes,
    required this.preview,
  });

  final String name;
  final String path;
  final int bytes;
  final String preview;

  String get sizeLabel {
    const units = <String>['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    final precision = unitIndex == 0 ? 0 : 1;
    return '${size.toStringAsFixed(precision)} ${units[unitIndex]}';
  }
}

class AppStatus {
  const AppStatus({
    required this.runtimeReady,
    required this.nftAvailable,
    required this.pkexecAvailable,
    required this.rootSession,
    required this.running,
    required this.pid,
    required this.message,
    required this.updatedAt,
    required this.profileText,
    required this.helperLogTail,
    required this.nfqwsLogTail,
    required this.runtimePath,
    required this.generalList,
    required this.googleList,
    required this.tlsPayload,
    required this.quicPayload,
  });

  final bool runtimeReady;
  final bool nftAvailable;
  final bool pkexecAvailable;
  final bool rootSession;
  final bool running;
  final int? pid;
  final String message;
  final String updatedAt;
  final String profileText;
  final String helperLogTail;
  final String nfqwsLogTail;
  final String runtimePath;
  final ResourceInfo generalList;
  final ResourceInfo googleList;
  final ResourceInfo tlsPayload;
  final ResourceInfo quicPayload;

  String get privilegeSummary {
    if (rootSession) {
      return 'Команды выполняются напрямую под root.';
    }
    if (pkexecAvailable) {
      return 'Команды start/stop будут поднимать root через pkexec.';
    }
    return 'Нужен root или установленный pkexec/polkit.';
  }
}
