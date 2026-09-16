import 'package:flutter/material.dart';

import '../../ai/assistant.dart';
import '../../core/capability.dart';
import '../../core/units.dart';
import '../theme.dart';

/// Sets up the on-device assistant: what it is, what it costs to install, and
/// how to remove it again.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key, this.assistant});

  /// Defaults to the app's assistant; injected in tests.
  final Assistant? assistant;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  Assistant get _assistant => widget.assistant ?? Assistant.instance;

  @override
  void initState() {
    super.initState();
    if (_assistant.state.value.phase == AssistantPhase.unknown) {
      _assistant.refresh();
    }
  }

  Future<void> _confirmRemoval() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove the assistant?'),
        content: Text(
          'This deletes the ${formatBytes(_assistant.requirement.downloadBytes)} '
          'model. Translations it already made stay on this phone. You can '
          'download it again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (go ?? false) await _assistant.remove();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: SadhanaColors.background,
    appBar: AppBar(
      backgroundColor: SadhanaColors.background,
      foregroundColor: SadhanaColors.ink,
      elevation: 0,
      title: Text(
        'On-device AI',
        style: serif(size: 22, color: SadhanaColors.ink),
      ),
    ),
    body: ValueListenableBuilder<AssistantState>(
      valueListenable: _assistant.state,
      builder: (context, state, _) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            'Sadhana can translate verses and answer questions on this phone. '
            'The model runs here: nothing you read or ask is sent anywhere.',
            style: const TextStyle(
              fontSize: 16,
              height: 1.55,
              color: SadhanaColors.ink,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Scripture itself is never generated. The AI only translates and '
            'explains the text the app already has, and anything it writes is '
            'marked as a machine translation.',
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              color: SadhanaColors.inkSoft,
            ),
          ),
          const SizedBox(height: 24),
          _StatusCard(
            state: state,
            requirement: _assistant.requirement,
            onInstall: _assistant.install,
            onRetry: _assistant.refresh,
            onRemove: _confirmRemoval,
          ),
        ],
      ),
    ),
  );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.state,
    required this.requirement,
    required this.onInstall,
    required this.onRetry,
    required this.onRemove,
  });

  final AssistantState state;
  final ModelRequirement requirement;
  final VoidCallback onInstall;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: SadhanaColors.surface,
      borderRadius: BorderRadius.circular(22),
      boxShadow: const [
        BoxShadow(
          color: Color(0x11000000),
          blurRadius: 18,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _body(context),
      ),
    ),
  );

  List<Widget> _body(BuildContext context) {
    final size = formatBytes(requirement.downloadBytes);
    switch (state.phase) {
      case AssistantPhase.unknown:
        return const [
          _Line('Checking what this phone can run…'),
          SizedBox(height: 12),
          LinearProgressIndicator(),
        ];

      case AssistantPhase.unsupported:
        return [
          _Title('Not available on this phone'),
          const SizedBox(height: 8),
          _Line(state.message ?? 'This phone cannot run the model.'),
          const SizedBox(height: 8),
          const _Line(
            'Everything else in Sadhana works without it. Translations that '
            'ship with a pack are unaffected.',
          ),
        ];

      case AssistantPhase.notInstalled:
        return [
          _Title('Download the assistant'),
          const SizedBox(height: 8),
          _Line(
            'A one-time $size download. Use Wi-Fi, keep the app open while it '
            'downloads, and expect it to take a few minutes.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('assistant-install'),
            onPressed: onInstall,
            style: FilledButton.styleFrom(backgroundColor: SadhanaColors.green),
            child: Text('Download ($size)'),
          ),
          const SizedBox(height: 10),
          const _Line(
            'If a model is already on this phone, Sadhana can use it instead '
            'of downloading again.',
          ),
        ];

      case AssistantPhase.downloading:
        final percent = state.percent ?? 0;
        return [
          _Title('Downloading — $percent%'),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: percent <= 0 ? null : percent / 100,
            color: SadhanaColors.green,
          ),
          const SizedBox(height: 12),
          const _Line('You can keep reading; leave the app open.'),
        ];

      case AssistantPhase.loading:
        return const [
          _Title('Getting ready'),
          SizedBox(height: 12),
          LinearProgressIndicator(),
          SizedBox(height: 12),
          _Line('The first start takes about a minute.'),
        ];

      case AssistantPhase.ready:
      case AssistantPhase.working:
        return [
          _Title(state.phase == AssistantPhase.working ? 'Working…' : 'Ready'),
          const SizedBox(height: 8),
          _Line(
            'Open a verse with no translation in your language and choose '
            '"Translate on this phone".',
          ),
          const SizedBox(height: 16),
          TextButton(
            key: const ValueKey('assistant-remove'),
            onPressed: onRemove,
            child: Text('Remove the model ($size)'),
          ),
        ];

      case AssistantPhase.failed:
        return [
          _Title('That did not work'),
          const SizedBox(height: 8),
          _Line(state.message ?? 'Something went wrong.'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(backgroundColor: SadhanaColors.green),
            child: const Text('Try again'),
          ),
        ];
    }
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: serif(size: 20, color: SadhanaColors.ink));
}

class _Line extends StatelessWidget {
  const _Line(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 15,
      height: 1.5,
      color: SadhanaColors.inkSoft,
    ),
  );
}
