import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/app_config.dart';
import '../models/app_status.dart';
import 'runtime_service.dart';

class CommandOutcome {
  const CommandOutcome({required this.success, required this.message});

  final bool success;
  final String message;
}

class NzapretController {
  NzapretController({RuntimeService? runtimeService})
    : _runtimeService = runtimeService ?? RuntimeService();

  final RuntimeService _runtimeService;
  RuntimeLayout? _layout;
  Future<RuntimeLayout>? _layoutFuture;

  Future<RuntimeLayout> _ensureLayout() async {
    if (_layout != null) {
      return _layout!;
    }

    final future = _layoutFuture ??= _runtimeService.ensureRuntime();
    try {
      final layout = await future;
      _layout = layout;
      return layout;
    } catch (_) {
      if (identical(_layoutFuture, future)) {
        _layoutFuture = null;
      }
      rethrow;
    }
  }

  Future<AppConfig> loadConfig() async {
    final layout = await _ensureLayout();
    return _runtimeService.loadConfig(layout);
  }

  Future<String> buildProfilePreview(AppConfig config) async {
    final layout = await _ensureLayout();
    return config.buildProfile(layout.rootDir);
  }

  Future<ThemeMode> loadThemeMode() async {
    final layout = await _ensureLayout();
    return _runtimeService.loadThemeMode(layout);
  }

  Future<void> saveThemeMode(ThemeMode themeMode) async {
    final layout = await _ensureLayout();
    await _runtimeService.saveThemeMode(layout, themeMode);
  }

  Future<CommandOutcome> saveConfig(AppConfig config) async {
    final layout = await _ensureLayout();
    await _runtimeService.saveConfig(layout, config);
    return const CommandOutcome(
      success: true,
      message: 'Профиль сохранён в runtime.',
    );
  }

  Future<CommandOutcome> start(AppConfig config) async {
    await saveConfig(config);
    return _runPrivileged('start');
  }

  Future<CommandOutcome> restart(AppConfig config) async {
    await saveConfig(config);
    return _runPrivileged('restart');
  }

  Future<CommandOutcome> stop() => _runPrivileged('stop');

  Future<AppStatus> readStatus() async {
    final layout = await _ensureLayout();
    final statusMap = await _readKeyValueFile(layout.statusPath);
    final pid = int.tryParse(statusMap['pid'] ?? '');
    final running = pid != null && await Directory('/proc/$pid').exists();
    final rawMessage = (statusMap['message'] ?? '').trim();
    final normalizedMessage = _normalizeUserMessage(rawMessage);
    final message = running
        ? (normalizedMessage.isNotEmpty ? normalizedMessage : 'Сервис запущен.')
        : normalizedMessage.isNotEmpty && normalizedMessage != 'Сервис запущен.'
        ? normalizedMessage
        : pid != null
        ? 'nfqws завершился. Открой лог helper/nfqws.'
        : 'Статус ещё не обновлялся.';

    return AppStatus(
      runtimeReady: await _runtimeReady(layout),
      nftAvailable: await _commandExists('nft'),
      pkexecAvailable: await _commandExists('pkexec'),
      rootSession: await _isRootSession(),
      running: running,
      pid: running ? pid : null,
      message: message,
      updatedAt: statusMap['updated_at'] ?? 'ещё нет действий',
      profileText: await _readText(layout.profilePath),
      helperLogTail: await _tailFile(layout.helperLogPath),
      nfqwsLogTail: await _tailFile(layout.nfqwsLogPath),
      runtimePath: layout.rootDir,
      generalList: await _inspectTextResource(
        'list-general.txt',
        layout.generalListPath,
        previewLines: 8,
      ),
      googleList: await _inspectTextResource(
        'list-google.txt',
        layout.googleListPath,
        previewLines: 8,
      ),
      tlsPayload: await _inspectBinaryResource(
        'tls_clienthello_www_google_com.bin',
        layout.tlsPayloadPath,
      ),
      quicPayload: await _inspectBinaryResource(
        'quic_initial_www_google_com.bin',
        layout.quicPayloadPath,
      ),
    );
  }

