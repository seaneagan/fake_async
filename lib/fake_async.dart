// Copyright 2014 Google Inc. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

library fake_async;

import 'dart:async';
import 'dart:collection';

import 'package:clock/clock.dart' as clock;

/// Allows one to fake asynchronous events such as timers and microtasks in
/// order to test for them deterministically and without delay.
///
/// Use [run] to execute test code in a [Zone] which mocks out the [Timer] and
/// [scheduleMicrotask] APIs to instead store their callbacks for execution by
/// subsequent calls to [elapse] which simulates the asynchronous passage of
/// time, which can be measured at any point via [elapsed].  The microtask queue
/// is drained surrounding each timer to simulate the real event queue.
///
/// The synchronous passage of time (blocking or expensive calls) can also be
/// simulated using [elapseBlocking].
abstract class FakeAsync {
  /// [initialTime] controls the value of [clock.now] within [run]
  /// callbacks.  It defaults to the value of [clock.now] immediately before
  /// the [run] callback.
  factory FakeAsync({DateTime initialTime}) = _FakeAsync;

  FakeAsync._();

  /// Returns the total amount of time elapsed by calls to [elapse] and
  /// [elapseBlocking].
  Duration get elapsed;

  /// Simulates the asynchronous passage of time.
  ///
  /// **This should only be called from within the zone used by [run].**
  ///
  /// If [duration] is negative, the returned future completes with an
  /// [ArgumentError].
  ///
  /// If a previous call to [elapse] has not yet completed, throws a
  /// [StateError].
  ///
  /// Any Timers created within the Zone used by [run], which are to expire
  /// at or before the new time after [duration] has elapsed, are run.
  /// The microtask queue is processed surrounding each timer.  When a timer is
  /// run, [elapsed] will have been advanced by the timer's specified
  /// duration.  Calls to [elapseBlocking] from within these timers and
  /// microtasks which cause more time to be [elapsed] than the specified
  /// [duration], can cause more timers to expire and thus be run.
  ///
  /// Once all expired timers are processed, [elapsed] is advanced (as
  /// necessary) to its initial value upon calling this method + [duration].
  void elapse(Duration duration);

  /// Simulates the synchronous passage of time, resulting from blocking or
  /// expensive calls.
  ///
  /// Neither timers nor microtasks are run during this call.  Upon return,
  /// [elapsed] will have increased by [duration].
  ///
  /// If [duration] is negative, throws an [ArgumentError].
  void elapseBlocking(Duration duration);

  /// Runs [callback] in a [Zone] with fake timer and microtask scheduling.
  ///
  /// Uses
  /// [ZoneSpecification.createTimer], [ZoneSpecification.createPeriodicTimer],
  /// and [ZoneSpecification.scheduleMicrotask] to store callbacks for later
  /// execution within the zone via calls to [elapse].
  ///
  /// The [callback] is called with `this` as argument.
  run(callback(FakeAsync self));

  /// Runs all remaining microtasks, including those scheduled as a result of
  /// running them, until there are no more microtasks scheduled.
  ///
  /// Does not run timers.
  void flushMicrotasks();

  /// The number of created periodic timers that have not been canceled.
  int get periodicTimerCount;

  /// The number of pending non periodic timers that have not been canceled.
  int get nonPeriodicTimerCount;

  /// The number of pending microtasks.
  int get microtaskCount;
}

class _FakeAsync extends FakeAsync {
  Duration _elapsed = Duration.ZERO;
  Duration get elapsed => _elapsed;
  Duration _elapsingTo;
  DateTime _initialTime;

  _FakeAsync({DateTime initialTime})
      : super._(),
        _initialTime = initialTime {}

  @override
  void elapse(Duration duration) {
    if (duration.inMicroseconds < 0) {
      throw new ArgumentError('Cannot call elapse with negative duration');
    }
    if (_elapsingTo != null) {
      throw new StateError('Cannot elapse until previous elapse is complete.');
    }
    _elapsingTo = _elapsed + duration;
    _drainMicrotasks();
    Timer next;
    while ((next = _getNextTimer()) != null) {
      _runTimer(next);
      _drainMicrotasks();
    }
    _elapseTo(_elapsingTo);
    _elapsingTo = null;
  }

