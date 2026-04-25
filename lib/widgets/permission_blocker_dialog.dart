import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;

// Blocking dialog shown when a required runtime permission is denied.
// The single action closes the app via SystemNavigator.pop() — TravelTrace
// can't function without GPS or camera, so the simplest contract is to
// stop here rather than try to recover.
Future<void> showPermissionBlockerDialog(
  BuildContext context, {
  required String permissionName,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      // Block back-button dismissal — the only way out is the Exit button.
      canPop: false,
      child: AlertDialog(
        title: Text('$permissionName Permission Required'),
        content: Text(
          'TravelTrace cannot run without $permissionName access.',
        ),
        actions: [
          FilledButton(
            onPressed: () => SystemNavigator.pop(),
            child: const Text('Exit'),
          ),
        ],
      ),
    ),
  );
}
