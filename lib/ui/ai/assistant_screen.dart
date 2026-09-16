import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../ai/assistant.dart';
import '../../ai/model_host.dart';
import '../../core/capability.dart';
import '../../core/model_catalog.dart';
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
            modelName: _assistant.model.name,
            loadEstimate: _assistant.loadEstimate,
            loadElapsed: _assistant.loadElapsed,
            onInstall: _assistant.install,
            onCancel: _assistant.cancelDownload,
            onRetry: _assistant.refresh,
            onRemove: _confirmRemoval,
          ),
          if (state.phase == AssistantPhase.notInstalled ||
              state.phase == AssistantPhase.ready ||
              state.phase == AssistantPhase.failed) ...[
            const SizedBox(height: 24),
            _ModelPicker(
              chosen: _assistant.model,
              onChanged: (model) {
                setState(() => _assistant.model = model);
                // Whether this one is installed is a different question.
                _assistant.refresh();
              },
            ),
          ],
          if (state.phase == AssistantPhase.notInstalled ||
              state.phase == AssistantPhase.failed) ...[
            const SizedBox(height: 24),
            _HostPicker(
              chosen: _assistant.preferredHost,
              onChanged: (host) => setState(() {
                _assistant.preferredHost = host;
              }),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Which model to run.
///
/// Two real choices, and the difference between them is quality against size:
/// said plainly, because it is the reader's phone and their data.
class _ModelPicker extends StatelessWidget {
  const _ModelPicker({required this.chosen, required this.onChanged});

  final ModelChoice chosen;
  final void Function(ModelChoice model) onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Which model', style: serif(size: 18, color: SadhanaColors.ink)),
      const SizedBox(height: 8),
      RadioGroup<String>(
        groupValue: chosen.id,
        onChanged: (id) => onChanged(modelChoiceById(id)),
        child: Column(
          children: [
            for (final model in assistantModels)
              RadioListTile<String>(
                key: ValueKey('model-${model.id}'),
                value: model.id,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${model.name}  ·  ${formatBytes(model.downloadBytes)}',
                ),
                subtitle: Text(model.summary),
                isThreeLine: true,
              ),
          ],
        ),
      ),
    ],
  );
}

/// Where to download from.
///
/// Offered rather than reasoned about: whoever is watching the bar knows more
/// about their connection than one speed test would.
class _HostPicker extends StatelessWidget {
  const _HostPicker({required this.chosen, required this.onChanged});

  final ModelHost? chosen;
  final void Function(ModelHost? host) onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Download from', style: serif(size: 18, color: SadhanaColors.ink)),
      const SizedBox(height: 4),
      const _Line(
        'Hugging Face by default. If the download crawls, the mirror may be '
        'closer to you.',
      ),
      const SizedBox(height: 8),
      RadioGroup<ModelHost?>(
        groupValue: chosen,
        onChanged: onChanged,
        child: Column(
          children: [
            const RadioListTile<ModelHost?>(
              key: ValueKey('host-auto'),
              value: null,
              contentPadding: EdgeInsets.zero,
              title: Text('Whichever answers first'),
            ),
            for (final host in ModelHost.values)
              RadioListTile<ModelHost?>(
                key: ValueKey('host-${host.name}'),
                value: host,
                contentPadding: EdgeInsets.zero,
                title: Text(host.label),
              ),
          ],
        ),
      ),
    ],
  );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.state,
    required this.requirement,
    required this.modelName,
    required this.loadEstimate,
    required this.loadElapsed,
    required this.onInstall,
    required this.onCancel,
    required this.onRetry,
    required this.onRemove,
  });

  final AssistantState state;
  final ModelRequirement requirement;
  final String modelName;
  final Duration loadEstimate;
  final ValueListenable<Duration> loadElapsed;
  final VoidCallback onInstall;
  final VoidCallback onCancel;
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

      case AssistantPhase.checking:
        return const [
          _Title('Checking the download'),
          SizedBox(height: 12),
          LinearProgressIndicator(),
          SizedBox(height: 12),
          _Line('Making sure the file is there before starting.'),
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
          const SizedBox(height: 8),
          TextButton(
            key: const ValueKey('assistant-cancel'),
            onPressed: onCancel,
            child: const Text('Stop the download'),
          ),
        ];

      case AssistantPhase.loading:
        return [
          const _Title('Getting ready'),
          const SizedBox(height: 12),
          // Time against the last measured load: the runtime reports no
          // progress, and the bar stops short of full rather than claiming to
          // be finished while it is not.
          ValueListenableBuilder<Duration>(
            valueListenable: loadElapsed,
            builder: (context, elapsed, _) => LinearProgressIndicator(
              value: loadEstimate.inMilliseconds <= 0
                  ? null
                  : (elapsed.inMilliseconds / loadEstimate.inMilliseconds)
                        .clamp(0.0, 0.99),
              color: SadhanaColors.green,
            ),
          ),
          const SizedBox(height: 12),
          _Line(
            'The first start takes about ${loadEstimate.inSeconds} seconds on '
            'this phone.',
          ),
        ];

      case AssistantPhase.ready:
      case AssistantPhase.working:
        return [
          _Title(
            state.phase == AssistantPhase.working
                ? 'Working…'
                : '$modelName is ready',
          ),
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
