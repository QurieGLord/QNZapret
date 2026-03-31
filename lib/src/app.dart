import 'dart:async';

import 'package:flutter/material.dart';

import 'models/app_config.dart';
import 'models/app_status.dart';
import 'services/nzapret_controller.dart';
import 'theme/app_theme.dart';
import 'widgets/status_pill.dart';

enum _LogView { helper, nfqws }

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
  static const _motionDuration = Duration(milliseconds: 420);
  static const _motionCurve = Curves.easeInOutCubicEmphasized;

  final _logScrollController = ScrollController();

  AppConfig _config = AppConfig.defaults;
  AppStatus? _status;
  bool _busy = true;
  bool _logsExpanded = true;
  String _activityMessage =
      'Инициализируем runtime и подготавливаем профиль...';
  _LogView _logView = _LogView.helper;
  Timer? _timer;

  bool get _canInteract => !_busy && _status != null;
  NzapretController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshStatus(silent: true),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
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
      setState(() {
        _config = config;
        _status = status;
        _busy = false;
        _activityMessage =
            'Runtime готов. Профиль уже сохранён, можно запускать сервис, быстро перезапускать его и смотреть live-логи ниже.';
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

  Future<void> _runConfigTask({
    required String progressMessage,
    required Future<CommandOutcome> Function(AppConfig config) task,
  }) async {
    try {
      setState(() {
        _busy = true;
        _activityMessage = progressMessage;
      });
      final outcome = await task(_config);
      await _refreshStatus(silent: true);
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _activityMessage = outcome.message;
      });
      _showSnack(outcome);
    } catch (error) {
      if (!mounted) {
        return;
      }
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

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final logText = switch (_logView) {
      _LogView.helper => status?.helperLogTail ?? 'Лог helper-а пока пуст.',
      _LogView.nfqws => status?.nfqwsLogTail ?? 'Лог nfqws пока пуст.',
    };

    return Scaffold(
      body: Stack(
        children: [
          const _Backdrop(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final horizontalPadding = constraints.maxWidth >= 940
                    ? 30.0
                    : 18.0;

                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    24,
                    horizontalPadding,
                    28,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHero(status, isDark),
                          const SizedBox(height: 22),
                          _buildLogsPanel(status, logText, isDark),
                        ],
                      ),
                    ),
                  ),
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
    final scheme = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: _motionDuration,
      curve: _motionCurve,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(42),
        gradient: LinearGradient(
          colors: isDark
              ? const [Color(0xFF081E27), Color(0xFF0E3842), Color(0xFF1D7C73)]
              : const [Color(0xFFFCFCF8), Color(0xFFF4F8F5), Color(0xFFE5F0EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFD6E4DB),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.22)
                : const Color(0xFFB6CFC3).withValues(alpha: 0.28),
            blurRadius: 42,
            offset: const Offset(0, 22),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'NZapret Desktop',
                      style: Theme.of(context).textTheme.displayMedium
                          ?.copyWith(
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF143239),
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Один компактный экран для статуса сервиса, управления nfqws и быстрой диагностики без перегруженной панели параметров.',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.84)
                            : const Color(0xFF496067),
                        height: 1.28,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _buildThemeToggle(isDark),
            ],
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              StatusPill(
                label: 'Сервис',
                value: running ? 'Активен' : 'Остановлен',
                color: running
                    ? const Color(0xFF4CC9A6)
                    : const Color(0xFFE38B57),
                icon: running ? Icons.bolt_rounded : Icons.pause_circle_rounded,
              ),
              StatusPill(
                label: 'nftables',
                value: status?.nftAvailable == true ? 'Готов' : 'Не найден',
                color: const Color(0xFF6CA7F2),
                icon: Icons.rule_rounded,
              ),
              StatusPill(
                label: 'Доступ',
                value: status?.rootSession == true
                    ? 'root'
                    : status?.pkexecAvailable == true
                    ? 'pkexec'
                    : 'ограничен',
                color: const Color(0xFFB28AF0),
                icon: Icons.admin_panel_settings_rounded,
              ),
              StatusPill(
                label: 'Обновлено',
                value: status?.updatedAt ?? 'ещё нет',
                color: const Color(0xFFDA7F63),
                icon: Icons.schedule_rounded,
              ),
            ],
          ),
          const SizedBox(height: 22),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.9),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status?.message ?? _activityMessage,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: isDark ? Colors.white : const Color(0xFF1C353A),
                    fontWeight: FontWeight.w700,
                    height: 1.28,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _activityMessage,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.78)
                        : const Color(0xFF566E72),
                    height: 1.34,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _InlineMetaChip(
                      icon: Icons.memory_rounded,
                      label: 'PID',
                      value: status?.pid?.toString() ?? 'нет процесса',
                    ),
                    _InlineMetaChip(
                      icon: Icons.folder_special_rounded,
                      label: 'Runtime',
                      value: status?.runtimeReady == true
                          ? 'подготовлен'
                          : 'инициализация',
                    ),
                    _InlineMetaChip(
                      icon: Icons.tune_rounded,
                      label: 'Профиль',
                      value: _config.enableQuic
                          ? 'TCP + UDP/QUIC'
                          : 'только TCP',
                    ),
                    _InlineMetaChip(
                      icon: Icons.call_split_rounded,
                      label: 'Forward',
                      value: _config.hookForwardTraffic
                          ? 'включён'
                          : 'выключен',
                    ),
                  ],
                ),
              ],
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
                style: _softButtonStyle(
                  isDark: isDark,
                  foregroundColor: isDark
                      ? Colors.white
                      : const Color(0xFF284149),
                ),
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Остановить'),
              ),
              FilledButton.tonalIcon(
                onPressed: _canInteract ? () => _refreshStatus() : null,
                style: _softButtonStyle(
                  isDark: isDark,
                  foregroundColor: scheme.primary,
                ),
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
          backgroundColor: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.9),
          foregroundColor: isDark ? Colors.white : const Color(0xFF214048),
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

  ButtonStyle _softButtonStyle({
    required bool isDark,
    required Color foregroundColor,
  }) {
    return FilledButton.styleFrom(
      backgroundColor: isDark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.white.withValues(alpha: 0.74),
      foregroundColor: foregroundColor,
      disabledBackgroundColor: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.white.withValues(alpha: 0.45),
      disabledForegroundColor: foregroundColor.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.92),
      ),
    );
  }

  Widget _buildLogsPanel(AppStatus? status, String logText, bool isDark) {
    final headerColor = isDark ? Colors.white : const Color(0xFF183137);
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.74)
        : const Color(0xFF62777B);

    return AnimatedContainer(
      duration: _motionDuration,
      curve: _motionCurve,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(36),
        color: isDark
            ? const Color(0xFF0E171B).withValues(alpha: 0.86)
            : Colors.white.withValues(alpha: 0.76),
        border: Border.all(
          color: isDark ? const Color(0xFF1B3036) : const Color(0xFFE2EBE4),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.16)
                : const Color(0xFFCADBD0).withValues(alpha: 0.22),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => setState(() => _logsExpanded = !_logsExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Логи и диагностика',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(color: headerColor),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Ниже только live-лог helper-а и nfqws в одном раскрывающемся блоке.',
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(color: subColor, height: 1.28),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    AnimatedRotation(
                      duration: _motionDuration,
                      curve: _motionCurve,
                      turns: _logsExpanded ? 0.5 : 0,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 30,
                        color: headerColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              duration: _motionDuration,
              sizeCurve: _motionCurve,
              firstCurve: _motionCurve,
              secondCurve: _motionCurve,
              crossFadeState: _logsExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  status?.message ??
                      'Раскрой блок, чтобы посмотреть текущий лог helper-а или nfqws.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: subColor),
                ),
              ),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
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
                        OutlinedButton.icon(
                          onPressed: _canInteract
                              ? () => _refreshStatus()
                              : null,
                          icon: const Icon(Icons.sync_rounded),
                          label: const Text('Обновить'),
                        ),
                        StatusPill(
                          label: 'Источник',
                          value: _logView == _LogView.helper
                              ? 'Helper'
                              : 'nfqws',
                          color: const Color(0xFF7E9EF0),
                          icon: _logView == _LogView.helper
                              ? Icons.rule_rounded
                              : Icons.terminal_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 240),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF081014)
                            : const Color(0xFFF9FBF7),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF20363D)
                              : const Color(0xFFDCE7DF),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: SizedBox(
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
                                        ? const Color(0xFFE7FFF6)
                                        : const Color(0xFF264046),
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Runtime: ${status?.runtimePath ?? 'готовится...'}',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: subColor),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineMetaChip extends StatelessWidget {
  const _InlineMetaChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.9),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              '$label: $value',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.88),
              ),
            ),
          ],
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
                    ? const [Color(0xFF060D10), Color(0xFF0A1418)]
                    : const [Color(0xFFF7F4EE), Color(0xFFEFF5F0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        ),
        Positioned(
          top: -140,
          right: -90,
          child: _glow(
            360,
            scheme.primary.withValues(alpha: isDark ? 0.14 : 0.18),
          ),
        ),
        Positioned(
          top: 180,
          left: -120,
          child: _glow(
            300,
            scheme.secondary.withValues(alpha: isDark ? 0.08 : 0.12),
          ),
        ),
        Positioned(
          bottom: -50,
          right: 40,
          child: _glow(
            260,
            scheme.tertiary.withValues(alpha: isDark ? 0.1 : 0.13),
          ),
        ),
      ],
    );
  }

  Widget _glow(double size, Color color) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}
