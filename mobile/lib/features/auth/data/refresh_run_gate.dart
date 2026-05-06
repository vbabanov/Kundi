class RefreshRunGate<T> {
  Future<T>? _inFlight;

  bool get isRunning => _inFlight != null;

  Future<T> run(
    Future<T> Function() action, {
    void Function()? onCoalesced,
  }) {
    final active = _inFlight;
    if (active != null) {
      if (onCoalesced != null) {
        onCoalesced();
      }
      return active;
    }

    final future = action();
    _inFlight = future;
    future.whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    });
    return future;
  }
}
