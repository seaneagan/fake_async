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

library fake_async_test;

import 'dart:async';

import 'package:clock/clock.dart' as clock;
import 'package:fake_async/fake_async.dart';
import 'package:unittest/unittest.dart';

main() {
  group('FakeAsync', () {
    var elapseBy = const Duration(days: 1);

    test('should initialize elapsed to zero', () {
      expect(new FakeAsync().elapsed, Duration.ZERO);
    });

    test('should have correct clock.now value', () {
      var initialTime = new DateTime(2014, 3, 6);
      new FakeAsync(initialTime: initialTime).run((async) {
        expect(clock.now, initialTime);
        async.elapse(elapseBy);
        expect(clock.now, initialTime.add(elapseBy));
      });
    });

    test('should have correct clock.getStopwatch() value', () {
      new FakeAsync().run((async) {
        var stopwatch = clock.getStopwatch()..start();
        expect(stopwatch.elapsed, Duration.ZERO);
        async.elapse(const Duration(seconds: 1));
        expect(stopwatch.elapsed, const Duration(seconds: 1));
      });
    });

    group('elapseBlocking', () {
      test('should elapse time without calling timers', () {
        new FakeAsync().run((async) {
          var timerCalled = false;
          new Timer(elapseBy ~/ 2, () => timerCalled = true);
          async.elapseBlocking(elapseBy);
          expect(timerCalled, isFalse);
        });
      });

      test('should elapse time by the specified amount', () {
        var it = new FakeAsync();
        it.elapseBlocking(elapseBy);
        expect(it.elapsed, elapseBy);
      });

      test('should throw when called with a negative duration', () {
        expect(() {
          new FakeAsync().elapseBlocking(const Duration(days: -1));
        }, throwsA(new isInstanceOf<ArgumentError>()));
      });
    });

    group('elapse', () {
      test('should elapse time by the specified amount', () {
        new FakeAsync().run((async) {
          async.elapse(elapseBy);
          expect(async.elapsed, elapseBy);
        });
      });

      test('should throw ArgumentError when called with a negative duration',
          () {
        expect(() => new FakeAsync().elapse(const Duration(days: -1)),
            throwsA(new isInstanceOf<ArgumentError>()));
      });

      test('should throw when called before previous call is complete', () {
        new FakeAsync().run((async) {
          var error;
          new Timer(elapseBy ~/ 2, () {
            try {
              async.elapse(elapseBy);
            } catch (e) {
              error = e;
            }
          });
          async.elapse(elapseBy);
          expect(error, new isInstanceOf<StateError>());
        });
      });

      group('when creating timers', () {
        test('should call timers expiring before or at end time', () {
          new FakeAsync().run((async) {
            var beforeCallCount = 0;
            var atCallCount = 0;
            new Timer(elapseBy ~/ 2, () {
              beforeCallCount++;
            });
            new Timer(elapseBy, () {
              atCallCount++;
            });
            async.elapse(elapseBy);
            expect(beforeCallCount, 1);
            expect(atCallCount, 1);
          });
        });

        test('should call timers expiring due to elapseBlocking', () {
          new FakeAsync().run((async) {
            bool secondaryCalled = false;
            new Timer(elapseBy, () {
              async.elapseBlocking(elapseBy);
            });
            new Timer(elapseBy * 2, () {
              secondaryCalled = true;
            });
            async.elapse(elapseBy);
            expect(secondaryCalled, isTrue);
            expect(async.elapsed, elapseBy * 2);
          });
        });

        test('should call timers at their scheduled time', () {
          new FakeAsync().run((async) {
            Duration calledAt;
            var periodicCalledAt = <Duration>[];
            new Timer(elapseBy ~/ 2, () {
              calledAt = async.elapsed;
            });
            new Timer.periodic(elapseBy ~/ 2, (_) {
              periodicCalledAt.add(async.elapsed);
            });
            async.elapse(elapseBy);
            expect(calledAt, elapseBy ~/ 2);
            expect(periodicCalledAt, [elapseBy ~/ 2, elapseBy]);
          });
        });

        test('should not call timers expiring after end time', () {
          new FakeAsync().run((async) {
            var timerCallCount = 0;
            new Timer(elapseBy * 2, () {
              timerCallCount++;
            });
            async.elapse(elapseBy);
            expect(timerCallCount, 0);
          });
        });

        test('should not call canceled timers', () {
          new FakeAsync().run((async) {
            int timerCallCount = 0;
            var timer = new Timer(elapseBy ~/ 2, () {
              timerCallCount++;
            });
            timer.cancel();
            async.elapse(elapseBy);
            expect(timerCallCount, 0);
          });
        });

        test('should call periodic timers each time the duration elapses', () {
          new FakeAsync().run((async) {
            var periodicCallCount = 0;
            new Timer.periodic(elapseBy ~/ 10, (_) {
              periodicCallCount++;
            });
            async.elapse(elapseBy);
            expect(periodicCallCount, 10);
          });
        });

        test('should process microtasks surrounding each timer', () {
          new FakeAsync().run((async) {
            var microtaskCalls = 0;
            var timerCalls = 0;
            scheduleMicrotasks() {
              for (int i = 0; i < 5; i++) {
                scheduleMicrotask(() => microtaskCalls++);
              }
            }

            scheduleMicrotasks();
            new Timer.periodic(elapseBy ~/ 5, (_) {
              timerCalls++;
              expect(microtaskCalls, 5 * timerCalls);
              scheduleMicrotasks();
            });
            async.elapse(elapseBy);
            expect(timerCalls, 5);
            expect(microtaskCalls, 5 * (timerCalls + 1));
          });
        });

        test('should pass the periodic timer itself to callbacks', () {
          new FakeAsync().run((async) {
            Timer passedTimer;
            Timer periodic = new Timer.periodic(elapseBy, (timer) {
              passedTimer = timer;
            });
            async.elapse(elapseBy);
            expect(periodic, same(passedTimer));
          });
        });

        test('should call microtasks before advancing time', () {
          new FakeAsync().run((async) {
            Duration calledAt;
            scheduleMicrotask(() {
              calledAt = async.elapsed;
            });
            async.elapse(const Duration(minutes: 1));
            expect(calledAt, Duration.ZERO);
          });
        });

        test('should add event before advancing time', () {
          return new Future(() => new FakeAsync().run((async) {
                var controller = new StreamController();
                var ret = controller.stream.first.then((_) {
                  expect(async.elapsed, Duration.ZERO);
                });
                controller.add(null);
                async.elapse(const Duration(minutes: 1));
                return ret;
              }));
        });

        test('should increase negative duration timers to zero duration', () {
          new FakeAsync().run((async) {
            var negativeDuration = const Duration(days: -1);
            Duration calledAt;
            new Timer(negativeDuration, () {
              calledAt = async.elapsed;
            });
            async.elapse(const Duration(minutes: 1));
            expect(calledAt, Duration.ZERO);
          });
        });

        test('should not be additive with elapseBlocking', () {
          new FakeAsync().run((async) {
            new Timer(Duration.ZERO, () => async.elapseBlocking(elapseBy * 5));
            async.elapse(elapseBy);
            expect(async.elapsed, elapseBy * 5);
          });
        });

        group('isActive', () {
          test('should be false after timer is run', () {
            new FakeAsync().run((async) {
              var timer = new Timer(elapseBy ~/ 2, () {});
              async.elapse(elapseBy);
              expect(timer.isActive, isFalse);
            });
          });

          test('should be true after periodic timer is run', () {
            new FakeAsync().run((async) {
              var timer = new Timer.periodic(elapseBy ~/ 2, (_) {});
              async.elapse(elapseBy);
              expect(timer.isActive, isTrue);
            });
          });

          test('should be false after timer is canceled', () {
            new FakeAsync().run((async) {
              var timer = new Timer(elapseBy ~/ 2, () {});
              timer.cancel();
              expect(timer.isActive, isFalse);
            });
          });
        });

        test('should work with new Future()', () {
          new FakeAsync().run((async) {
            var callCount = 0;
            new Future(() => callCount++);
            async.elapse(Duration.ZERO);
            expect(callCount, 1);
          });
        });

        test('should work with Future.delayed', () {
          new FakeAsync().run((async) {
            int result;
            new Future.delayed(elapseBy, () => result = 5);
            async.elapse(elapseBy);
            expect(result, 5);
          });
        });

        test('should work with Future.timeout', () {
          new FakeAsync().run((async) {
            var completer = new Completer();
            var timed = completer.future.timeout(elapseBy ~/ 2);
            expect(timed, throwsA(new isInstanceOf<TimeoutException>()));
            async.elapse(elapseBy);
            completer.complete();
          });
        });

        // TODO: Pausing and resuming the timeout Stream doesn't work since
        // it uses `new Stopwatch()`.
        //
        // See https://code.google.com/p/dart/issues/detail?id=18149
        test('should work with Stream.periodic', () {
          new FakeAsync().run((async) {
            var events = <int>[];
            StreamSubscription subscription;
            var periodic =
                new Stream.periodic(const Duration(minutes: 1), (i) => i);
            subscription = periodic.listen(events.add, cancelOnError: true);
            async.elapse(const Duration(minutes: 3));
            subscription.cancel();
            expect(events, [0, 1, 2]);
          });
        });

        test('should work with Stream.timeout', () {
          new FakeAsync().run((async) {
            var events = <int>[];
            var errors = [];
            var controller = new StreamController<int>();
            var timed = controller.stream.timeout(const Duration(minutes: 2));
            var subscription =  timed.listen(events.add,
                onError: errors.add, cancelOnError: true);
            controller.add(0);
            async.elapse(const Duration(minutes: 1));
            expect(events, [0]);
            async.elapse(const Duration(minutes: 1));
            subscription.cancel();
            expect(errors, hasLength(1));
            expect(errors.first, new isInstanceOf<TimeoutException>());
            return controller.close();
          });
        });
      });
    });

    group('flushMicrotasks', () {
      test('should flush a microtask', () {
        new FakeAsync().run((async) {
          bool microtaskRan = false;
          new Future.microtask(() {
            microtaskRan = true;
          });
          expect(microtaskRan, isFalse,
              reason: 'should not flush until asked to');
          async.flushMicrotasks();
          expect(microtaskRan, isTrue);
        });
      });

      test('should flush microtasks scheduled by microtasks in order', () {
        new FakeAsync().run((async) {
          final log = [];
          new Future.microtask(() {
            log.add(1);
            new Future.microtask(() {
              log.add(3);
            });
          });
          new Future.microtask(() {
            log.add(2);
          });
          expect(log, hasLength(0), reason: 'should not flush until asked to');
          async.flushMicrotasks();
          expect(log, [1, 2, 3]);
        });
      });

      test('should not run timers', () {
        new FakeAsync().run((async) {
          final log = [];
          new Future.microtask(() {
            log.add(1);
          });
          new Future(() {
            log.add(2);
          });
          new Timer.periodic(new Duration(seconds: 1), (_) {
            log.add(2);
          });
          async.flushMicrotasks();
          expect(log, [1]);
        });
      });
    });

    group('stats', () {
      test('should report the number of pending microtasks', () {
        new FakeAsync().run((async) {
          expect(async.microtaskCount, 0);
          scheduleMicrotask(() => null);
          expect(async.microtaskCount, 1);
          scheduleMicrotask(() => null);
          expect(async.microtaskCount, 2);
          async.flushMicrotasks();
          expect(async.microtaskCount, 0);
        });
      });

      test('it should report the number of pending periodic timers', () {
        new FakeAsync().run((async) {
          expect(async.periodicTimerCount, 0);
          Timer timer =
              new Timer.periodic(new Duration(minutes: 30), (Timer timer) {});
          expect(async.periodicTimerCount, 1);
          new Timer.periodic(new Duration(minutes: 20), (Timer timer) {});
          expect(async.periodicTimerCount, 2);
          async.elapse(new Duration(minutes: 20));
          expect(async.periodicTimerCount, 2);
          timer.cancel();
          expect(async.periodicTimerCount, 1);
        });
      });

      test('it should report the number of pending non periodic timers', () {
        new FakeAsync().run((async) {
          expect(async.nonPeriodicTimerCount, 0);
          Timer timer = new Timer(new Duration(minutes: 30), () {});
          expect(async.nonPeriodicTimerCount, 1);
          new Timer(new Duration(minutes: 20), () {});
          expect(async.nonPeriodicTimerCount, 2);
          async.elapse(new Duration(minutes: 25));
          expect(async.nonPeriodicTimerCount, 1);
          timer.cancel();
          expect(async.nonPeriodicTimerCount, 0);
        });
      });
    });
  });
}
