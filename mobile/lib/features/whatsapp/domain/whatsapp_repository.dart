import 'whatsapp_entity.dart';

abstract class WhatsappRepository {
  Future<List<WhatsappEntity>> list();
}
