import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Reports a real child paint once for each renderer generation.
///
/// The callback is deferred until after the painted frame, so callers never
/// mutate widget state from the render pipeline itself.
final class KundiFirstPaintNotifier extends SingleChildRenderObjectWidget {
  const KundiFirstPaintNotifier({
    required this.generation,
    required this.onMounted,
    required this.onPainted,
    required super.child,
    super.key,
  });

  final int generation;
  final ValueChanged<int> onMounted;
  final ValueChanged<int> onPainted;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _KundiFirstPaintRenderObject(
        generation: generation,
        onMounted: onMounted,
        onPainted: onPainted,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderObject renderObject,
  ) {
    (renderObject as _KundiFirstPaintRenderObject)
      ..generation = generation
      ..onMounted = onMounted
      ..onPainted = onPainted;
  }
}

final class _KundiFirstPaintRenderObject extends RenderProxyBox {
  _KundiFirstPaintRenderObject({
    required int generation,
    required ValueChanged<int> onMounted,
    required ValueChanged<int> onPainted,
  })  : _generation = generation,
        _onMounted = onMounted,
        _onPainted = onPainted;

  int _generation;
  ValueChanged<int> _onMounted;
  ValueChanged<int> _onPainted;
  int _callbackVersion = 0;
  bool _mountCallbackScheduled = false;
  bool _paintCallbackScheduled = false;
  bool _mountedReported = false;
  bool _paintedReported = false;

  set generation(int value) {
    if (_generation == value) return;
    _generation = value;
    _callbackVersion++;
    _mountCallbackScheduled = false;
    _paintCallbackScheduled = false;
    _mountedReported = false;
    _paintedReported = false;
    if (attached) {
      _scheduleMountedCallback();
      markNeedsPaint();
    }
  }

  set onMounted(ValueChanged<int> value) => _onMounted = value;

  set onPainted(ValueChanged<int> value) => _onPainted = value;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _scheduleMountedCallback();
  }

  @override
  void detach() {
    _callbackVersion++;
    _mountCallbackScheduled = false;
    _paintCallbackScheduled = false;
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (_paintedReported || _paintCallbackScheduled) return;
    _paintCallbackScheduled = true;
    final scheduledGeneration = _generation;
    final scheduledVersion = _callbackVersion;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _paintCallbackScheduled = false;
      if (!attached ||
          _generation != scheduledGeneration ||
          _callbackVersion != scheduledVersion ||
          _paintedReported) {
        return;
      }
      _paintedReported = true;
      _onPainted(scheduledGeneration);
    });
  }

  void _scheduleMountedCallback() {
    if (_mountedReported || _mountCallbackScheduled) return;
    _mountCallbackScheduled = true;
    final scheduledGeneration = _generation;
    final scheduledVersion = _callbackVersion;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _mountCallbackScheduled = false;
      if (!attached ||
          _generation != scheduledGeneration ||
          _callbackVersion != scheduledVersion ||
          _mountedReported) {
        return;
      }
      _mountedReported = true;
      _onMounted(scheduledGeneration);
    });
  }
}
