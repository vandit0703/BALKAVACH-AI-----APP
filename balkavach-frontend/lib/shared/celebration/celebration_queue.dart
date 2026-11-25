import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runs celebration jobs strictly one after another, so a mission approval, a
/// level-up and a new badge that all arrive together play in turn and never
/// stack on screen. A failing job does not stop the ones queued behind it.
class CelebrationQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() job) {
    final done = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        done.complete(await job());
      } on Object catch (error, stack) {
        done.completeError(error, stack);
      }
    });
    return done.future;
  }
}

final celebrationQueueProvider = Provider<CelebrationQueue>(
  (ref) => CelebrationQueue(),
);
