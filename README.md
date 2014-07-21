fake_async
==========

[![Build Status](https://drone.io/github.com/seaneagan/fake_async/status.png)](https://drone.io/github.com/seaneagan/fake_async/latest)

The `fake_async` package provides a `FakeAsync` class which allows one to fake 
asynchronous events such as timers and microtasks in order to test for them 
deterministically and without delay.

`FakeAsync.run()` can be used to execute the test code in a [Zone][] which mocks 
out the [Timer][] and [scheduleMicrotask][] APIs to instead store their 
callbacks for execution by subsequent calls to `FakeAsync.elapse()` which 
simulates the asynchronous passage of time, which can be measured at any point 
via `FakeAsync.elapsed`.  The microtask queue is drained surrounding each timer 
to simulate the [real event queue][event_queue].

For example:

```dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:unittest/unittest.dart';

void main() {
  test("Future.timeout() throws an error once the timeout is up", () {
    new FakeAsync().run((async) {
      expect(new Completer().future.timeout(new Duration(seconds: 5)),
          throwsA(new isInstanceOf<TimeoutException>()));
      async.elapse(new Duration(seconds: 5));
    });
  });
}
```

[Zone]: https://api.dartlang.org/apidocs/channels/stable/dartdoc-viewer/dart-async.Zone
[Timer]: https://api.dartlang.org/apidocs/channels/stable/dartdoc-viewer/dart-async.Timer
[scheduleMicrotask]: https://api.dartlang.org/apidocs/channels/stable/dartdoc-viewer/dart-async.Zone#id_scheduleMicrotask
[event_queue]: https://www.dartlang.org/articles/event-loop/#darts-event-loop-and-queues
