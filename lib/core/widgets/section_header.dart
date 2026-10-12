import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme_extensions.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final String? helpText;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.helpText,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                  ),
                  HelpTooltip(
                    message: helpText ?? _defaultHelpMessage(title, subtitle),
                  ),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class HelpTooltip extends StatelessWidget {
  final String message;

  const HelpTooltip({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      waitDuration: const Duration(milliseconds: 350),
      showDuration: const Duration(seconds: 5),
      triggerMode: TooltipTriggerMode.longPress,
      preferBelow: false,
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Icon(
          Icons.help_outline_rounded,
          size: 16,
          color: context.textSecondary.withValues(alpha: 0.46),
        ),
      ),
    );
  }
}

class HelpTitle extends StatelessWidget {
  final String title;
  final String? helpText;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  const HelpTitle({
    super.key,
    required this.title,
    this.helpText,
    this.style,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            title,
            style: style,
            maxLines: maxLines,
            overflow: overflow,
          ),
        ),
        HelpTooltip(message: helpText ?? _defaultHelpMessage(title, null)),
      ],
    );
  }
}

String _defaultHelpMessage(String title, String? subtitle) {
  final cleanTitle = title.trim();
  final cleanSubtitle = subtitle?.trim();
  if (cleanSubtitle != null && cleanSubtitle.isNotEmpty) {
    return cleanSubtitle;
  }
  if (cleanTitle.isEmpty) {
    return 'Explica la funcionalidad de este bloque.';
  }
  return 'Explica la funcionalidad del bloque "$cleanTitle".';
}