  Future<CommandOutcome> _runPrivileged(String action) async {
    final layout = await _ensureLayout();
    final isRoot = await _isRootSession();
    final hasPkexec = await _commandExists('pkexec');

    if (!isRoot && !hasPkexec) {
      return const CommandOutcome(
        success: false,
        message:
            'Нужен root-доступ. Установите pkexec/polkit или запустите приложение от root.',
      );
    }

    if (!isRoot && hasPkexec && action == 'stop') {
      return _stopViaSystemd(layout);
    }

    if (!isRoot && hasPkexec && (action == 'start' || action == 'restart')) {
      return _runViaSystemd(action, layout);
    }

    final executable = isRoot ? layout.helperPath : 'pkexec';
    final arguments = isRoot
        ? <String>[action, layout.rootDir]
        : <String>[layout.helperPath, action, layout.rootDir];

    final result = await Process.run(executable, arguments);
    final stdout = (result.stdout as String).trim();
    final stderr = (result.stderr as String).trim();

    if (result.exitCode == 0) {
      final message = _normalizeUserMessage(stdout);
      return CommandOutcome(
        success: true,
        message: message.isNotEmpty ? message : _defaultSuccessMessage(action),
      );
    }

    final message = _normalizeUserMessage(stderr.isNotEmpty ? stderr : stdout);
    return CommandOutcome(
      success: false,
      message: message.isNotEmpty ? message : _defaultFailureMessage(action),
    );
  }

  Future<CommandOutcome> _runViaSystemd(
    String action,
    RuntimeLayout layout,
  ) async {
    await _ensurePolkitAgentIfPossible();
    final unit = await _serviceUnitName();
    final result = await Process.run('pkexec', <String>[
      layout.helperPath,
      'launch-service',
      layout.rootDir,
      unit,
    ]);

    final stdout = (result.stdout as String).trim();
    final stderr = (result.stderr as String).trim();

    if (result.exitCode != 0) {
      final message = _normalizeUserMessage(
        stderr.isNotEmpty ? stderr : stdout,
      );
      return CommandOutcome(
        success: false,
        message: message.isNotEmpty
            ? message
            : 'Не удалось запустить сервис через systemd.',
      );
    }

    return _waitForManagedStart(action, layout);
  }

  Future<CommandOutcome> _stopViaSystemd(RuntimeLayout layout) async {
    await _ensurePolkitAgentIfPossible();
    final unit = await _serviceUnitName();
    final result = await Process.run('pkexec', <String>[
      'systemctl',
      'stop',
      unit,
    ]);

    final stdout = (result.stdout as String).trim();
    final stderr = (result.stderr as String).trim();

    if (result.exitCode != 0) {
      final rawMessage = stderr.isNotEmpty ? stderr : stdout;
      final message = _normalizeUserMessage(rawMessage);
      if (!_looksLikeMissingUnit(rawMessage)) {
        return CommandOutcome(
          success: false,
          message: message.isNotEmpty
              ? message
              : 'Не удалось остановить сервис.',
        );
      }

      final fallback = await Process.run('pkexec', <String>[
        layout.helperPath,
        'stop',
        layout.rootDir,
      ]);
      final fallbackStdout = (fallback.stdout as String).trim();
      final fallbackStderr = (fallback.stderr as String).trim();

      if (fallback.exitCode != 0) {
        final fallbackMessage = _normalizeUserMessage(
          fallbackStderr.isNotEmpty ? fallbackStderr : fallbackStdout,
        );
        return CommandOutcome(
          success: false,
          message: fallbackMessage.isNotEmpty
              ? fallbackMessage
              : 'Не удалось остановить сервис.',
        );
      }
    }

    return _waitForManagedStop(layout);
  }

