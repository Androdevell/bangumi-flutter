import 'package:flutter/material.dart';
import '../core/localization/app_localizations.dart';

class SettingsChoiceTile extends StatelessWidget {
  const SettingsChoiceTile({
    super.key,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    this.icon = Icons.tune,
    this.searchable = false,
  });
  final String title, value;
  final Map<String, String> options;
  final ValueChanged<String>? onChanged;
  final IconData icon;
  final bool searchable;

  @override
  Widget build(BuildContext context) => Card.filled(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(options[value] ?? value),
      trailing: const Icon(Icons.unfold_more_rounded),
      enabled: onChanged != null,
      onTap:
          onChanged == null
              ? null
              : () async {
                final selected = await showSettingsChoice(
                  context,
                  title: title,
                  value: value,
                  options: options,
                  searchable: searchable,
                );
                if (selected != null) onChanged?.call(selected);
              },
    ),
  );
}

Future<String?> showSettingsChoice(
  BuildContext context, {
  required String title,
  required String value,
  required Map<String, String> options,
  bool searchable = false,
}) {
  final panel = _ChoicePanel(
    title: title,
    value: value,
    options: options,
    searchable: searchable,
  );
  if (MediaQuery.sizeOf(context).width >= 600) {
    return showDialog<String>(
      context: context,
      builder:
          (_) => Dialog(child: SizedBox(width: 520, height: 540, child: panel)),
    );
  }
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder:
        (context) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .7,
            child: panel,
          ),
        ),
  );
}

class _ChoicePanel extends StatefulWidget {
  const _ChoicePanel({
    required this.title,
    required this.value,
    required this.options,
    required this.searchable,
  });
  final String title, value;
  final Map<String, String> options;
  final bool searchable;
  @override
  State<_ChoicePanel> createState() => _ChoicePanelState();
}

class _ChoicePanelState extends State<_ChoicePanel> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final items =
        widget.options.entries
            .where(
              (e) => ('${e.key} ${e.value}').toLowerCase().contains(
                _query.toLowerCase(),
              ),
            )
            .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        if (widget.searchable)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: AppLocalizations.of(context).t('choiceSearch'),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              return RadioListTile<String>(
                title: Text(item.value),
                value: item.key,
                groupValue: widget.value,
                onChanged: (v) => Navigator.pop(context, v),
              );
            },
          ),
        ),
      ],
    );
  }
}
