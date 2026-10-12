import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme_extensions.dart';

/// Shown in place of an editable section (design, forms, links,
/// integrations) when that section is currently resolved from the
/// organization's shared template member instead of from the profile being
/// viewed/edited. Used both in the admin "edit member" dialog
/// (`lib/features/admin/views/admin_view.dart`) and in the member's own
/// `EditCardView`, so its visual style stays identical in both places.
class SharedTemplateLockBanner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final double maxWidth;

  const SharedTemplateLockBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.maxWidth = 760,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.24),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 23),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message,
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          height: 1.45,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
