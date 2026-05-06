import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/whatsapp_repository_impl.dart';
import '../domain/whatsapp_entity.dart';

final whatsappControllerProvider =
    AsyncNotifierProvider<WhatsappController, List<WhatsappEntity>>(
  WhatsappController.new,
);

class WhatsappController extends AsyncNotifier<List<WhatsappEntity>> {
  final WhatsappRepositoryImpl _repository = WhatsappRepositoryImpl();

  @override
  Future<List<WhatsappEntity>> build() {
    return _repository.list();
  }
}
