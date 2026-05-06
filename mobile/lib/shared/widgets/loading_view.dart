import 'package:flutter/material.dart';

import 'kundi_surface.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label = 'Loading...'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return KundiStateBody.loading(
      label: label,
    );
  }
}
