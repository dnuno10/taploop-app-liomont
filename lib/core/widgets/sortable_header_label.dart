import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Column header that sorts its table when tapped, showing an arrow for the
/// active column and direction.
class SortableHeaderLabel extends StatelessWidget {
  final String title;
  final bool active;
  final bool ascending;
  final VoidCallback onTap;
  final TextStyle style;

  const SortableHeaderLabel({
    super.key,
    required this.title,
    required this.active,
    required this.ascending,
    required this.onTap,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : style.color;
    return Tooltip(
      message: 'Ordenar por ${title.toLowerCase()}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style.copyWith(color: color),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                active
                    ? (ascending
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded)
                    : Icons.unfold_more_rounded,
                size: 16,
                color: color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