  Future<CommandOutcome> _waitForManagedStart(
    String action,
    RuntimeLayout layout,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    var lastMessage = action == 'restart'
        ? 'Сервис перезапускается через systemd...'
        : 'Сервис запускается через systemd...';

    while (DateTime.now().isBefore(deadline)) {
      final statusMap = await _readKeyValueFile(layout.statusPath);
      final rawMessage = (statusMap['message'] ?? '').trim();
      final message = _normalizeUserMessage(rawMessage);
      final pid = int.tryParse(statusMap['pid'] ?? '');

      if (message.isNotEmpty) {
        lastMessage = message;
      }

      if (pid != null && await Directory('/proc/$pid').exists()) {
        return CommandOutcome(
          success: true,
          message: action == 'restart'
              ? 'Сервис перезапущен. PID $pid.'
              : 'Сервис запущен. PID $pid.',
        );
      }

      if (_isLaunchFailureMessage(rawMessage)) {
        return CommandOutcome(success: false, message: message);
      }

      await Future<void>.delayed(const Duration(milliseconds: 400));
    }

    return CommandOutcome(
      success: false,
      message:
          'Не удалось дождаться рабочего PID. Последний статус: $lastMessage',
    );
  }

  Future<CommandOutcome> _waitForManagedStop(RuntimeLayout layout) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    var lastMessage = 'Останавливаем сервис...';

    while (DateTime.now().isBefore(deadline)) {
      final statusMap = await _readKeyValueFile(layout.statusPath);
      final rawMessage = (statusMap['message'] ?? '').trim();
      final message = _normalizeUserMessage(rawMessage);
      final pid = int.tryParse(statusMap['pid'] ?? '');
      final running = pid != null && await Directory('/proc/$pid').exists();

      if (message.isNotEmpty) {
        lastMessage = message;
      }

      if (!running) {
        return CommandOutcome(
          success: true,
          message: message.isNotEmpty ? message : 'Сервис остановлен.',
        );
      }

      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    return CommandOutcome(
      success: false,
      message:
          'Не удалось дождаться остановки сервиса. Последний статус: $lastMessage',
    );
  }

  bool _isLaunchFailureMessage(String message) {
    final normalizedMessage = _normalizeUserMessage(message);
    if (message.isEmpty ||
        normalizedMessage.isEmpty ||
        normalizedMessage == 'Запускаем сервис через systemd...' ||
        normalizedMessage == 'Запрос на запуск через systemd отправлен.') {
      return false;
    }

    final normalized = normalizedMessage.toLowerCase();
    return normalized.contains('exited') ||
        normalized.contains('failed') ||
        normalized.contains('missing') ||
        normalized.contains('permission') ||
        normalized.contains('denied') ||
        normalized.contains('сбой') ||
        normalized.contains('завершился') ||
        normalized.contains('не найден') ||
        normalized.contains('не найдена') ||
        normalized.contains('отказано') ||
        normalized.contains('не удалось');
  }

  String _defaultSuccessMessage(String action) {
    switch (action) {
      case 'start':
        return 'Сервис запущен.';
      case 'restart':
        return 'Сервис перезапущен.';
      case 'stop':
        return 'Сервис остановлен.';
      default:
        return 'Команда выполнена.';
    }
  }

  String _defaultFailureMessage(String action) {
    switch (action) {
      case 'start':
        return 'Не удалось запустить сервис.';
      case 'restart':
        return 'Не удалось перезапустить сервис.';
      case 'stop':
        return 'Не удалось остановить сервис.';
      default:
        return 'Команда завершилась с ошибкой.';
    }
  }

