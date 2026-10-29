import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'diagnostics.dart';

class RuntimeDiagnostics with WidgetsBindingObserver {
  RuntimeDiagnostics._();
  static final instance = RuntimeDiagnostics._();
  StreamSubscription<List<ConnectivityResult>>? _network;
  Future<void> start() async {
    if (_network != null) return;
    WidgetsBinding.instance.addObserver(this);
    Diagnostics.instance.event('app.start');
    try {
      final connectivity = Connectivity();
      void record(List<ConnectivityResult> results) =>
          Diagnostics.instance.event('network.changed', {
            'transports': results.map((r) => r.name).join(','),
          });
      record(await connectivity.checkConnectivity());
      _network = connectivity.onConnectivityChanged.listen(
        record,
        onError: (Object e) =>
            Diagnostics.instance.event('network.monitor_error', {'message': e}),
      );
    } on Object catch (e) {
      Diagnostics.instance.event('network.monitor_error', {'message': e});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    Diagnostics.instance.event('app.lifecycle', {'state': state.name});
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(Diagnostics.instance.flush());
    }
  }
}
