import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/lab_module.dart';
import '../app/theme.dart';

const mono = TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.45);

/// Common page frame for every lab. Title, intro, icon and colour all come
/// from [LabModule], so a lab can't drift out of sync with its home tile.
class LabScaffold extends StatelessWidget {
  const LabScaffold({super.key, required this.module, required this.children});

  final LabModule module;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final color = module.color;
    return Scaffold(
      appBar: AppBar(title: Text(module.shortTitle)),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: [color.withValues(alpha: .35), AppColors.navyLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: color.withValues(alpha: .25),
                    child: Icon(module.icon, color: color),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(module.intro, style: const TextStyle(color: Colors.white70, height: 1.4)),
                  ),
                ],
              ),
            ),
            for (final c in children) ...[const SizedBox(height: 16), c],
          ],
        ),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// "Key idea" bullets for the trainer to talk through.
class ConceptCard extends StatelessWidget {
  const ConceptCard({super.key, required this.points, this.title = 'Key concepts'});

  final String title;
  final List<(String, String)> points;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: title,
      child: Column(
        children: [
          for (final (head, body) in points)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Icon(Icons.check_circle, size: 16, color: AppColors.teal),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$head  ',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(
                            text: body,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                      style: const TextStyle(height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class CodeSnippet extends StatelessWidget {
  const CodeSnippet({super.key, required this.code, this.title = 'Code'});

  final String title;
  final String code;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: title,
      trailing: CopyButton(text: code),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.code, borderRadius: BorderRadius.circular(12)),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(code.trim(), style: mono.copyWith(color: const Color(0xFFCFE3FF))),
        ),
      ),
    );
  }
}

class CopyButton extends StatelessWidget {
  const CopyButton({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: 'Copy',
      icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.muted),
      onPressed: () {
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)));
      },
    );
  }
}

/// Labelled monospace value (keys, MACs, ciphertext).
class OutputField extends StatelessWidget {
  const OutputField({super.key, required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: 1, color: AppColors.muted)),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            decoration: BoxDecoration(color: AppColors.code, borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(value, style: mono.copyWith(color: color ?? Colors.white)),
                ),
                CopyButton(text: value),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class StatusBanner extends StatelessWidget {
  const StatusBanner({super.key, required this.ok, required this.text});

  final bool ok;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = ok ? AppColors.teal : AppColors.red;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        border: Border.all(color: color.withValues(alpha: .6)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.verified_rounded : Icons.gpp_bad_rounded, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = AppColors.muted});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: .15), borderRadius: BorderRadius.circular(20)),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// A TextField whose text is owned by state (a Riverpod notifier), not by
/// the widget. External changes (e.g. a "Tamper" button) are pushed into
/// the controller; user edits go out through [onChanged].
class SyncedTextField extends StatefulWidget {
  const SyncedTextField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.maxLines = 1,
    this.obscure = false,
    this.keyboardType,
    this.prefixText,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final int maxLines;
  final bool obscure;
  final TextInputType? keyboardType;
  final String? prefixText;

  @override
  State<SyncedTextField> createState() => _SyncedTextFieldState();
}

class _SyncedTextFieldState extends State<SyncedTextField> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(SyncedTextField old) {
    super.didUpdateWidget(old);
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        maxLines: widget.maxLines,
        obscureText: widget.obscure,
        keyboardType: widget.keyboardType,
        decoration: InputDecoration(labelText: widget.label, prefixText: widget.prefixText),
      );
}

/// Primary action button with a built-in busy spinner and danger style.
class BusyButton extends StatelessWidget {
  const BusyButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.busy = false,
    this.danger = false,
    this.outlined = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;
  final bool danger;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final leading =
        busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon);
    final action = busy ? null : onPressed;
    if (outlined) {
      return OutlinedButton.icon(onPressed: action, icon: leading, label: Text(label));
    }
    return FilledButton.icon(
      style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white) : null,
      onPressed: action,
      icon: leading,
      label: Text(label),
    );
  }
}

/// Single-choice chip row, e.g. tamper modes or attack scenarios.
class OptionChips<T> extends StatelessWidget {
  const OptionChips({
    super.key,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    this.isDanger,
    this.enabled = true,
  });

  final List<T> options;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;
  final bool Function(T)? isDanger;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          Builder(
            builder: (context) {
              final danger = isDanger?.call(o) ?? false;
              final color = danger ? AppColors.red : AppColors.teal;
              return ChoiceChip(
                avatar: isDanger == null
                    ? null
                    : Icon(danger ? Icons.bug_report_rounded : Icons.verified_user_rounded, size: 16, color: color),
                label: Text(labelOf(o)),
                selected: o == selected,
                selectedColor: color.withValues(alpha: .3),
                onSelected: enabled ? (_) => onSelected(o) : null,
              );
            },
          ),
      ],
    );
  }
}

/// Compact bullet list used inside lab cards.
class ConceptBullets extends StatelessWidget {
  const ConceptBullets({super.key, required this.points});

  final List<String> points;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          for (final p in points)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(Icons.circle, size: 6, color: AppColors.teal),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(p, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
