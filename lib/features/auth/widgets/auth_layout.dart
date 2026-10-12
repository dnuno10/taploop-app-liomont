import 'package:flutter/material.dart';
import '../../../core/utils/responsive.dart';

/// Wraps auth screens in a centered, scrollable, responsive card layout.
class AuthLayout extends StatelessWidget {
  final Widget child;

  const AuthLayout({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final cardWidth = Responsive.authCardWidth(context);
    final hPadding = Responsive.authPadding(context);
    final verticalPadding = isMobile ? 16.0 : 46.0;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : hPadding,
              vertical: verticalPadding,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: cardWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 22 : 52,
                      vertical: isMobile ? 24 : 52,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(isMobile ? 28 : 32),
                      border: Border.all(
                        color: const Color(0xFFE4E9F0),
                        width: 1,
                      ),
                    ),
                    child: child,
                  ),
                  SizedBox(height: isMobile ? 20 : 28),
                  const Text(
                    'ACCESO CORPORATIVO',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF8A94A6),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Image.asset(
                    'assets/images/liomont.png',
                    height: isMobile ? 22 : 26,
                    fit: BoxFit.contain,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
