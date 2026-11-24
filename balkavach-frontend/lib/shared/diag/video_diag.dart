// TEMPORARY diagnostics for the "grey Home after video Back" investigation.
// Debug builds only; every call is a no-op in profile/release. Remove this
// file and its `vdiag(` call sites once the cause is fixed.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool _installed = false;
AppLifecycleState? _lifecycle;
int _seq = 0;

class _LifecycleProbe with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    vdiag('app.lifecycle', screen: 'app', extra: 'state=${state.name}');
  }
}

void _install() {
  if (_installed) return;
  _installed = true;
  final binding = WidgetsBinding.instance;
  _lifecycle = binding.lifecycleState;
  binding.addObserver(_LifecycleProbe());
  // Chain, never replace: the existing handler still runs first.
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    previous?.call(details);
    vdiag(
      'flutter.error',
      screen: 'app',
      extra:
          'library=${details.library} '
          'exception=${details.exceptionAsString().split('\n').first}',
      error: details.exception,
      stack: details.stack,
    );
  };
}

/// Logs one diagnostic event. Never throws, never awaits, never touches
/// player or navigation state. [id] is an identityHashCode, not user data.
void vdiag(
  String event, {
  required String screen,
  Object? id,
  String? extra,
  Object? error,
  StackTrace? stack,
}) {
  if (!kDebugMode) return;
  try {
    _install();
    final buffer = StringBuffer('[VDIAG] ')
      ..write(DateTime.now().toIso8601String())
      ..write(' #${++_seq}')
      ..write(' event=$event screen=$screen')
      ..write(' lifecycle=${_lifecycle?.name ?? 'unknown'}');
    if (id != null) buffer.write(' id=$id');
    if (extra != null) buffer.write(' $extra');
    if (error != null) buffer.write(' error=${error.runtimeType}: $error');
    debugPrint(buffer.toString());
    if (stack != null) {
      final lines = stack.toString().split('\n').take(8).join('\n  ');
      debugPrint('[VDIAG]   stack:\n  $lines');
    }
  } on Object {
    // Diagnostics must never affect the app.
  }
}

/// Logs every route change the root navigator makes. Passive.
class VideoDiagNavigatorObserver extends NavigatorObserver {
  String _name(Route<dynamic>? route) =>
      route?.settings.name ??
      route?.settings.arguments?.runtimeType.toString() ??
      route?.runtimeType.toString() ??
      'null';

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => vdiag(
    'nav.push',
    screen: _name(route),
    id: identityHashCode(route),
    extra: 'previous=${_name(previousRoute)}',
  );

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => vdiag(
    'nav.pop',
    screen: _name(route),
    id: identityHashCode(route),
    extra: 'now_top=${_name(previousRoute)}',
  );

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      vdiag('nav.remove', screen: _name(route), id: identityHashCode(route));

  // (VideoDiagProbe is defined at the end of this file.)

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      vdiag(
        'nav.replace',
        screen: _name(newRoute),
        extra: 'old=${_name(oldRoute)}',
      );
}

/// Wraps a subtree and logs when it is mounted and unmounted. Adds no layout
/// and no behavior.
class VideoDiagProbe extends StatefulWidget {
  const VideoDiagProbe({required this.name, required this.child, super.key});

  final String name;
  final Widget child;

  @override
  State<VideoDiagProbe> createState() => _VideoDiagProbeState();
}

class _VideoDiagProbeState extends State<VideoDiagProbe> {
  @override
  void initState() {
    super.initState();
    vdiag('probe.mount', screen: widget.name, id: identityHashCode(this));
  }

  @override
  void dispose() {
    vdiag('probe.unmount', screen: widget.name, id: identityHashCode(this));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
