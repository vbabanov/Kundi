import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'kundi_native_avatar_controller.dart';
import 'kundi_native_avatar_feature.dart';
import 'kundi_native_avatar_protocol.dart';
import 'kundi_home_avatar_placement.dart';

final class KundiNativeAvatarTextureConfiguration {
  const KundiNativeAvatarTextureConfiguration({
    required this.logicalWidth,
    required this.logicalHeight,
    required this.devicePixelRatio,
  });

  final double logicalWidth;
  final double logicalHeight;
  final double devicePixelRatio;

  Map<String, Object> toCreateArguments() => <String, Object>{
        'protocolVersion': KundiNativeAvatarEnvelope.version,
        'logicalWidth': logicalWidth,
        'logicalHeight': logicalHeight,
        'devicePixelRatio': devicePixelRatio,
        'renderScale': KundiNativeAvatarFeature.renderScale,
        'passiveBurstIntervalMillis':
            KundiNativeAvatarFeature.passiveBurstIntervalMillis,
        'passiveBurstDurationMillis':
            KundiNativeAvatarFeature.passiveBurstDurationMillis,
        ...KundiHomeAvatarPlacement.rendererArguments,
      };

  Map<String, Object> toResizeArguments(int textureId) => <String, Object>{
        'textureId': textureId,
        'logicalWidth': logicalWidth,
        'logicalHeight': logicalHeight,
        'devicePixelRatio': devicePixelRatio,
      };

  @override
  bool operator ==(Object other) =>
      other is KundiNativeAvatarTextureConfiguration &&
      logicalWidth == other.logicalWidth &&
      logicalHeight == other.logicalHeight &&
      devicePixelRatio == other.devicePixelRatio;

  @override
  int get hashCode => Object.hash(
        logicalWidth,
        logicalHeight,
        devicePixelRatio,
      );
}

abstract interface class KundiNativeAvatarTextureBridge {
  Future<int> create(KundiNativeAvatarTextureConfiguration configuration);

  Future<void> resize(
    int textureId,
    KundiNativeAvatarTextureConfiguration configuration,
  );

  Stream<Object?> eventsFor(int textureId);

  Future<Object?> send(
    int textureId,
    Map<String, Object> envelope,
  );

  Future<void> disposeTexture(int textureId);
}

final class MethodChannelKundiNativeAvatarTextureBridge
    implements KundiNativeAvatarTextureBridge {
  const MethodChannelKundiNativeAvatarTextureBridge();

  static const MethodChannel _commands =
      MethodChannel('kundi/native_avatar/texture/commands');
  static const EventChannel _events =
      EventChannel('kundi/native_avatar/texture/events');

  @override
  Future<int> create(
    KundiNativeAvatarTextureConfiguration configuration,
  ) async {
    final result = await _commands.invokeMapMethod<String, Object?>(
      'create',
      configuration.toCreateArguments(),
    );
    final textureId = result?['textureId'];
    if (textureId is! int) {
      throw PlatformException(
        code: 'invalid_texture_response',
        message: 'Native avatar texture ID is missing.',
      );
    }
    return textureId;
  }

  @override
  Future<void> resize(
    int textureId,
    KundiNativeAvatarTextureConfiguration configuration,
  ) =>
      _commands.invokeMethod<void>(
        'resize',
        configuration.toResizeArguments(textureId),
      );

  @override
  Stream<Object?> eventsFor(int textureId) =>
      _events.receiveBroadcastStream().where(
            (event) => event is Map && event['textureId'] == textureId,
          );

  @override
  Future<Object?> send(
    int textureId,
    Map<String, Object> envelope,
  ) =>
      _commands.invokeMethod<Object?>(
        'command',
        <String, Object>{
          'textureId': textureId,
          'envelope': envelope,
        },
      );

  @override
  Future<void> disposeTexture(int textureId) => _commands.invokeMethod<void>(
        'dispose',
        <String, Object>{'textureId': textureId},
      );
}

