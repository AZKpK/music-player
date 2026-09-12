import 'package:flutter/material.dart';

/// Ena izbira v [AppSelectMenu].
class AppSelectOption<T> {
  const AppSelectOption({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// Enoten pojavni izbirnik za nastavitve z eno aktivno vrednostjo.
///
/// Uporablja se za kratke sezname, kot so hitrost predvajanja, vrstni red
/// predvajanja, sortiranje in sleep timer. Aktivna izbira je označena s
/// kljukico, zato lahko vsak klicatelj uporablja isti vizualni jezik.
class AppSelectMenu<T> extends StatelessWidget {
  const AppSelectMenu({
    required this.value,
    required this.options,
    required this.onSelected,
    required this.tooltip,
    this.enabled = true,
    this.icon,
    this.child,
    super.key,
  }) : assert(icon != null || child != null);

  final T? value;
  final List<AppSelectOption<T>> options;
  final ValueChanged<T> onSelected;
  final String tooltip;
  final bool enabled;
  final Widget? icon;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: tooltip,
      initialValue: value,
      onSelected: enabled ? onSelected : null,
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem(
            value: option.value,
            child: Row(
              children: [
                if (option.icon != null) ...[
                  Icon(option.icon, size: 20),
                  const SizedBox(width: 12),
                ],
                Expanded(child: Text(option.label)),
                if (option.value == value) ...[
                  const SizedBox(width: 12),
                  Icon(
                    Icons.check,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ],
            ),
          ),
      ],
      icon: icon,
      child: child,
    );
  }
}