  @override
  void elapseBlocking(Duration duration) {
    if (duration.inMicroseconds < 0) {
      throw new ArgumentError('Cannot call elapse with negative duration');
    }
    _elapsed += duration;
    if (_elapsingTo != null && _elapsed > _elapsingTo) {
      _elapsingTo = _elapsed;
    }
  }

  @override
  void run(callback(FakeAsync self)) {
    if (_zone == null) {
      _zone = Zone.current.fork(specification: _zoneSpec);
    }
    var currentElapsed = _elapsed;
    var fakeClock = new clock.Clock(
        initialTime: _initialTime, elapsed: () => _elapsed - currentElapsed);
    return _zone
        .runGuarded(() => clock.withClock(fakeClock, () => callback(this)));
  }

  Zone _zone;

  @override
  void flushMicrotasks() {
    _drainMicrotasks();
  }

  @override
  int get periodicTimerCount =>
      _timers.where((_FakeTimer timer) => timer._isPeriodic).length;

  @override
  int get nonPeriodicTimerCount =>
      _timers.where((_FakeTimer timer) => !timer._isPeriodic).length;

  @override
  int get microtaskCount => _microtasks.length;

  ZoneSpecification get _zoneSpec => new ZoneSpecification(
          createTimer: (_, __, ___, Duration duration, Function callback) {
        return _createTimer(duration, callback, false);
      }, createPeriodicTimer:
              (_, __, ___, Duration duration, Function callback) {
        return _createTimer(duration, callback, true);
      }, scheduleMicrotask: (_, __, ___, Function microtask) {
        _microtasks.add(microtask);
      });

  _elapseTo(Duration to) {
    if (to > _elapsed) {
      _elapsed = to;
    }
  }

  Queue<Function> _microtasks = new Queue();

  Set<_FakeTimer> _timers = new Set<_FakeTimer>();
  bool _waitingForTimer = false;

  Timer _createTimer(Duration duration, Function callback, bool isPeriodic) {
    var timer = new _FakeTimer._(duration, callback, isPeriodic, this);
    _timers.add(timer);
    return timer;
  }

  _FakeTimer _getNextTimer() {
    return _minOf(_timers.where((timer) => timer._nextCall <= _elapsingTo),
        (timer1, timer2) => timer1._nextCall.compareTo(timer2._nextCall));
  }

  _runTimer(_FakeTimer timer) {
    assert(timer.isActive);
    _elapseTo(timer._nextCall);
    if (timer._isPeriodic) {
      timer._callback(timer);
      timer._nextCall += timer._duration;
    } else {
      timer._callback();
      _timers.remove(timer);
    }
  }

  _drainMicrotasks() {
    while (_microtasks.isNotEmpty) {
      _microtasks.removeFirst()();
    }
  }

  _hasTimer(_FakeTimer timer) => _timers.contains(timer);

  _cancelTimer(_FakeTimer timer) => _timers.remove(timer);
}

class _FakeTimer implements Timer {
  final Duration _duration;
  final Function _callback;
  final bool _isPeriodic;
  final _FakeAsync _async;
  Duration _nextCall;

  // TODO: In browser JavaScript, timers can only run every 4 milliseconds once
  // sufficiently nested:
  //     http://www.w3.org/TR/html5/webappapis.html#timer-nesting-level
  // Without some sort of delay this can lead to infinitely looping timers.
  // What do the dart VM and dart2js timers do here?
  static const _minDuration = Duration.ZERO;

  _FakeTimer._(Duration duration, this._callback, this._isPeriodic, this._async)
      : _duration = duration < _minDuration ? _minDuration : duration {
    _nextCall = _async.elapsed + _duration;
  }

  bool get isActive => _async._hasTimer(this);

  cancel() => _async._cancelTimer(this);
}

/**
 * Returns the minimum value in [i], according to the order specified by the
 * [compare] function, or `null` if [i] is empty.
 *
 * The compare function must act as a [Comparator]. If [compare] is omitted,
 * [Comparable.compare] is used. If [i] contains null elements, an exception
 * will be thrown.
 */
// TODO: Move this to a "compare" package, see
// https://github.com/google/quiver-dart/pull/119
dynamic _minOf(Iterable i, [Comparator compare = Comparable.compare]) =>
    i.isEmpty ? null : i.reduce((a, b) => compare(a, b) < 0 ? a : b);
