import 'package:path/path.dart' as p;

class AppConfig {
  const AppConfig({
    required this.queueNumber,
    required this.tcpPorts,
    required this.udpPorts,
    required this.enableQuic,
    required this.hookForwardTraffic,
    required this.tcpExtraArgs,
    required this.udpExtraArgs,
  });

  final int queueNumber;
  final String tcpPorts;
  final String udpPorts;
  final bool enableQuic;
  final bool hookForwardTraffic;
  final String tcpExtraArgs;
  final String udpExtraArgs;

  static const AppConfig defaults = AppConfig(
    queueNumber: 200,
    tcpPorts: '80,443',
    udpPorts: '443',
    enableQuic: true,
    hookForwardTraffic: true,
    tcpExtraArgs: '',
    udpExtraArgs: '',
  );

  AppConfig copyWith({
    int? queueNumber,
    String? tcpPorts,
    String? udpPorts,
    bool? enableQuic,
    bool? hookForwardTraffic,
    String? tcpExtraArgs,
    String? udpExtraArgs,
  }) {
    return AppConfig(
      queueNumber: queueNumber ?? this.queueNumber,
      tcpPorts: tcpPorts ?? this.tcpPorts,
      udpPorts: udpPorts ?? this.udpPorts,
      enableQuic: enableQuic ?? this.enableQuic,
      hookForwardTraffic: hookForwardTraffic ?? this.hookForwardTraffic,
      tcpExtraArgs: tcpExtraArgs ?? this.tcpExtraArgs,
      udpExtraArgs: udpExtraArgs ?? this.udpExtraArgs,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'queueNumber': queueNumber,
      'tcpPorts': tcpPorts,
      'udpPorts': udpPorts,
      'enableQuic': enableQuic,
      'hookForwardTraffic': hookForwardTraffic,
      'tcpExtraArgs': tcpExtraArgs,
      'udpExtraArgs': udpExtraArgs,
    };
  }

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      queueNumber: json['queueNumber'] as int? ?? defaults.queueNumber,
      tcpPorts: json['tcpPorts'] as String? ?? defaults.tcpPorts,
      udpPorts: json['udpPorts'] as String? ?? defaults.udpPorts,
      enableQuic: json['enableQuic'] as bool? ?? defaults.enableQuic,
      hookForwardTraffic:
          json['hookForwardTraffic'] as bool? ?? defaults.hookForwardTraffic,
      tcpExtraArgs: (json['tcpExtraArgs'] as String? ?? '').trim(),
      udpExtraArgs: (json['udpExtraArgs'] as String? ?? '').trim(),
    );
  }

  static String normalizePorts(String value) {
    return value
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(',');
  }

  String buildProfile(String runtimeRoot) {
    final generalList = p.join(runtimeRoot, 'lists', 'list-general.txt');
    final googleList = p.join(runtimeRoot, 'lists', 'list-google.txt');
    final tlsPayload = p.join(
      runtimeRoot,
      'payloads',
      'tls_clienthello_www_google_com.bin',
    );
    final quicPayload = p.join(
      runtimeRoot,
      'payloads',
      'quic_initial_www_google_com.bin',
    );

    final buffer = StringBuffer()
      ..writeln('# profile: Desktop nftables preset')
      ..writeln('--uid=0:0')
      ..writeln('--qnum=$queueNumber')
      ..writeln('--bind-fix4')
      ..writeln('--bind-fix6')
      ..writeln('--filter-tcp=${normalizePorts(tcpPorts)}')
      ..writeln('--hostlist=$generalList')
      ..writeln('--hostlist=$googleList')
      ..writeln('--dpi-desync=fake,split')
      ..writeln('--dpi-desync-split-pos=1')
      ..writeln('--dpi-desync-repeats=1')
      ..writeln('--dpi-desync-fooling=ts')
      ..writeln('--dpi-desync-fake-tls=@$tlsPayload');

    _writeExtraArgs(buffer, tcpExtraArgs);

    if (enableQuic) {
      buffer
        ..writeln('--new')
        ..writeln('--filter-udp=${normalizePorts(udpPorts)}')
        ..writeln('--hostlist=$googleList')
        ..writeln('--dpi-desync=fake')
        ..writeln('--dpi-desync-repeats=1')
        ..writeln('--dpi-desync-fake-quic=@$quicPayload');

      _writeExtraArgs(buffer, udpExtraArgs);
    }

    return buffer.toString().trimRight();
  }

  static void _writeExtraArgs(StringBuffer buffer, String rawArgs) {
    for (final line in rawArgs.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      buffer.writeln(trimmed);
    }
  }
}
