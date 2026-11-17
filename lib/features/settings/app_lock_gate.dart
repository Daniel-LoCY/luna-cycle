import 'dart:async';

import 'package:local_auth/local_auth.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  final _authentication = LocalAuthentication();
  bool _verified = false;
  bool _authenticating = false;
  bool _attemptScheduled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (!_authenticating && _isEnabled) {
        setState(() {
          _verified = false;
          _error = null;
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(localReminderServiceProvider).rescheduleSafely());
      if (_isEnabled && !_verified) unawaited(_authenticate());
    }
  }

  bool get _isEnabled =>
      ref.read(appLockEnabledProvider).asData?.value ?? false;

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockEnabledProvider);
    if (lock.isLoading) {
      return const Material(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('載入隱私設定…'),
            ],
          ),
        ),
      );
    }
    if (lock.hasError) {
      return const Material(
        child: Center(child: Text('無法讀取隱私設定。請重新開啟 Luna Cycle。')),
      );
    }
    if (lock.value != true) {
      _verified = false;
      return widget.child;
    }
    if (!_verified && !_authenticating && !_attemptScheduled) {
      _attemptScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _attemptScheduled = false;
        if (mounted && !_verified) unawaited(_authenticate());
      });
    }
    if (_verified) return widget.child;
    return Material(
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Luna Cycle 已鎖定',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text('使用指紋、臉部辨識或裝置螢幕鎖解鎖。'),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _authenticating ? null : _authenticate,
                  icon: const Icon(Icons.fingerprint_rounded),
                  label: Text(_authenticating ? '驗證中…' : '解鎖'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _authenticate() async {
    if (_authenticating || !_isEnabled) return;
    setState(() {
      _authenticating = true;
      _error = null;
    });
    try {
      final unlocked = await _authentication.authenticate(
        localizedReason: '解鎖以查看你的個人健康紀錄',
        biometricOnly: false,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: true,
      );
      if (mounted && unlocked) setState(() => _verified = true);
    } catch (_) {
      if (mounted) setState(() => _error = '無法完成裝置驗證，請再試一次。');
    } finally {
      if (mounted) setState(() => _authenticating = false);
    }
  }
}
