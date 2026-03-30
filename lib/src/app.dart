import 'dart:async';

import 'package:flutter/material.dart';

import 'models/app_config.dart';
import 'models/app_status.dart';
import 'services/nzapret_controller.dart';
import 'theme/app_theme.dart';
import 'widgets/status_pill.dart';

enum _LogView { helper, nfqws }

enum _DashboardTab { control, logs }

class NzapretDesktopApp extends StatefulWidget {
  const NzapretDesktopApp({super.key});

  @override
  State<NzapretDesktopApp> createState() => _NzapretDesktopAppState();
}

class _NzapretDesktopAppState extends State<NzapretDesktopApp> {
  final _controller = NzapretController();
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _restoreThemeMode();
  }

  Future<void> _restoreThemeMode() async {
    try {
      final themeMode = await _controller.loadThemeMode();
      if (!mounted) {
        return;
      }
      setState(() {
        _themeMode = themeMode;
      });
    } catch (error, stackTrace) {
      debugPrint('theme restore failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _persistThemeMode(ThemeMode themeMode) async {
    try {
      await _controller.saveThemeMode(themeMode);
    } catch (error, stackTrace) {
      debugPrint('theme save failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _toggleTheme() {
    final platformBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final isDark = switch (_themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => platformBrightness == Brightness.dark,
    };
    final nextThemeMode = isDark ? ThemeMode.light : ThemeMode.dark;

    setState(() {
      _themeMode = nextThemeMode;
    });
    unawaited(_persistThemeMode(nextThemeMode));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NZapret Desktop',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      themeAnimationDuration: const Duration(milliseconds: 520),
      themeAnimationCurve: Curves.easeInOutCubicEmphasized,
      home: _DashboardPage(
        controller: _controller,
        onThemeToggle: _toggleTheme,
      ),
    );
  }
}

class _DashboardPage extends StatefulWidget {
  const _DashboardPage({required this.controller, required this.onThemeToggle});

  final NzapretController controller;
  final VoidCallback onThemeToggle;

  @override
  State<_DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<_DashboardPage> {
  static const _motionDuration = Duration(milliseconds: 460);
  static const _motionCurve = Curves.easeInOutCubicEmphasized;
  static const _tabIslandInset = 18.0;
  static const _tabIslandBottomPadding = 108.0;

  final _queueController = TextEditingController();
  final _tcpPortsController = TextEditingController();
  final _udpPortsController = TextEditingController();
  final _tcpExtraController = TextEditingController();
  final _udpExtraController = TextEditingController();
  final _logScrollController = ScrollController();

  AppStatus? _status;
  bool _busy = true;
  bool _enableQuic = true;
  bool _hookForwardTraffic = true;
  String _activityMessage =
      'Инициализируем runtime и подготавливаем профиль...';
  _LogView _logView = _LogView.helper;
  _DashboardTab _activeTab = _DashboardTab.control;
  int _tabDirection = 1;
  Timer? _timer;

  bool get _canInteract => !_busy && _status != null;
  NzapretController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _applyConfig(AppConfig.defaults);
    _bootstrap();
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshStatus(silent: true),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _queueController.dispose();
    _tcpPortsController.dispose();
    _udpPortsController.dispose();
    _tcpExtraController.dispose();
    _udpExtraController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final config = await _controller.loadConfig();
      final status = await _controller.readStatus();
      if (!mounted) {
        return;
      }
      _applyConfig(config);
      setState(() {
        _status = status;
        _busy = false;
        _activityMessage =
            'Hostlist-ы и payload-ы уже встроены. Можно запускать профиль или перейти в логи для live-диагностики.';
      });
    } catch (error, stackTrace) {
      debugPrint('bootstrap failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _activityMessage = 'Не удалось инициализировать приложение: $error';
      });
    }
  }

  void _applyConfig(AppConfig config) {
    _queueController.text = config.queueNumber.toString();
    _tcpPortsController.text = config.tcpPorts;
    _udpPortsController.text = config.udpPorts;
    _tcpExtraController.text = config.tcpExtraArgs;
    _udpExtraController.text = config.udpExtraArgs;
    _enableQuic = config.enableQuic;
    _hookForwardTraffic = config.hookForwardTraffic;
  }

  AppConfig _draftConfig() {
    final queue = int.tryParse(_queueController.text.trim());
    if (queue == null || queue <= 0 || queue > 65535) {
      throw const FormatException('NFQUEUE должен быть числом от 1 до 65535.');
    }

    return AppConfig(
      queueNumber: queue,
      tcpPorts: AppConfig.normalizePorts(_tcpPortsController.text),
      udpPorts: AppConfig.normalizePorts(_udpPortsController.text),
      enableQuic: _enableQuic,
      hookForwardTraffic: _hookForwardTraffic,
      tcpExtraArgs: _tcpExtraController.text.trim(),
      udpExtraArgs: _udpExtraController.text.trim(),
    );
  }

  Future<void> _runConfigTask({
    required String progressMessage,
    required Future<CommandOutcome> Function(AppConfig config) task,
  }) async {
    try {
      final config = _draftConfig();
      setState(() {
        _busy = true;
        _activityMessage = progressMessage;
      });
      final outcome = await task(config);
      await _refreshStatus(silent: true);
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _activityMessage = outcome.message;
      });
      _showSnack(outcome);
    } on FormatException catch (error) {
      setState(() {
        _busy = false;
        _activityMessage = error.message;
      });
      _showSnack(CommandOutcome(success: false, message: error.message));
    } catch (error) {
      setState(() {
        _busy = false;
        _activityMessage = '$error';
      });
      _showSnack(CommandOutcome(success: false, message: '$error'));
    }
  }

  Future<void> _stop() async {
    setState(() {
      _busy = true;
      _activityMessage = 'Останавливаем nfqws и снимаем таблицу nftables...';
    });
    final outcome = await _controller.stop();
    await _refreshStatus(silent: true);
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _activityMessage = outcome.message;
    });
    _showSnack(outcome);
  }

  Future<void> _refreshStatus({bool silent = false}) async {
    try {
      final status = await _controller.readStatus();
      if (!mounted) {
        return;
      }
      setState(() {
        _status = status;
        if (!silent) {
          _activityMessage = 'Статус обновлён.';
        }
      });
    } catch (error, stackTrace) {
      debugPrint('refresh status failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted || silent) {
        return;
      }
      setState(() {
        _activityMessage = 'Не удалось обновить статус: $error';
      });
    }
  }

  void _showSnack(CommandOutcome outcome) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(outcome.message),
        backgroundColor: outcome.success
            ? const Color(0xFF0F7C70)
            : const Color(0xFF9B3D2A),
      ),
    );
  }

  void _selectTab(_DashboardTab tab) {
    if (tab == _activeTab) {
      return;
    }

    final currentIndex = _DashboardTab.values.indexOf(_activeTab);
    final nextIndex = _DashboardTab.values.indexOf(tab);

    setState(() {
      _tabDirection = nextIndex > currentIndex ? 1 : -1;
      _activeTab = tab;
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final logText = switch (_logView) {
      _LogView.helper => status?.helperLogTail ?? 'Лог helper-а пока пуст.',
      _LogView.nfqws => status?.nfqwsLogTail ?? 'Лог nfqws пока пуст.',
    };

    final page = switch (_activeTab) {
      _DashboardTab.control => _buildParametersCard(status),
      _DashboardTab.logs => _buildLogsCard(status, logText, isDark),
    };

    return Scaffold(
      body: Stack(
        children: [
          const _Backdrop(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final horizontalPadding = constraints.maxWidth >= 920
                    ? 30.0
                    : 18.0;

                return Stack(
                  children: [
                    SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        24,
                        horizontalPadding,
                        _tabIslandBottomPadding,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1180),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildHero(status, isDark),
                              const SizedBox(height: 22),
                              AnimatedSwitcher(
                                duration: _motionDuration,
                                switchInCurve: _motionCurve,
                                switchOutCurve: Curves.easeOutCubic,
                                layoutBuilder:
                                    (currentChild, previousChildren) {
                                      return Stack(
                                        alignment: Alignment.topCenter,
                                        children: [
                                          ...previousChildren,
                                          ...?currentChild == null
                                              ? null
                                              : <Widget>[currentChild],
                                        ],
                                      );
                                    },
                                transitionBuilder: (child, animation) {
                                  final isIncoming =
                                      child.key ==
                                      ValueKey<_DashboardTab>(_activeTab);
                                  final curved = CurvedAnimation(
                                    parent: animation,
                                    curve: _motionCurve,
                                    reverseCurve: Curves.easeOutCubic,
                                  );
                                  final beginX = isIncoming
                                      ? 0.09 * _tabDirection
                                      : -0.09 * _tabDirection;

                                  return FadeTransition(
                                    opacity: curved,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: Offset(beginX, 0),
                                        end: Offset.zero,
                                      ).animate(curved),
                                      child: child,
                                    ),
                                  );
                                },
                                child: KeyedSubtree(
                                  key: ValueKey<_DashboardTab>(_activeTab),
                                  child: page,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: _tabIslandInset,
                      child: Center(child: _buildTabIsland(isDark)),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero(AppStatus? status, bool isDark) {
    final running = status?.running ?? false;

    return AnimatedContainer(
      duration: _motionDuration,
      curve: _motionCurve,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
        gradient: LinearGradient(
          colors: isDark
              ? const [Color(0xFF0A2834), Color(0xFF0D5C5F), Color(0xFFCA6F47)]
              : const [Color(0xFF0E4A63), Color(0xFF138475), Color(0xFFF07D43)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.1 : 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFF0E4A63,
            ).withValues(alpha: isDark ? 0.34 : 0.2),
            blurRadius: 48,
            offset: const Offset(0, 26),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    StatusPill(
                      label: 'Сервис',
                      value: running ? 'Активен' : 'Остановлен',
                      color: running
                          ? const Color(0xFF67F2D3)
                          : const Color(0xFFFFA662),
                      icon: running
                          ? Icons.bolt_rounded
                          : Icons.pause_circle_rounded,
                    ),
                    StatusPill(
                      label: 'nftables',
                      value: status?.nftAvailable == true
                          ? 'Готов'
                          : 'Не найден',
                      color: const Color(0xFFBCEAFF),
                      icon: Icons.rule_rounded,
                    ),
                    StatusPill(
                      label: 'PID',
                      value: status?.pid?.toString() ?? 'нет процесса',
                      color: const Color(0xFFFFE1D2),
                      icon: Icons.memory_rounded,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _buildThemeToggle(isDark),
            ],
          ),
          const SizedBox(height: 26),
          Text(
            'NZapret Desktop',
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Основной control-центр для запуска стратегии, управления nftables и быстрого перехода к логам.',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.92),
              height: 1.25,
            ),
          ),
          const SizedBox(height: 18),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: isDark ? 0.1 : 0.14),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: Colors.white.withValues(alpha: isDark ? 0.1 : 0.18),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Text(
                _activityMessage,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.93),
                  height: 1.34,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: _canInteract
                    ? () => _runConfigTask(
                        progressMessage:
                            'Запускаем nfqws и применяем правила nftables...',
                        task: _controller.start,
                      )
                    : null,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Запустить'),
              ),
              FilledButton.tonalIcon(
                onPressed: _canInteract
                    ? () => _runConfigTask(
                        progressMessage: 'Перезапускаем профиль...',
                        task: _controller.restart,
                      )
                    : null,
                icon: const Icon(Icons.autorenew_rounded),
                label: const Text('Перезапустить'),
              ),
              FilledButton.tonalIcon(
                onPressed: _canInteract ? _stop : null,
                style: _heroSurfaceButtonStyle(isDark),
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Остановить'),
              ),
              FilledButton.tonalIcon(
                onPressed: _canInteract ? () => _refreshStatus() : null,
                style: _heroSurfaceButtonStyle(isDark),
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Обновить'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThemeToggle(bool isDark) {
    return Tooltip(
      message: isDark
          ? 'Переключить на светлую тему'
          : 'Переключить на тёмную тему',
      child: IconButton.filledTonal(
        onPressed: widget.onThemeToggle,
        style: IconButton.styleFrom(
          fixedSize: const Size.square(56),
          backgroundColor: Colors.white.withValues(alpha: isDark ? 0.1 : 0.16),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        icon: AnimatedSwitcher(
          duration: _motionDuration,
          switchInCurve: _motionCurve,
          switchOutCurve: Curves.easeOutCubic,
          transitionBuilder: (child, animation) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: _motionCurve,
            );
            return RotationTransition(
              turns: Tween<double>(begin: 0.86, end: 1).animate(curved),
              child: FadeTransition(opacity: curved, child: child),
            );
          },
          child: Icon(
            isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            key: ValueKey<bool>(isDark),
          ),
        ),
      ),
    );
  }

  ButtonStyle _heroSurfaceButtonStyle(bool isDark) {
    return FilledButton.styleFrom(
      backgroundColor: Colors.white.withValues(alpha: isDark ? 0.14 : 0.18),
      foregroundColor: Colors.white,
      disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
      disabledForegroundColor: Colors.white.withValues(alpha: 0.46),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide(
        color: Colors.white.withValues(alpha: isDark ? 0.2 : 0.26),
      ),
    );
  }

  Widget _buildParametersCard(AppStatus? status) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Параметры запуска',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              status?.privilegeSummary ??
                  'Инициализация runtime ещё не завершена. После неё станут доступны реальные пути, статус nftables и запуск.',
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                StatusPill(
                  label: 'Runtime',
                  value: status?.runtimeReady == true
                      ? 'Подготовлен'
                      : 'Инициализация',
                  color: const Color(0xFF0F7C70),
                  icon: Icons.folder_special_rounded,
                ),
                StatusPill(
                  label: 'Privilege',
                  value: status?.rootSession == true
                      ? 'root'
                      : status?.pkexecAvailable == true
                      ? 'pkexec'
                      : 'нужен root',
                  color: const Color(0xFF1F5A86),
                  icon: Icons.admin_panel_settings_rounded,
                ),
                StatusPill(
                  label: 'Обновлено',
                  value: status?.updatedAt ?? 'ещё нет',
                  color: const Color(0xFFF06A3F),
                  icon: Icons.schedule_rounded,
                ),
              ],
            ),
            const SizedBox(height: 22),
            LayoutBuilder(
              builder: (context, constraints) {
                final firstRowColumns = constraints.maxWidth >= 940
                    ? 3
                    : constraints.maxWidth >= 620
                    ? 2
                    : 1;
                final firstRowWidth =
                    (constraints.maxWidth - (firstRowColumns - 1) * 16) /
                    firstRowColumns;
                final extraColumns = constraints.maxWidth >= 820 ? 2 : 1;
                final extraWidth =
                    (constraints.maxWidth - (extraColumns - 1) * 16) /
                    extraColumns;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        SizedBox(
                          width: firstRowWidth,
                          child: TextField(
                            controller: _queueController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'NFQUEUE',
                              helperText: 'Номер очереди для nft queue',
                            ),
                          ),
                        ),
                        SizedBox(
                          width: firstRowWidth,
                          child: TextField(
                            controller: _tcpPortsController,
                            decoration: const InputDecoration(
                              labelText: 'TCP-порты',
                              helperText: 'Например, 80,443',
                            ),
                          ),
                        ),
                        SizedBox(
                          width: firstRowWidth,
                          child: TextField(
                            controller: _udpPortsController,
                            enabled: _enableQuic,
                            decoration: const InputDecoration(
                              labelText: 'UDP-порты',
                              helperText: 'Обычно 443',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.34),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).dividerColor.withValues(alpha: 0.9),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          children: [
                            SwitchListTile.adaptive(
                              value: _enableQuic,
                              onChanged: _canInteract
                                  ? (value) =>
                                        setState(() => _enableQuic = value)
                                  : null,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              title: const Text('Включить UDP/QUIC секцию'),
                              subtitle: const Text(
                                'Если отключить, профиль останется только с TCP fake+split секцией.',
                              ),
                            ),
                            Divider(
                              height: 1,
                              color: Theme.of(
                                context,
                              ).dividerColor.withValues(alpha: 0.7),
                            ),
                            SwitchListTile.adaptive(
                              value: _hookForwardTraffic,
                              onChanged: _canInteract
                                  ? (value) => setState(
                                      () => _hookForwardTraffic = value,
                                    )
                                  : null,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              title: const Text('Подключать chain forward'),
                              subtitle: const Text(
                                'Полезно, если этот хост будет прокидывать трафик дальше, а не только обслуживать свой output.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        SizedBox(
                          width: extraWidth,
                          child: TextField(
                            controller: _tcpExtraController,
                            minLines: 4,
                            maxLines: 7,
                            decoration: const InputDecoration(
                              labelText: 'Доп. nfqws args для TCP',
                              hintText: '--dpi-desync-autottl=-1:3-20',
                            ),
                          ),
                        ),
                        SizedBox(
                          width: extraWidth,
                          child: TextField(
                            controller: _udpExtraController,
                            enabled: _enableQuic,
                            minLines: 4,
                            maxLines: 7,
                            decoration: const InputDecoration(
                              labelText: 'Доп. nfqws args для UDP',
                              hintText: '--dpi-desync-udplen-increment=2',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 22),
            FilledButton.tonalIcon(
              onPressed: _canInteract
                  ? () => _runConfigTask(
                      progressMessage: 'Сохраняем профиль...',
                      task: _controller.saveConfig,
                    )
                  : null,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Сохранить профиль'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogsCard(AppStatus? status, String logText, bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Логи и диагностика',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        status?.message ??
                            'Логи helper-а и nfqws доступны сразу после первого обновления статуса.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: _canInteract ? () => _refreshStatus() : null,
                  icon: const Icon(Icons.sync_rounded),
                  label: const Text('Обновить'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                StatusPill(
                  label: 'Runtime',
                  value: status?.runtimeReady == true
                      ? 'Готов'
                      : 'Инициализация',
                  color: const Color(0xFF0F7C70),
                  icon: Icons.folder_special_rounded,
                ),
                StatusPill(
                  label: 'Источник',
                  value: _logView == _LogView.helper ? 'Helper' : 'nfqws',
                  color: const Color(0xFF1F5A86),
                  icon: _logView == _LogView.helper
                      ? Icons.rule_rounded
                      : Icons.terminal_rounded,
                ),
                StatusPill(
                  label: 'Обновлено',
                  value: status?.updatedAt ?? 'ещё нет',
                  color: const Color(0xFFF06A3F),
                  icon: Icons.schedule_rounded,
                ),
              ],
            ),
            const SizedBox(height: 20),
            SegmentedButton<_LogView>(
              segments: const [
                ButtonSegment<_LogView>(
                  value: _LogView.helper,
                  label: Text('Helper'),
                  icon: Icon(Icons.rule_rounded),
                ),
                ButtonSegment<_LogView>(
                  value: _LogView.nfqws,
                  label: Text('nfqws'),
                  icon: Icon(Icons.terminal_rounded),
                ),
              ],
              selected: <_LogView>{_logView},
              onSelectionChanged: (values) {
                setState(() => _logView = values.first);
              },
            ),
            const SizedBox(height: 18),
            AnimatedContainer(
              duration: _motionDuration,
              curve: _motionCurve,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF081216)
                    : const Color(0xFFFEF8EF),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF1F353C)
                      : const Color(0xFFE0D2BF),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: SizedBox(
                  width: double.infinity,
                  height: 320,
                  child: Scrollbar(
                    controller: _logScrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _logScrollController,
                      padding: const EdgeInsets.only(right: 8),
                      child: SelectionArea(
                        child: Text(
                          logText,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: isDark
                                ? const Color(0xFFE8FFFA)
                                : const Color(0xFF23353D),
                            height: 1.42,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Runtime: ${status?.runtimePath ?? 'готовится...'}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabIsland(bool isDark) {
    final scheme = Theme.of(context).colorScheme;
    final borderColor = Theme.of(context).dividerColor.withValues(alpha: 0.85);

    return AnimatedContainer(
      duration: _motionDuration,
      curve: _motionCurve,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(maxWidth: 240),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).cardTheme.color?.withValues(alpha: isDark ? 0.88 : 0.92),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: isDark ? 0.28 : 0.12),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTabIslandButton(
            tab: _DashboardTab.control,
            icon: Icons.space_dashboard_rounded,
            tooltip: 'Основной экран',
            isDark: isDark,
            scheme: scheme,
          ),
          _buildTabIslandButton(
            tab: _DashboardTab.logs,
            icon: Icons.terminal_rounded,
            tooltip: 'Логи',
            isDark: isDark,
            scheme: scheme,
          ),
        ],
      ),
    );
  }

  Widget _buildTabIslandButton({
    required _DashboardTab tab,
    required IconData icon,
    required String tooltip,
    required bool isDark,
    required ColorScheme scheme,
  }) {
    final selected = _activeTab == tab;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => _selectTab(tab),
            child: AnimatedContainer(
              duration: _motionDuration,
              curve: _motionCurve,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: selected
                    ? scheme.primary.withValues(alpha: isDark ? 0.22 : 0.16)
                    : Colors.transparent,
              ),
              child: Icon(
                icon,
                color: selected
                    ? scheme.primary
                    : Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop();

  static const _motionDuration = Duration(milliseconds: 520);
  static const _motionCurve = Curves.easeInOutCubicEmphasized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedContainer(
            duration: _motionDuration,
            curve: _motionCurve,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? const [Color(0xFF071014), Color(0xFF0B161A)]
                    : const [Color(0xFFF6F1E8), Color(0xFFF9F6EF)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),
        Positioned(
          top: -110,
          right: -80,
          child: _bubble(
            320,
            scheme.primary.withValues(alpha: isDark ? 0.14 : 0.16),
          ),
        ),
        Positioned(
          top: 190,
          left: -100,
          child: _bubble(
            250,
            scheme.tertiary.withValues(alpha: isDark ? 0.1 : 0.14),
          ),
        ),
        Positioned(
          bottom: -30,
          right: 120,
          child: _bubble(
            210,
            scheme.secondary.withValues(alpha: isDark ? 0.12 : 0.14),
          ),
        ),
      ],
    );
  }

  Widget _bubble(double size, Color color) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}