  String _normalizeUserMessage(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    const exactMessages = <String, String>{
      'service stopped': 'Сервис остановлен.',
      'Сервис остановлен.': 'Сервис остановлен.',
      'nfqws started': 'Сервис запущен.',
      'Сервис запущен.': 'Сервис запущен.',
      'status refreshed': 'Статус обновлён.',
      'Статус обновлён.': 'Статус обновлён.',
      'launching via systemd': 'Запускаем сервис через systemd...',
      'Запускаем сервис через systemd...': 'Запускаем сервис через systemd...',
      'service launch queued': 'Запрос на запуск через systemd отправлен.',
      'Запрос на запуск через systemd отправлен.':
          'Запрос на запуск через systemd отправлен.',
      'failed to start transient systemd service':
          'Не удалось запустить transient unit через systemd.',
      'systemd unit name is required': 'Не передано имя systemd-unit-а.',
      'runtime directory is required': 'Не передан runtime-каталог.',
    };

    final exactMessage = exactMessages[trimmed];
    if (exactMessage != null) {
      return exactMessage;
    }

    final lowerTrimmed = trimmed.toLowerCase();
    if (lowerTrimmed.contains('error creating textual authentication agent') &&
        lowerTrimmed.contains('/dev/tty')) {
      return 'Не удалось открыть окно авторизации pkexec. Графический polkit-agent в сессии не запущен или был закрыт. Запусти его снова и повтори попытку.';
    }

    if (lowerTrimmed.contains('no authentication agent found')) {
      return 'Не найден графический агент авторизации polkit. Запусти его в пользовательской сессии и повтори попытку.';
    }

    if (lowerTrimmed == 'not authorized' ||
        lowerTrimmed.contains('authorization failed')) {
      return 'Авторизация отменена или не была завершена.';
    }

    if (trimmed.contains('wait "\$pid"')) {
      return 'Сбой helper-а при ожидании завершения процесса.';
    }

    final helperFailedMatch = RegExp(
      r'^helper failed:\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (helperFailedMatch != null) {
      return 'Сбой helper-а: ${helperFailedMatch.group(1)!.trim()}';
    }

    final helperFailureMatch = RegExp(
      r'^helper failure(?: \(\d+\))?:\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (helperFailureMatch != null) {
      return 'Сбой helper-а: ${helperFailureMatch.group(1)!.trim()}';
    }

    final startedPidMatch = RegExp(
      r'^nfqws started \(pid (\d+)\)$',
    ).firstMatch(trimmed);
    if (startedPidMatch != null) {
      return 'Сервис запущен. PID ${startedPidMatch.group(1)}.';
    }

    final startupExitMatch = RegExp(
      r'^nfqws exited during startup, see (.+)$',
    ).firstMatch(trimmed);
    if (startupExitMatch != null) {
      return 'nfqws завершился во время запуска. См. ${startupExitMatch.group(1)}';
    }

    final exitCodeMatch = RegExp(
      r'^nfqws exited \(code (\d+)\)$',
    ).firstMatch(trimmed);
    if (exitCodeMatch != null) {
      return 'nfqws завершился с кодом ${exitCodeMatch.group(1)}.';
    }

    if (trimmed.startsWith('missing command: ')) {
      return 'Не найдена команда: ${trimmed.substring('missing command: '.length)}';
    }

    if (trimmed.startsWith('missing file: ')) {
      return 'Не найден файл: ${trimmed.substring('missing file: '.length)}';
    }

    return trimmed
        .replaceAll('Permission denied', 'Отказано в доступе')
        .replaceAll('permission denied', 'отказано в доступе');
  }

  Future<void> _ensurePolkitAgentIfPossible() async {
    if (await _hasRunningPolkitAgent()) {
      return;
    }

    final desktop = (Platform.environment['XDG_CURRENT_DESKTOP'] ?? '')
        .toLowerCase();
    final candidates = <String>[
      if (desktop.contains('pantheon'))
        '/usr/lib/x86_64-linux-gnu/policykit-1-pantheon/io.elementary.desktop.agent-polkit',
      '/usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1',
    ];

    for (final candidate in candidates) {
      if (!await File(candidate).exists()) {
        continue;
      }

      try {
        await Process.start(
          candidate,
          const <String>[],
          mode: ProcessStartMode.detached,
        );
      } catch (_) {
        continue;
      }

      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (await _hasRunningPolkitAgent()) {
        return;
      }
    }
  }