final class TextureKundiNativeAvatarTransport
    implements KundiNativeAvatarTransport {
  TextureKundiNativeAvatarTransport({
    required KundiNativeAvatarTextureBridge bridge,
    required int textureId,
  })  : _bridge = bridge,
        _textureId = textureId;

  final KundiNativeAvatarTextureBridge _bridge;
  final int _textureId;
  bool _disposed = false;

  @override
  Stream<Object?> get events => _bridge.eventsFor(_textureId);

  @override
  Future<Object?> send(Map<String, Object> envelope) =>
      _bridge.send(_textureId, envelope);

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _bridge.disposeTexture(_textureId);
  }
}

final class KundiNativeAvatarTextureView extends StatefulWidget {
  const KundiNativeAvatarTextureView({
    required this.onControllerCreated,
    required this.onTextureAvailable,
    required this.onTextureMounted,
    this.onRendererError,
    this.bridge = const MethodChannelKundiNativeAvatarTextureBridge(),
    super.key,
  });

  final ValueChanged<KundiNativeAvatarController> onControllerCreated;
  final ValueChanged<int> onTextureAvailable;
  final ValueChanged<int> onTextureMounted;
  final VoidCallback? onRendererError;
  final KundiNativeAvatarTextureBridge bridge;

  @override
  State<KundiNativeAvatarTextureView> createState() =>
      _KundiNativeAvatarTextureViewState();
}

class _KundiNativeAvatarTextureViewState
    extends State<KundiNativeAvatarTextureView> {
  int? _textureId;
  KundiNativeAvatarController? _controller;
  KundiNativeAvatarTextureConfiguration? _desiredConfiguration;
  KundiNativeAvatarTextureConfiguration? _appliedConfiguration;
  bool _synchronizationScheduled = false;
  bool _creating = false;
  bool _disposed = false;
  int? _mountedNotificationTextureId;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          if (width.isFinite && height.isFinite && width > 0 && height > 0) {
            _scheduleSynchronization(
              KundiNativeAvatarTextureConfiguration(
                logicalWidth: width,
                logicalHeight: height,
                devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
              ),
            );
          }
          final textureId = _textureId;
          if (textureId == null) {
            return const SizedBox.expand();
          }
          _scheduleMountedNotification(textureId);
          return Texture(
            textureId: textureId,
            filterQuality: FilterQuality.medium,
          );
        },
      );

  void _scheduleMountedNotification(int textureId) {
    if (_mountedNotificationTextureId == textureId || _disposed) return;
    _mountedNotificationTextureId = textureId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || _textureId != textureId || !mounted) return;
      widget.onTextureMounted(textureId);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    final controller = _controller;
    final textureId = _textureId;
    if (controller != null) {
      unawaited(controller.dispose());
    } else if (textureId != null) {
      unawaited(widget.bridge.disposeTexture(textureId));
    }
    super.dispose();
  }

  void _scheduleSynchronization(
    KundiNativeAvatarTextureConfiguration configuration,
  ) {
    _desiredConfiguration = configuration;
    if (_synchronizationScheduled || _disposed) return;
    _synchronizationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _synchronizationScheduled = false;
      unawaited(_synchronize());
    });
  }

  Future<void> _synchronize() async {
    if (_disposed || _creating) return;
    final desired = _desiredConfiguration;
    if (desired == null) return;
    final textureId = _textureId;
    if (textureId == null) {
      _creating = true;
      try {
        final createdTextureId = await widget.bridge.create(desired);
        if (_disposed) {
          await widget.bridge.disposeTexture(createdTextureId);
          return;
        }
        final controller = KundiNativeAvatarController(
          TextureKundiNativeAvatarTransport(
            bridge: widget.bridge,
            textureId: createdTextureId,
          ),
        );
        _textureId = createdTextureId;
        _controller = controller;
        _appliedConfiguration = desired;
        if (mounted) {
          widget.onTextureAvailable(createdTextureId);
          setState(() {});
          widget.onControllerCreated(controller);
        }
      } on Object {
        widget.onRendererError?.call();
      } finally {
        _creating = false;
      }
      if (_desiredConfiguration != _appliedConfiguration) {
        await _synchronize();
      }
      return;
    }
    if (_appliedConfiguration == desired) return;
    try {
      await widget.bridge.resize(textureId, desired);
      _appliedConfiguration = desired;
    } on Object {
      widget.onRendererError?.call();
    }
  }
}
