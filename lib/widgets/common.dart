import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app/theme.dart';
import '../models/models.dart';
import '../models/sla.dart';

final inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final dateFmt = DateFormat('d MMM yyyy');
final dateTimeFmt = DateFormat('EEE, d MMM · h:mm a');

/// Centers content and caps width on large screens.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.maxWidth = 1200});
  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.onTap,
    this.sub,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: c.withValues(alpha: 0.12),
                child: Icon(icon, color: c),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    if (sub != null) Text(sub!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Responsive grid of fixed-height tiles.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth > 900 ? 4 : (c.maxWidth > 520 ? 2 : 1);
        const gap = 12.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final ch in children) SizedBox(width: w, child: ch)],
        );
      },
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.action, this.padding = true});
  final String title;
  final Widget child;
  final Widget? action;
  final bool padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  ?action,
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: padding ? 16 : 0),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

/// Two columns on wide screens, stacked on narrow.
class TwoCol extends StatelessWidget {
  const TwoCol({super.key, required this.left, required this.right});
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 16), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 16),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.color, this.icon, this.filled = false});
  final String text;
  final Color color;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: filled ? Colors.white : color), const SizedBox(width: 4)],
          Text(
            text,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: filled ? Colors.white : color),
          ),
        ],
      ),
    );
  }
}

class SlaPill extends StatelessWidget {
  const SlaPill(this.info, {super.key});
  final SlaInfo info;

  @override
  Widget build(BuildContext context) =>
      Pill(info.ageLabel, color: AppColors.sla(info.color), filled: true, icon: Icons.schedule);
}

Color criticalityColor(Criticality c) => switch (c) {
  Criticality.critical => AppColors.red,
  Criticality.high => const Color(0xFFEA580C),
  Criticality.medium => const Color(0xFF2563EB),
  Criticality.low => const Color(0xFF64748B),
};

class CriticalityPill extends StatelessWidget {
  const CriticalityPill(this.c, {super.key, this.ai = false});
  final Criticality c;
  final bool ai;

  @override
  Widget build(BuildContext context) => Pill(c.label, color: criticalityColor(c), icon: ai ? Icons.auto_awesome : null);
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.text, {super.key, this.icon = Icons.inbox_outlined});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        Icon(icon, size: 40, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 8),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
      ],
    ),
  );
}

void toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));

Future<String?> promptText(BuildContext context, {required String title, required String hint, bool required = true}) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: 3,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (required && ctrl.text.trim().isEmpty) return;
            Navigator.pop(ctx, ctrl.text.trim());
          },
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
