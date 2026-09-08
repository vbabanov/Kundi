import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/student_refresh_controller.dart';
import '../../l10n/l10n.dart';

final studentRefreshActionProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    await ref.read(studentRefreshControllerProvider.notifier).refresh();
  };
});

Future<void> refreshStudentFromGesture(
  BuildContext context,
  WidgetRef ref,
) async {
  try {
    await ref.read(studentRefreshActionProvider)();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(context.l10n.pullRefreshFailed),
          action: SnackBarAction(
            label: context.l10n.commonRetry,
            onPressed: () {
              refreshStudentFromGesture(context, ref);
            },
          ),
        ),
      );
  }
}

bool studentRefreshNotification(ScrollNotification notification) {
  return notification.depth <= 2 && notification.metrics.extentBefore == 0;
}