  Future<bool> _hasRunningPolkitAgent() async {
    final result = await Process.run('ps', <String>['-eo', 'comm=,args=']);
    if (result.exitCode != 0) {
      return false;
    }

    final output = (result.stdout as String).toLowerCase();
    const markers = <String>[
      'io.elementary.desktop.agent-polkit',
      'polkit-gnome-authentication-agent-1',
      'lxqt-policykit-agent',
      'mate-polkit',
      'xfce-polkit',
      'polkit-kde-authentication-agent-1',
      'polkit-kde-agent-1',
    ];

    return markers.any(output.contains);
  }

  bool _looksLikeMissingUnit(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('not loaded') ||
        normalized.contains('could not be found') ||
        normalized.contains('not be found') ||
        normalized.contains('not loaded.');
  }

  Future<String> _serviceUnitName() async {
    final result = await Process.run('id', <String>['-u']);
    final uid = (result.stdout as String).trim();
    final safeUid = uid.isEmpty ? 'unknown' : uid;
    return 'nzapret-desktop-$safeUid.service';
  }

  Future<bool> _runtimeReady(RuntimeLayout layout) async {
    return await File(layout.binaryPath).exists() &&
        await File(layout.generalListPath).exists() &&
        await File(layout.googleListPath).exists() &&
        await File(layout.tlsPayloadPath).exists() &&
        await File(layout.quicPayloadPath).exists() &&
        await File(layout.helperPath).exists() &&
        await File(layout.profilePath).exists();
  }

  Future<Map<String, String>> _readKeyValueFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return <String, String>{};
    }

    final values = <String, String>{};
    for (final line in await file.readAsLines()) {
      final separator = line.indexOf('=');
      if (separator <= 0) {
        continue;
      }
      values[line.substring(0, separator)] = line.substring(separator + 1);
    }
    return values;
  }

  Future<String> _readText(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return '';
    }
    return file.readAsString();
  }

  Future<String> _tailFile(String path, {int maxLines = 80}) async {
    final file = File(path);
    if (!await file.exists()) {
      return 'Лог пока пуст.';
    }
    final lines = await file.readAsLines();
    if (lines.isEmpty) {
      return 'Лог пока пуст.';
    }
    return lines
        .skip(lines.length > maxLines ? lines.length - maxLines : 0)
        .join('\n');
  }

  Future<ResourceInfo> _inspectTextResource(
    String name,
    String path, {
    required int previewLines,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      return ResourceInfo(
        name: name,
        path: path,
        bytes: 0,
        preview: 'Файл не найден.',
      );
    }

    final stat = await file.stat();
    final preview = await file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .take(previewLines)
        .toList();

    return ResourceInfo(
      name: name,
      path: path,
      bytes: stat.size,
      preview: preview.isEmpty ? 'Файл пуст.' : preview.join('\n'),
    );
  }

  Future<ResourceInfo> _inspectBinaryResource(String name, String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return ResourceInfo(
        name: name,
        path: path,
        bytes: 0,
        preview: 'Файл не найден.',
      );
    }

    final stat = await file.stat();
    return ResourceInfo(
      name: name,
      path: path,
      bytes: stat.size,
      preview: 'Бинарный payload, предпросмотр отключён.',
    );
  }

  Future<bool> _commandExists(String command) async {
    final result = await Process.run('bash', <String>[
      '-lc',
      'command -v $command',
    ]);
    return result.exitCode == 0;
  }

  Future<bool> _isRootSession() async {
    final result = await Process.run('id', <String>['-u']);
    return (result.stdout as String).trim() == '0';
  }
}
