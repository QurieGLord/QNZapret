import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/app_config.dart';

const _runtimeRevision = 'r7';

class RuntimeLayout {
  const RuntimeLayout({
    required this.rootDir,
    required this.binaryPath,
    required this.generalListPath,
    required this.googleListPath,
    required this.tlsPayloadPath,
    required this.quicPayloadPath,
    required this.helperPath,
    required this.profilePath,
    required this.settingsPath,
    required this.uiSettingsPath,
    required this.runtimeEnvPath,
    required this.statusPath,
    required this.helperLogPath,
    required this.nfqwsLogPath,
  });

  final String rootDir;
  final String binaryPath;
  final String generalListPath;
  final String googleListPath;
  final String tlsPayloadPath;
  final String quicPayloadPath;
  final String helperPath;
  final String profilePath;
  final String settingsPath;
  final String uiSettingsPath;
  final String runtimeEnvPath;
  final String statusPath;
  final String helperLogPath;
  final String nfqwsLogPath;
}

class RuntimeService {
  Future<RuntimeLayout> ensureRuntime() async {
    final rootDir = Directory(await _resolveRuntimeRoot());
    final binDir = Directory(p.join(rootDir.path, 'bin'));
    final listsDir = Directory(p.join(rootDir.path, 'lists'));
    final payloadsDir = Directory(p.join(rootDir.path, 'payloads'));
    final scriptsDir = Directory(p.join(rootDir.path, 'scripts'));
    final profilesDir = Directory(p.join(rootDir.path, 'profiles'));
    final stateDir = Directory(p.join(rootDir.path, 'state'));
    final logsDir = Directory(p.join(rootDir.path, 'logs'));

    for (final directory in <Directory>[
      rootDir,
      binDir,
      listsDir,
      payloadsDir,
      scriptsDir,
      profilesDir,
      stateDir,
      logsDir,
    ]) {
      await directory.create(recursive: true);
      await _setDirectoryMode(directory.path);
    }

    final layout = RuntimeLayout(
      rootDir: rootDir.path,
      binaryPath: p.join(binDir.path, 'nfqws'),
      generalListPath: p.join(listsDir.path, 'list-general.txt'),
      googleListPath: p.join(listsDir.path, 'list-google.txt'),
      tlsPayloadPath: p.join(
        payloadsDir.path,
        'tls_clienthello_www_google_com.bin',
      ),
      quicPayloadPath: p.join(
        payloadsDir.path,
        'quic_initial_www_google_com.bin',
      ),
      helperPath: p.join(scriptsDir.path, 'nzapret-helper.sh'),
      profilePath: p.join(profilesDir.path, 'default.conf'),
      settingsPath: p.join(rootDir.path, 'settings.json'),
      uiSettingsPath: p.join(rootDir.path, 'ui-settings.json'),
      runtimeEnvPath: p.join(stateDir.path, 'runtime.env'),
      statusPath: p.join(stateDir.path, 'status.env'),
      helperLogPath: p.join(logsDir.path, 'service.log'),
      nfqwsLogPath: p.join(logsDir.path, 'nfqws.log'),
    );

    await _writeAsset(
      'assets/runtime/bin/nfqws',
      layout.binaryPath,
      executable: true,
    );
    await _writeAsset(
      'assets/runtime/lists/list-general.txt',
      layout.generalListPath,
    );
    await _writeAsset(
      'assets/runtime/lists/list-google.txt',
      layout.googleListPath,
    );
    await _writeAsset(
      'assets/runtime/payloads/tls_clienthello_www_google_com.bin',
      layout.tlsPayloadPath,
    );
    await _writeAsset(
      'assets/runtime/payloads/quic_initial_www_google_com.bin',
      layout.quicPayloadPath,
    );
    await _writeAsset(
      'assets/runtime/scripts/nzapret-helper.sh',
      layout.helperPath,
      executable: true,
    );

    if (!File(layout.settingsPath).existsSync()) {
      await saveConfig(layout, AppConfig.defaults);
    } else {
      final config = await loadConfig(layout);
      await _writeProfileAndRuntime(layout, config);
    }

    await File(layout.helperLogPath).create(recursive: true);
    await File(layout.nfqwsLogPath).create(recursive: true);
    await _setFileMode(layout.helperLogPath);
    await _setFileMode(layout.nfqwsLogPath);

    return layout;
  }

  Future<String> _resolveRuntimeRoot() async {
    final uid = await _currentUserId();
    return '/var/tmp/dev.qurie.nzapret_desktop-$uid/$_runtimeRevision/runtime';
  }

  Future<String> _currentUserId() async {
    final result = await Process.run('id', <String>['-u']);
    final uid = (result.stdout as String).trim();
    return uid.isEmpty ? 'unknown' : uid;
  }

  Future<AppConfig> loadConfig(RuntimeLayout layout) async {
    final file = File(layout.settingsPath);
    if (!await file.exists()) {
      return AppConfig.defaults;
    }

    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return AppConfig.fromJson(json);
  }

  Future<void> saveConfig(RuntimeLayout layout, AppConfig config) async {
    await File(layout.settingsPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
    );
    await _writeProfileAndRuntime(layout, config);
  }

  Future<ThemeMode> loadThemeMode(RuntimeLayout layout) async {
    final file = File(layout.uiSettingsPath);
    if (!await file.exists()) {
      return ThemeMode.system;
    }

    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return _themeModeFromName(json['themeMode'] as String?);
    } catch (_) {
      return ThemeMode.system;
    }
  }

  Future<void> saveThemeMode(RuntimeLayout layout, ThemeMode themeMode) async {
    await File(layout.uiSettingsPath).writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(<String, Object?>{'themeMode': _themeModeName(themeMode)}),
      flush: true,
    );
    await _setFileMode(layout.uiSettingsPath);
  }

  Future<void> _writeProfileAndRuntime(
    RuntimeLayout layout,
    AppConfig config,
  ) async {
    await File(
      layout.profilePath,
    ).writeAsString(config.buildProfile(layout.rootDir), flush: true);
    await _setFileMode(layout.profilePath);
    await File(layout.runtimeEnvPath).writeAsString(
      [
        'FORWARD_ENABLED=${config.hookForwardTraffic ? 1 : 0}',
        'NFQWS_DEBUG=1',
        'STARTUP_WAIT_SECONDS=5',
      ].join('\n'),
      flush: true,
    );
    await _setFileMode(layout.runtimeEnvPath);
  }

  Future<void> _writeAsset(
    String assetPath,
    String outputPath, {
    bool executable = false,
  }) async {
    final file = File(outputPath);
    if (await file.exists()) {
      if (executable) {
        await Process.run('chmod', <String>['755', outputPath]);
      } else {
        await _setFileMode(outputPath);
      }
      return;
    }

    final bytes = await _loadAssetBytes(assetPath);
    await file.writeAsBytes(bytes, flush: true);
    if (executable) {
      await Process.run('chmod', <String>['755', outputPath]);
    } else {
      await _setFileMode(outputPath);
    }
  }

  Future<Uint8List> _loadAssetBytes(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  Future<void> _setDirectoryMode(String path) async {
    await Process.run('chmod', <String>['775', path]);
  }

  Future<void> _setFileMode(String path) async {
    await Process.run('chmod', <String>['664', path]);
  }

  ThemeMode _themeModeFromName(String? value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  String _themeModeName(ThemeMode themeMode) {
    return switch (themeMode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
  }
}
