import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_player_providers.dart';

/// Upravlja "sleep timer" - samodejno pavzira predvajanje po nastavljenem
/// času (glej `player_screen.dart`, bedtime ikona + izbirni dialog). Stanje
/// je preostali čas do pavze (`null` če timer ni aktiven), da lahko UI
/// prikaže odštevanje.
class SleepTimerController extends StateNotifier<Duration?>
    with WidgetsBindingObserver {
  SleepTimerController(this._ref) : super(null) {
    WidgetsBinding.instance.addObserver(this);
  }

  final Ref _ref;
  Timer? _pauseTimer;
  Timer? _displayTimer;
  DateTime? _endTime;

  /// Za dejansko pavzo uporabi en sam timer. Sekundni timer obstaja samo za
  /// prikaz odštevanja v ospredju in se ustavi, ko aplikacija ni aktivna.
  void start(Duration duration) {
    cancel();
    _endTime = DateTime.now().add(duration);
    state = duration;
    _pauseTimer = Timer(duration, _complete);
    _startDisplayTimer();
  }

  /// Prekliče aktiven timer brez pavze predvajanja.
  void cancel() {
    _pauseTimer?.cancel();
    _displayTimer?.cancel();
    _pauseTimer = null;
    _displayTimer = null;
    _endTime = null;
    state = null;
  }

  void _startDisplayTimer() {
    if (_displayTimer != null || _endTime == null) return;
    _displayTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateDisplay(),
    );
  }

  void _updateDisplay() {
    final endTime = _endTime;
    if (endTime == null) return;
    final remaining = endTime.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _complete();
    } else {
      state = remaining;
    }
  }

  void _complete() {
    _pauseTimer?.cancel();
    _displayTimer?.cancel();
    _pauseTimer = null;
    _displayTimer = null;
    _endTime = null;
    state = null;
    _ref.read(audioHandlerProvider).pause();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_endTime == null) return;
    if (state == AppLifecycleState.resumed) {
      _updateDisplay();
      _startDisplayTimer();
    } else {
      _displayTimer?.cancel();
      _displayTimer = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pauseTimer?.cancel();
    _displayTimer?.cancel();
    super.dispose();
  }
}

/// Preostali čas sleep timerja, `null` če ni aktiven.
final sleepTimerProvider =
    StateNotifierProvider<SleepTimerController, Duration?>((ref) {
      return SleepTimerController(ref);
    });
