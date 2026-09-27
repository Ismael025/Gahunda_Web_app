import 'package:flutter/material.dart';

class WebInstallButton extends StatelessWidget {
  const WebInstallButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Install Gahunda',
      onPressed: () => showDialog<void>(
        context: context,
        builder: (BuildContext context) => const _WebInstallDialog(),
      ),
      icon: const Icon(Icons.install_mobile_rounded),
    );
  }
}

class _WebInstallDialog extends StatelessWidget {
  const _WebInstallDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.install_mobile_rounded),
      title: const Text('Install Gahunda'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'On iPhone',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 6),
            Text('1. Open this site in Safari.'),
            Text('2. Tap Share.'),
            Text('3. Tap Add to Home Screen, then Add.'),
            Text('4. Open Gahunda from its new Home Screen icon.'),
            SizedBox(height: 16),
            Text(
              'On a computer or Android',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 6),
            Text(
              'Use the browser installation icon or menu and choose Install app.',
            ),
            SizedBox(height: 16),
            Text(
              'Your browser stores an offline working copy. Sign in and sync so '
              'your information can also be restored on another device.',
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
