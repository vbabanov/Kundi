import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'kundi_home_avatar_diagnostics.dart';
import 'kundi_home_avatar_placement.dart';

typedef KundiHomeAvatarFrameDecoder = Future<ui.Image> Function(
  String assetPath,
);
typedef KundiHomeAvatarDiagnosticRecorder = void Function(
  String name, {
  required int generation,
  int? textureId,
});

/// Owns decoded engine images used by the Home avatar's static top layer.
///
/// The holder lives above MainShell and is disposed only after that subtree is
/// removed, so RawImage never receives an already-disposed ui.Image.
final class KundiHomeAvatarLoadingFrame {
  KundiHomeAvatarLoadingFrame({
    required ui.Image? primaryImage,
    required ui.Image? fatalFallbackImage,
  })  : assert(primaryImage != null || fatalFallbackImage != null),
        _primaryImage = primaryImage,
        _fatalFallbackImage = fatalFallbackImage;

  final ui.Image? _primaryImage;
  final ui.Image? _fatalFallbackImage;
  bool _disposed = false;

  bool get primaryFrameReady => _primaryImage != null;
  bool get fatalFallbackReady => _fatalFallbackImage != null;
  bool get usesFatalFallback => _primaryImage == null;
  bool get isDisposed => _disposed;

  ui.Image get loadingImage => _active(_primaryImage ?? _fatalFallbackImage!);

  ui.Image get fatalFallbackImage =>
      _active(_fatalFallbackImage ?? _primaryImage!);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _primaryImage?.dispose();
    if (!identical(_fatalFallbackImage, _primaryImage)) {
      _fatalFallbackImage?.dispose();
    }
  }

  ui.Image _active(ui.Image image) {
    if (_disposed) {
      throw StateError('Kundi Home avatar loading frame is disposed.');
    }
    return image;
  }
}

/// Decodes and retains the first frame of both Home static assets exactly once.
final class KundiHomeAvatarLoadingFramePreloader {
  KundiHomeAvatarLoadingFramePreloader({
    required KundiHomeAvatarFrameDecoder decodeFrame,
    KundiHomeAvatarDiagnosticRecorder? recordDiagnostic,
  })  : _decodeFrame = decodeFrame,
        _recordDiagnostic = recordDiagnostic;

  final KundiHomeAvatarFrameDecoder _decodeFrame;
  final KundiHomeAvatarDiagnosticRecorder? _recordDiagnostic;
  Future<KundiHomeAvatarLoadingFrame>? _preparation;

  Future<KundiHomeAvatarLoadingFrame> prepare() =>
      _preparation ??= _prepareOnce();

  Future<KundiHomeAvatarLoadingFrame> _prepareOnce() async {
    _recordDiagnostic?.call(
      KundiHomeAvatarTraceName.loadingDecodeStarted,
      generation: 0,
    );
    ui.Image? primaryImage;
    ui.Image? fatalFallbackImage;

    try {
      primaryImage =
          await _decodeFrame(KundiHomeAvatarPlacement.loadingAssetPath);
    } on Object {
      primaryImage = null;
    }

    try {
      fatalFallbackImage = await _decodeFrame(
        KundiHomeAvatarPlacement.fatalFallbackAssetPath,
      );
    } on Object {
      fatalFallbackImage = null;
    }

    if (primaryImage == null && fatalFallbackImage == null) {
      throw StateError('Neither Home avatar static frame could be decoded.');
    }
    final frame = KundiHomeAvatarLoadingFrame(
      primaryImage: primaryImage,
      fatalFallbackImage: fatalFallbackImage,
    );
    _recordDiagnostic?.call(
      KundiHomeAvatarTraceName.loadingDecodeReady,
      generation: 0,
    );
    return frame;
  }
}

typedef KundiHomeAvatarPreparedBuilder = Widget Function(
  BuildContext context,
  KundiHomeAvatarLoadingFrame? frame,
);

/// Keeps the existing startup surface visible until real ui.Images are ready.
///
/// When realtime is compiled off, the builder runs immediately and no avatar
/// loading asset is read or decoded.
final class KundiHomeAvatarLoadingFrameGate extends StatefulWidget {
  const KundiHomeAvatarLoadingFrameGate({
    required this.enabled,
    required this.loading,
    required this.builder,
    this.preloader,
    super.key,
  });

  final bool enabled;
  final Widget loading;
  final KundiHomeAvatarPreparedBuilder builder;
  final KundiHomeAvatarLoadingFramePreloader? preloader;

  @override
  State<KundiHomeAvatarLoadingFrameGate> createState() =>
      _KundiHomeAvatarLoadingFrameGateState();
}

class _KundiHomeAvatarLoadingFrameGateState
    extends State<KundiHomeAvatarLoadingFrameGate> {
  KundiHomeAvatarLoadingFrame? _frame;
  bool _preparationStarted = false;
  bool _preparationFailed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_preparationStarted || !widget.enabled) return;
    _preparationStarted = true;
    final diagnostics = KundiHomeAvatarDiagnostics.instance;
    final preloader = widget.preloader ??
        KundiHomeAvatarLoadingFramePreloader(
          decodeFrame: _decodeAssetFrame,
          recordDiagnostic: diagnostics.record,
        );
    unawaited(_prepare(preloader));
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || _preparationFailed) {
      return widget.builder(context, null);
    }
    final frame = _frame;
    return frame == null ? widget.loading : widget.builder(context, frame);
  }

  @override
  void dispose() {
    _frame?.dispose();
    super.dispose();
  }

  Future<void> _prepare(KundiHomeAvatarLoadingFramePreloader preloader) async {
    try {
      final frame = await preloader.prepare();
      if (!mounted) {
        frame.dispose();
        return;
      }
      setState(() => _frame = frame);
    } on Object catch (error) {
      debugPrint(
        '[KUNDI_AVATAR_LOADING] decoded frame unavailable; '
        'falling back to normal app assets: $error',
      );
      if (!mounted) return;
      setState(() => _preparationFailed = true);
    }
  }

  Future<ui.Image> _decodeAssetFrame(String assetPath) async {
    final bytes = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }
}
