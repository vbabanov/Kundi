import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/whatsapp_controller.dart';

class WhatsappPage extends ConsumerWidget {
  const WhatsappPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(whatsappControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Whatsapp')),
      body: state.when(
        data: (items) => ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, index) =>
              ListTile(title: Text(items[index].id)),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error.toString())),
      ),
    );
  }
}
