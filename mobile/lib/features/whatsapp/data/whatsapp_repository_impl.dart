import '../domain/whatsapp_entity.dart';
import '../domain/whatsapp_repository.dart';

class WhatsappRepositoryImpl implements WhatsappRepository {
  @override
  Future<List<WhatsappEntity>> list() async {
    return const <WhatsappEntity>[];
  }
}
