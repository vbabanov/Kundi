import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../runtimes/avatar_runtime/bridge/method_channel_avatar_bridge.dart';
import '../../runtimes/avatar_runtime/facade/avatar_facade.dart';

final avatarFacadeProvider = Provider<AvatarFacade>((ref) {
  return AvatarFacade(MethodChannelAvatarBridge());
});
