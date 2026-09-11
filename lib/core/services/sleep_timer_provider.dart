import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_player_providers.dart';

/// Upravlja "sleep timer" - samodejno pavzira predvajanje po nastavljenem
/// času (glej `player_screen.dart`, bedtime ikona + izbirni dialog). Stanje
/// je preostali čas do pavze (`null` če timer ni aktiven), da lahko UI
/// prikaže odštevanje.
class SleepTimerController extends StateNotifier<Duration?> {
  SleepTimerController(this._ref) : super(null);

  final Ref _ref;
  Timer? _timer;
  DateTime? _endTime;

  /// Zažene (ali zamenja obstoječi) timer za `duration`. Interno tika vsako
  /// sekundo namesto enkratnega `Timer(duration, ...)`, da lahko `state`
  /// sproti prikazuje preostali čas.
  void start(Duration duration) {
    _timer?.cancel();
    _endTime = DateTime.now().add(duration);
    state = duration;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  /// Prekliče aktiven timer brez pavze predvajanja.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _endTime = null;
    state = null;
  }

  void _tick() {
    final endTime = _endTime;
    if (endTime == null) return;
    final remaining = endTime.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _timer?.cancel();
      _timer = null;
      _endTime = null;
      state = null;
      _ref.read(audioHandlerProvider).pause();
    } else {
      state = remaining;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Preostali čas sleep timerja, `null` če ni aktiven.
final sleepTimerProvider =
    StateNotifierProvider<SleepTimerController, Duration?>((ref) {
      return SleepTimerController(ref);
    });
