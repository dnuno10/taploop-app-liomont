import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/data/app_state.dart';
import '../../../core/data/repositories/card_repository.dart';
import '../../../core/data/repositories/analytics_repository.dart';
import '../../../core/data/repositories/lead_repository.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/utils/visitor_info.dart';
import '../../../core/widgets/native_web_image.dart';
import '../../../core/widgets/platform_icon.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/taploop_progress_indicator.dart';
import '../../../core/widgets/taploop_toast.dart';
import '../models/digital_card_model.dart';
import '../models/contact_item_model.dart';
import '../models/social_link_model.dart';
import '../models/smart_form_model.dart';
import '../utils/calendar_links.dart';
import '../utils/vcard_download_stub.dart'
    if (dart.library.html) '../utils/vcard_download_web.dart';

// ─── NFC serial state ─────────────────────────────────────────────────────────
enum _NfcState { loading, showCard, unassigned, notFound }

class PublicCardView extends StatefulWidget {
  final String? slug;
  final String? userId;
  final String? nfcSerial;

  /// 'qr' when opened from a QR scan, null/'' for regular link share
  final String? via;
  const PublicCardView({
    super.key,
    this.slug,
    this.userId,
    this.nfcSerial,
    this.via,
  }) : assert(slug != null || userId != null || nfcSerial != null);

  @override
  State<PublicCardView> createState() => _PublicCardViewState();
}

class _PublicCardViewState extends State<PublicCardView> {
  DigitalCardModel? _card;
  bool _loading = true;
  bool _notFound = false;
  // A network/Postgrest exception was thrown (e.g. the phone's connection
  // was still waking up after the page sat idle overnight) — distinct from
  // _notFound, which only means the query succeeded and returned no row.
  bool _loadFailed = false;
  String? _errorDetail;
  // True until we know whether the org has a logo, so the header can
  // reserve the logo's slot from the very first frame instead of the logo
  // popping in later and pushing the rest of the header down.
  bool _logoPending = true;
  // NFC-specific
  _NfcState _nfcState = _NfcState.loading;
  bool _activating = false;
  String? _activationError;

  bool get _isNfcFlow => widget.nfcSerial != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _hydrateOrganizationLogo(DigitalCardModel? card) async {
    if (card == null) {
      if (mounted) setState(() => _logoPending = false);
      return;
    }
    if (card.companyLogoUrl?.trim().isNotEmpty == true) {
      if (mounted) setState(() => _logoPending = false);
      return;
    }
    final directOrgId = card.orgId?.trim();
    final orgId = directOrgId?.isNotEmpty == true
        ? directOrgId
        : await CardRepository.resolveCardOrganizationId({
            'org_id': card.orgId,
            'user_id': card.userId,
          });
    if (!mounted || _card?.id != card.id) return;
    if (orgId == null || orgId.isEmpty) {
      setState(() => _logoPending = false);
      return;
    }
    final orgLogoUrl = await CardRepository.fetchOrganizationLogoUrl(orgId);
    if (!mounted || _card?.id != card.id) return;
    setState(() {
      _logoPending = false;
      if (orgLogoUrl != null &&
          orgLogoUrl.isNotEmpty &&
          _card?.companyLogoUrl != orgLogoUrl) {
        _card = _card?.copyWith(companyLogoUrl: orgLogoUrl);
      }
    });
  }

  /// Retries transient failures (e.g. the phone's connection still waking
  /// up after this page sat idle/backgrounded overnight) a couple of times
  /// before giving up, instead of surfacing a network blip as "card not
  /// found" on the very first attempt.
  Future<T> _fetchWithRetry<T>(
    Future<T> Function() request, {
    int retries = 2,
    Duration initialDelay = const Duration(milliseconds: 500),
  }) async {
    var delay = initialDelay;
    for (var attempt = 0; ; attempt++) {
      try {
        return await request();
      } catch (error) {
        if (attempt >= retries) rethrow;
        await Future.delayed(delay);
        delay *= 2;
      }
    }
  }

  void _retryLoad() {
    setState(() {
      _loading = true;
      _loadFailed = false;
      _notFound = false;
      _errorDetail = null;
    });
    _load();
  }

  Future<void> _load() async {
    try {
      if (_isNfcFlow) {
        await _loadNfc();
      } else {
        DigitalCardModel? card;
        if (widget.userId != null) {
          card = await _fetchWithRetry(
            () => CardRepository.fetchByUserId(
              widget.userId!,
              includeOrganizationLogo: false,
            ),
          );
        } else {
          card = await _fetchWithRetry(
            () => CardRepository.fetchBySlug(
              widget.slug!,
              includeOrganizationLogo: false,
            ),
          );
        }
        if (mounted) {
          setState(() {
            _card = card;
            _notFound = card == null;
            _loading = false;
            _logoPending = true;
          });
        }
        if (card != null && card.isActive) {
          final source = (widget.via == 'qr') ? 'qr' : 'link';
          unawaited(AnalyticsRepository.recordVisit(card.id, source));
        }
        unawaited(_hydrateOrganizationLogo(card));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadFailed = true;
          _errorDetail = e.toString();
        });
      }
    }
  }

  Future<void> _loadNfc() async {
    final resolved = await _fetchWithRetry(
      () => CardRepository.resolveNfcSerial(
        widget.nfcSerial!,
        includeOrganizationLogo: false,
      ),
    );
    if (!mounted) return;
    if (resolved.status == 'not_found') {
      setState(() {
        _nfcState = _NfcState.notFound;
        _loading = false;
      });
      return;
    }
    if (resolved.status == 'unassigned') {
      setState(() {
        _nfcState = _NfcState.unassigned;
        _loading = false;
      });
      return;
    }
    // assigned — load the card
    final card = resolved.card;
    if (mounted) {
      setState(() {
        _card = card;
        _nfcState = _NfcState.showCard;
        _loading = false;
        _logoPending = true;
      });
    }
    if (card != null && card.isActive) {
      unawaited(AnalyticsRepository.recordVisit(card.id, 'nfc'));
    }
    unawaited(_hydrateOrganizationLogo(card));
  }

  Future<void> _activate() async {
    if (!appState.isAuthenticated) {
      final serial = Uri.encodeComponent(widget.nfcSerial!);
      context.go('/?pendingNfc=$serial');
      return;
    }
    setState(() {
      _activating = true;
      _activationError = null;
    });
    try {
      final targetCard = await _resolveTargetCardForActivation();
      if (targetCard == null) {
        setState(() {
          _activationError =
              'No se encontró una tarjeta digital para vincular este NFC.';
          _activating = false;
        });
        return;
      }

      final ok = await CardRepository.activateNfcCard(
        widget.nfcSerial!,
        targetCard.id,
      );
      if (!mounted) return;
      if (ok) {
        final user = appState.currentUser;
        if (user != null) {
          final cards = await AuthService.fetchUserCards(user.id);
          if (!mounted) return;
          appState.setCards(cards, selectedCardId: targetCard.id);
        }
        // Activación exitosa — ir al dashboard
        context.go('/');
      } else {
        setState(() {
          _activationError = 'Esta tarjeta ya fue activada por otra cuenta.';
          _activating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _activationError = e.toString();
          _activating = false;
        });
      }
    }
  }

  Future<DigitalCardModel?> _resolveTargetCardForActivation() async {
    final selectedCard = appState.currentCard;
    if (selectedCard != null) return selectedCard;

    if (appState.userCards.isNotEmpty) {
      final fallback = appState.userCards.first;
      appState.selectCardById(fallback.id);
      return fallback;
    }

    final user = appState.currentUser;
    if (user == null) return null;
    final createdCard = await CardRepository.ensureDigitalCardForUser(user.id);
    if (!mounted) return null;
    appState.addCard(createdCard);
    return createdCard;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(child: TapLoopProgressIndicator(color: AppColors.primary)),
      );
    }

    // ── NFC flows ──
    if (_isNfcFlow) {
      if (_nfcState == _NfcState.notFound) {
        return _NotFoundPage(slug: widget.nfcSerial!, errorDetail: null);
      }
      if (_nfcState == _NfcState.unassigned) {
        return _NfcActivationPage(
          serial: widget.nfcSerial!,
          isLoggedIn: appState.isAuthenticated,
          activating: _activating,
          error: _activationError,
          onActivate: _activate,
          onLogin: () => context.push('/?pendingNfc=${widget.nfcSerial}'),
        );
      }
    }

    if (_loadFailed) {
      return _LoadErrorPage(errorDetail: _errorDetail, onRetry: _retryLoad);
    }

    // ── Normal slug/userId flow ──
    if (_notFound || _card == null) {
      return _NotFoundPage(
        slug: widget.slug ?? widget.nfcSerial ?? widget.userId ?? '',
        errorDetail: null,
      );
    }
    if (!_card!.isActive) {
      return _CardDeactivatedPage(
        message: _card!.deactivationReason?.trim().isNotEmpty == true
            ? _card!.deactivationReason!
            : 'Tarjeta digital desactivada por seguridad',
      );
    }
    return _CardPage(card: _card!, logoPending: _logoPending);
  }
}

// ─── Theme helpers (mirrors DigitalProfilePreview logic exactly) ──────────────

Color _cardAccent(DigitalCardModel card) => card.primaryColor;

Color _cardBgBase(DigitalCardModel card) => card.bgColor ?? Colors.white;

Color _cardTextColor(DigitalCardModel card) {
  final base = card.bgColor ?? Colors.white;
  final end = card.bgColorEnd;
  final sampled = switch (card.bgStyle) {
    CardBgStyle.gradient ||
    CardBgStyle.mesh => Color.lerp(base, end ?? base, 0.5) ?? base,
    CardBgStyle.plain || CardBgStyle.stripes => base,
  };
  return _contrastTextColor(sampled);
}

Color _contrastTextColor(Color color) {
  return ThemeData.estimateBrightnessForColor(color) == Brightness.dark
      ? Colors.white
      : const Color(0xFF0D0D0D);
}

/// Mirrors _ScreenContent._buildBgDecoration from digital_profile_preview.dart
BoxDecoration _buildPageDecoration(DigitalCardModel card) {
  final bgBase = card.bgColor ?? _cardBgBase(card);
  switch (card.bgStyle) {
    case CardBgStyle.gradient:
      return BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bgBase, card.bgColorEnd ?? _darkenColor(bgBase)],
        ),
      );
    case CardBgStyle.mesh:
      return BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0.2, -0.6),
          radius: 1.6,
          colors: [
            card.bgColorEnd ?? Colors.white.withValues(alpha: 0.45),
            bgBase,
          ],
        ),
      );
    default:
      return BoxDecoration(color: bgBase);
  }
}

Future<bool> _launchPublicUri(
  Uri uri, {
  LaunchMode mode = LaunchMode.externalApplication,
}) async {
  try {
    return await launchUrl(uri, mode: mode, webOnlyWindowName: '_self');
  } catch (error) {
    debugPrint('[PublicCard] launch error for $uri: $error');
    return false;
  }
}

String _normalizeWebUrl(String raw) {
  final value = raw.trim();
  if (value.startsWith(RegExp(r'https?://'))) return value;
  return 'https://$value';
}

String _normalizePublicSocialUrl(SocialLinkModel link) {
  final raw = link.url.trim();
  if (raw.isEmpty) return raw;
  if (link.platform == SocialPlatform.instagram) {
    return _normalizeInstagramUrl(raw);
  }
  if (link.platform == SocialPlatform.whatsapp) {
    return _normalizeWhatsAppSocialUrl(raw);
  }
  return _normalizeWebUrl(raw);
}

String _normalizeWhatsAppSocialUrl(String raw) {
  final value = raw.trim();
  if (value.startsWith('whatsapp://')) return value;
  if (value.startsWith(RegExp(r'https?://'))) return value;
  if (value.startsWith('wa.me/') || value.startsWith('api.whatsapp.com/')) {
    return 'https://$value';
  }
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return _normalizeWebUrl(value);
  return 'https://wa.me/$digits';
}

String _normalizeInstagramUrl(String raw) {
  final value = raw.trim();
  if (value.startsWith(RegExp(r'https?://'))) return value;
  if (value.startsWith('instagram://')) return value;

  if (value.startsWith('@')) {
    return 'https://www.instagram.com/${value.substring(1)}';
  }

  if (value.startsWith('www.instagram.com/') ||
      value.startsWith('instagram.com/')) {
    return value.startsWith('www.') ? 'https://$value' : 'https://www.$value';
  }

  final normalizedHandle = value
      .replaceFirst(RegExp(r'^/+'), '')
      .replaceFirst(RegExp(r'^@+'), '');
  return 'https://www.instagram.com/$normalizedHandle';
}

class _CardDeactivatedPage extends StatelessWidget {
  final String message;

  const _CardDeactivatedPage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    size: 42,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Esta tarjeta no se encuentra disponible temporalmente.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      height: 1.5,
                      color: const Color(0xFF6B7280),
                    ),
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

Color _darkenColor(Color c) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness - 0.2).clamp(0.0, 1.0)).toColor();
}

class _StripePainter extends CustomPainter {
  final Color bgColor;
  const _StripePainter(this.bgColor);

  @override
  void paint(Canvas canvas, Size size) {
    final isDark =
        ThemeData.estimateBrightnessForColor(bgColor) == Brightness.dark;
    final paint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06)
      ..strokeWidth = size.width * 0.025;
    final gap = size.width * 0.1;
    for (double i = -size.height; i < size.width + size.height; i += gap) {
      canvas.drawLine(
        Offset(i, 0),
        Offset(i + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StripePainter old) => old.bgColor != bgColor;
}

// ─── Card Page ────────────────────────────────────────────────────────────────

Widget _buildCardHeader(DigitalCardModel card, bool logoPending) =>
    _HeroHeader(card: card, logoPending: logoPending);

class _CardPage extends StatelessWidget {
  final DigitalCardModel card;
  final bool logoPending;
  const _CardPage({required this.card, this.logoPending = false});

  @override
  Widget build(BuildContext context) {
    final visibleContacts = card.contactItems.where((c) => c.isVisible).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final visibleSocials = card.socialLinks.where((s) => s.isVisible).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final accent = _cardAccent(card);
    final textCol = _cardTextColor(card);
    final bgBase = card.bgColor ?? _cardBgBase(card);
    final isModern = card.usesModernProfileDesign;

    final scrollView = CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildCardHeader(card, logoPending)),
        SliverToBoxAdapter(
          child: _SaveContactButton(
            card: card,
            contacts: visibleContacts,
            accent: accent,
          ),
        ),
        if (isModern)
          SliverToBoxAdapter(
            child: _ModernActionButtons(
              card: card,
              contacts: visibleContacts,
              accent: accent,
              iconColor: card.iconColor,
            ),
          ),
        if (isModern && visibleSocials.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _ModernSectionHeader(
              title: 'Conecta conmigo',
              textColor: textCol,
            ),
          ),
          SliverToBoxAdapter(
            child: _ModernSocialCircles(
              links: visibleSocials,
              cardId: card.id,
              customIconColor: card.iconColor,
            ),
          ),
        ],
        if (visibleContacts.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: isModern
                ? _ModernSectionHeader(title: 'Contacto', textColor: textCol)
                : _SectionHeader(title: 'Contacto', textColor: textCol),
          ),
          SliverToBoxAdapter(
            child: _ContactSection(
              items: visibleContacts,
              textColor: textCol,
              cardId: card.id,
              modern: isModern,
            ),
          ),
        ],
        if (!isModern && visibleSocials.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(title: 'Redes sociales', textColor: textCol),
          ),
          SliverToBoxAdapter(
            child: _SocialSection(
              links: visibleSocials,
              textColor: textCol,
              cardId: card.id,
              customIconColor: card.iconColor,
            ),
          ),
        ],
        if (card.calendarEnabled &&
            (card.calendarUrl?.trim().isNotEmpty ?? false)) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(title: 'Agendar reunión', textColor: textCol),
          ),
          SliverToBoxAdapter(
            child: _CalendarButton(
              url: card.calendarUrl!,
              accent: accent,
              textColor: textCol,
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: _FormsSection(card: card, accent: accent, textColor: textCol),
        ),
        SliverToBoxAdapter(
          child: _Footer(card: card, accent: accent),
        ),
      ],
    );

    if (card.bgStyle == CardBgStyle.stripes) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: bgBase),
            CustomPaint(painter: _StripePainter(bgBase)),
            scrollView,
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: _buildPageDecoration(card),
        child: scrollView,
      ),
    );
  }
}

// ─── Save Contact Button ─────────────────────────────────────────────────────

class _SaveContactButton extends StatelessWidget {
  final DigitalCardModel card;
  final List<ContactItemModel> contacts;
  final Color accent;

  const _SaveContactButton({
    required this.card,
    required this.contacts,
    required this.accent,
  });

  Future<void> _downloadVCard() async {
    final vcard = _buildVCard(card, contacts);
    final fileName = '${_safeFileName(card.name)}.vcf';
    final downloaded = await downloadVCardFile(fileName, vcard);
    if (downloaded) {
      await AnalyticsRepository.recordInteraction(
        cardId: card.id,
        source: 'downloaded_contact',
      );
    }
  }

  static String _buildVCard(
    DigitalCardModel card,
    List<ContactItemModel> contacts,
  ) {
    final lines = <String>[
      'BEGIN:VCARD',
      'VERSION:3.0',
      'FN:${_escapeVCard(card.name)}',
    ];

    final nameParts = card.name.trim().split(RegExp(r'\s+'));
    if (nameParts.isNotEmpty && nameParts.first.isNotEmpty) {
      final firstName = nameParts.first;
      final lastName = nameParts.length > 1
          ? nameParts.sublist(1).join(' ')
          : '';
      lines.add('N:${_escapeVCard(lastName)};${_escapeVCard(firstName)};;;');
    }
    if (card.company.trim().isNotEmpty) {
      lines.add('ORG:${_escapeVCard(card.company.trim())}');
    }
    if (card.jobTitle.trim().isNotEmpty) {
      lines.add('TITLE:${_escapeVCard(card.jobTitle.trim())}');
    }
    if (card.bio?.trim().isNotEmpty == true) {
      lines.add('NOTE:${_escapeVCard(card.bio!.trim())}');
    }
    if (card.profilePhotoUrl?.trim().isNotEmpty == true) {
      lines.add(
        'PHOTO;VALUE=URI:${_escapeVCard(card.profilePhotoUrl!.trim())}',
      );
    }
    if (card.companyLogoUrl?.trim().isNotEmpty == true) {
      lines.add('LOGO;VALUE=URI:${_escapeVCard(card.companyLogoUrl!.trim())}');
    }

    for (final item in contacts) {
      final value = item.value.trim();
      if (value.isEmpty) continue;
      switch (item.type) {
        case ContactType.phone:
          lines.add('TEL;TYPE=CELL:${_escapeVCard(value)}');
          break;
        case ContactType.whatsapp:
          lines.add('TEL;TYPE=CELL;TYPE=VOICE:${_escapeVCard(value)}');
          lines.add(
            'URL;TYPE=WhatsApp:${_escapeVCard('https://wa.me/${value.replaceAll(RegExp(r'\D'), '')}')}',
          );
          break;
        case ContactType.email:
          lines.add('EMAIL;TYPE=INTERNET:${_escapeVCard(value)}');
          break;
        case ContactType.address:
          lines.add('ADR;TYPE=WORK:;;${_escapeVCard(value)};;;;');
          break;
        case ContactType.website:
          final url = value.startsWith('http') ? value : 'https://$value';
          lines.add('URL:${_escapeVCard(url)}');
          break;
      }
    }

    lines
      ..add('URL:${_escapeVCard(card.publicUrl)}')
      ..add('END:VCARD');
    return '${lines.join('\r\n')}\r\n';
  }

  static String _escapeVCard(String value) {
    return value
        .replaceAll('\\', r'\\')
        .replaceAll(';', r'\;')
        .replaceAll(',', r'\,')
        .replaceAll('\r\n', r'\n')
        .replaceAll('\n', r'\n');
  }

  static String _safeFileName(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return normalized.isEmpty ? 'contacto-taploop' : normalized;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _downloadVCard,
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 20),
              label: const Text('Guardar contacto'),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                textStyle: GoogleFonts.dmSans(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModernActionButtons extends StatelessWidget {
  final DigitalCardModel card;
  final List<ContactItemModel> contacts;
  final Color accent;
  final Color iconColor;

  const _ModernActionButtons({
    required this.card,
    required this.contacts,
    required this.accent,
    required this.iconColor,
  });

  ContactItemModel? get _emailContact {
    for (final item in contacts) {
      if (item.type == ContactType.email && item.value.trim().isNotEmpty) {
        return item;
      }
    }
    return null;
  }

  Future<void> _sendEmail() async {
    final email = _emailContact;
    if (email == null) return;
    final uri = Uri(scheme: 'mailto', path: email.value.trim());
    await AnalyticsRepository.recordInteraction(
      cardId: card.id,
      source: 'contact',
      contactItemId: email.id,
    );
    await _launchPublicUri(uri);
  }

  Future<void> _share(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: card.publicUrl));
    await AnalyticsRepository.recordInteraction(
      cardId: card.id,
      source: 'share',
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Enlace copiado',
          style: GoogleFonts.dmSans(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasEmail = _emailContact != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Row(
            children: [
              if (hasEmail) ...[
                Expanded(
                  child: _ModernSecondaryButton(
                    icon: Icons.email_rounded,
                    label: 'Enviar correo',
                    iconColor: iconColor,
                    onTap: _sendEmail,
                  ),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: _ModernSecondaryButton(
                  icon: Icons.share_rounded,
                  label: 'Compartir',
                  iconColor: iconColor,
                  onTap: () => _share(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModernSecondaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final VoidCallback? onTap;

  const _ModernSecondaryButton({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFE5E7EB), width: 1.2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 21,
                color: onTap == null ? Colors.grey : iconColor,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 17,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                    color: onTap == null
                        ? Colors.grey
                        : const Color(0xFF0D0D0D),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Hero Header ──────────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
  final DigitalCardModel card;
  final bool logoPending;
  const _HeroHeader({required this.card, this.logoPending = false});

  @override
  Widget build(BuildContext context) {
    final accent = _cardAccent(card);
    final textCol = _cardTextColor(card);
    final subCol = textCol.withValues(alpha: 0.65);
    const logoMaxWidth = 220.0;
    const logoHeight = 58.0;
    const avatarSize = 112.0;
    const nameSize = 34.0;
    const titleSize = 20.0;
    const companySize = 14.0;
    const bioSize = 14.0;

    return Container(
      width: double.infinity,
      color: Colors.transparent,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 46, 24, 18),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Logo de empresa (primero). While we don't yet know if
                  // the org has a logo (logoPending), reserve the same slot
                  // so that if one arrives it fades into existing space
                  // instead of pushing the rest of the header down.
                  if ((card.companyLogoUrl != null &&
                          card.companyLogoUrl!.isNotEmpty) ||
                      logoPending)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 34),
                      child: _PublicCompanyLogo(
                        imageUrl: card.companyLogoUrl,
                        maxWidth: logoMaxWidth,
                        height: logoHeight,
                      ),
                    ),
                  // Avatar del usuario
                  _PublicProfileAvatar(
                    imageUrl: card.profilePhotoUrl,
                    size: avatarSize,
                    accent: accent,
                  ),
                  const SizedBox(height: 26),
                  // Nombre
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          card.name,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            fontSize: nameSize,
                            height: 1.02,
                            fontWeight: FontWeight.w800,
                            color: textCol,
                          ),
                        ),
                      ),
                      if (card.showVerifiedBadge) ...[
                        const SizedBox(width: 9),
                        Icon(
                          Icons.verified_rounded,
                          size: 27,
                          color: const Color(0xFF2F9DEB),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Puesto
                  Text(
                    card.jobTitle,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: titleSize,
                      height: 1.12,
                      fontWeight: FontWeight.w800,
                      color: textCol,
                    ),
                  ),
                  // Compañía
                  if (card.company.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      card.company,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.dmSans(
                        fontSize: companySize,
                        fontWeight: FontWeight.w700,
                        color: subCol,
                      ),
                    ),
                  ],
                  if (card.bio != null && card.bio!.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        card.bio!,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.dmSans(
                          fontSize: bioSize,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF6B7280),
                          height: 1.42,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PublicCompanyLogo extends StatelessWidget {
  // Null/empty while the org's logo hasn't resolved yet: renders an empty
  // placeholder of the same size so the reserved slot doesn't shift once
  // the real logo (or the "no logo" outcome) arrives.
  final String? imageUrl;
  final double maxWidth;
  final double height;

  const _PublicCompanyLogo({
    required this.imageUrl,
    required this.maxWidth,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SizedBox(
        width: maxWidth,
        height: height,
        child: (url == null || url.isEmpty)
            ? null
            : NativeWebImage(
                imageUrl: url,
                width: maxWidth,
                height: height,
                fit: BoxFit.contain,
                eager: true,
                highPriority: true,
              ),
      ),
    );
  }
}

class _PublicProfileAvatar extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final Color accent;

  const _PublicProfileAvatar({
    required this.imageUrl,
    required this.size,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final cleanedUrl = imageUrl?.trim();
    final hasImage = cleanedUrl != null && cleanedUrl.isNotEmpty;
    final placeholder = _AvatarIcon(size: size, accent: accent);

    return SizedBox(
      width: size,
      height: size,
      child: hasImage
          ? ClipOval(
              child: NativeWebImage(
                imageUrl: cleanedUrl,
                fit: BoxFit.cover,
                width: size,
                height: size,
                shape: BoxShape.circle,
                fallback: placeholder,
                eager: true,
                highPriority: true,
              ),
            )
          : placeholder,
    );
  }
}

class _AvatarIcon extends StatelessWidget {
  final double size;
  final Color accent;

  const _AvatarIcon({required this.size, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(
          Icons.person_outline_rounded,
          size: size * 0.42,
          color: accent,
        ),
      ),
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color textColor;
  const _SectionHeader({required this.title, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 44, 20, 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SizedBox(
            width: double.infinity,
            child: HelpTitle(
              title: title.toUpperCase(),
              helpText: 'Muestra la sección pública de $title en esta tarjeta.',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: textColor.withValues(alpha: 0.55),
                letterSpacing: 1.6,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Contact Section ──────────────────────────────────────────────────────────

class _ContactSection extends StatelessWidget {
  final List<ContactItemModel> items;
  final Color textColor;
  final String cardId;
  final bool modern;
  const _ContactSection({
    required this.items,
    required this.textColor,
    required this.cardId,
    this.modern = false,
  });

  Future<void> _handleTap(ContactItemModel item) async {
    final value = item.value.trim();
    if (value.isEmpty) return;

    final Uri uri;
    switch (item.type) {
      case ContactType.phone:
        uri = Uri(scheme: 'tel', path: value);
        break;
      case ContactType.whatsapp:
        final cleaned = value.replaceAll(RegExp(r'\D'), '');
        if (cleaned.isEmpty) return;
        uri = Uri.parse('https://wa.me/$cleaned');
        break;
      case ContactType.email:
        uri = Uri(scheme: 'mailto', path: value);
        break;
      case ContactType.address:
        uri = Uri.parse(
          'https://maps.google.com/?q=${Uri.encodeComponent(value)}',
        );
        break;
      case ContactType.website:
        uri = Uri.parse(_normalizeWebUrl(value));
        break;
    }
    await AnalyticsRepository.recordInteraction(
      cardId: cardId,
      source: 'contact',
      contactItemId: item.id,
    );
    await _launchPublicUri(uri);
  }

  String _displayValue(ContactItemModel item) {
    final value = item.value.trim();
    if (item.type != ContactType.website || value.isEmpty) return value;
    try {
      final uri = Uri.parse(
        value.startsWith('http') ? value : 'https://$value',
      );
      final host = uri.host.replaceFirst(RegExp(r'^www\.'), '');
      return host.isNotEmpty ? host : value;
    } catch (_) {
      return value
          .replaceFirst(RegExp(r'^https?://'), '')
          .replaceFirst(RegExp(r'^www\.'), '')
          .split('/')
          .first;
    }
  }

  String _modernLabel(ContactItemModel item) {
    return switch (item.type) {
      ContactType.phone => 'Llamar',
      ContactType.whatsapp => 'Enviar WhatsApp',
      ContactType.email => 'Enviar correo',
      ContactType.address => 'Cómo llegar',
      ContactType.website =>
        item.displayLabel.isNotEmpty ? item.displayLabel : 'Visitar sitio web',
    };
  }

  @override
  Widget build(BuildContext context) {
    const tileBorder = Color(0xFFE5E7EB);
    const tileBg = Colors.white;
    const labelColor = Color(0xFF6B7280);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            children: [
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(modern ? 999 : 16),
                    child: InkWell(
                      onTap: () => _handleTap(item),
                      borderRadius: BorderRadius.circular(modern ? 999 : 16),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: modern ? 24 : 14,
                          vertical: modern ? 18 : 11,
                        ),
                        decoration: BoxDecoration(
                          color: tileBg,
                          borderRadius: BorderRadius.circular(
                            modern ? 999 : 16,
                          ),
                          border: Border.all(
                            color: tileBorder,
                            width: modern ? 1.2 : 1.1,
                          ),
                        ),
                        child: Row(
                          children: [
                            PlatformIcon.contact(
                              contactType: item.type,
                              size: modern ? 24 : 22,
                              framed: !modern,
                            ),
                            SizedBox(width: modern ? 18 : 14),
                            Expanded(
                              child: modern
                                  ? Text(
                                      _modernLabel(item),
                                      style: GoogleFonts.outfit(
                                        fontSize: 17,
                                        height: 1.08,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF0D0D0D),
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.visible,
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          item.displayLabel,
                                          style: GoogleFonts.dmSans(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: labelColor,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _displayValue(item),
                                          style: GoogleFonts.outfit(
                                            fontSize: 17,
                                            height: 1.18,
                                            fontWeight: FontWeight.w600,
                                            color: textColor,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                            ),
                            Icon(
                              modern
                                  ? Icons.arrow_forward_rounded
                                  : Icons.chevron_right_rounded,
                              size: modern ? 28 : 22,
                              color: modern
                                  ? const Color(0xFF0D0D0D)
                                  : const Color(0xFF9CA3AF),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModernSectionHeader extends StatelessWidget {
  final String title;
  final Color textColor;

  const _ModernSectionHeader({required this.title, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SizedBox(
            width: double.infinity,
            child: HelpTitle(
              title: title,
              helpText: 'Muestra la sección pública de $title en esta tarjeta.',
              style: GoogleFonts.outfit(
                fontSize: 19,
                height: 1.1,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModernSocialCircles extends StatelessWidget {
  final List<SocialLinkModel> links;
  final String cardId;
  final Color customIconColor;

  const _ModernSocialCircles({
    required this.links,
    required this.cardId,
    required this.customIconColor,
  });

  Future<void> _openUrl(SocialLinkModel link) async {
    final normalizedUrl = _normalizePublicSocialUrl(link);
    if (normalizedUrl.isEmpty) return;
    final uri = Uri.parse(normalizedUrl);
    await AnalyticsRepository.recordInteraction(
      cardId: cardId,
      source: 'social',
      socialLinkId: link.id,
    );
    await _launchPublicUri(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.start,
              spacing: 13,
              runSpacing: 13,
              children: [
                for (final link in links)
                  Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _openUrl(link),
                      child: Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFE5E7EB),
                            width: 1.1,
                          ),
                        ),
                        child: Center(
                          child: PlatformIcon.social(
                            platform: link.platform,
                            framed: false,
                            size: 34,
                            color: link.platform == SocialPlatform.custom
                                ? customIconColor
                                : null,
                            iconKey: link.iconKey,
                          ),
                        ),
                      ),
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

// ─── Social Section ───────────────────────────────────────────────────────────

class _SocialSection extends StatelessWidget {
  final List<SocialLinkModel> links;
  final Color textColor;
  final String cardId;
  final Color customIconColor;
  const _SocialSection({
    required this.links,
    required this.textColor,
    required this.cardId,
    required this.customIconColor,
  });

  Future<void> _openUrl(SocialLinkModel link) async {
    final normalizedUrl = _normalizePublicSocialUrl(link);
    if (normalizedUrl.isEmpty) return;
    final uri = Uri.parse(normalizedUrl);
    await AnalyticsRepository.recordInteraction(
      cardId: cardId,
      source: 'social',
      socialLinkId: link.id,
    );
    await _launchPublicUri(uri);
  }

  String _shortHandle(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        final handle = segments.last;
        return handle.startsWith('@') ? handle : '@$handle';
      }
    } catch (_) {}
    if (url.trim().startsWith('@')) return url.trim();
    return url;
  }

  @override
  Widget build(BuildContext context) {
    const tileBorder = Color(0xFFE5E7EB);
    const tileBg = Colors.white;
    const labelColor = Color(0xFF6B7280);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            children: [
              for (final link in links)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      onTap: () => _openUrl(link),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: tileBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: tileBorder, width: 1.1),
                        ),
                        child: Row(
                          children: [
                            PlatformIcon.social(
                              platform: link.platform,
                              size: 22,
                              color: link.platform == SocialPlatform.custom
                                  ? customIconColor
                                  : null,
                              iconKey: link.iconKey,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    link.label,
                                    style: GoogleFonts.outfit(
                                      fontSize: 17,
                                      height: 1.12,
                                      fontWeight: FontWeight.w600,
                                      color: textColor,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _shortHandle(link.url),
                                    style: GoogleFonts.dmSans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: labelColor,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 22,
                              color: const Color(0xFF9CA3AF),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Footer ───────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  final DigitalCardModel card;
  final Color accent;
  const _Footer({required this.card, required this.accent});

  @override
  Widget build(BuildContext context) {
    final textCol = _cardTextColor(card);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 48),
      child: Center(
        child: Column(
          children: [
            Divider(color: textCol.withValues(alpha: 0.15)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () async {
                final uri = Uri.parse('https://www.taploop.com.mx');
                await _launchPublicUri(uri);
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Creado con ',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      color: textCol.withValues(alpha: 0.5),
                    ),
                  ),
                  Text(
                    'TapLoop',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Calendar Button ─────────────────────────────────────────────────────────

class _CalendarButton extends StatelessWidget {
  final String url;
  final Color accent;
  final Color textColor;
  const _CalendarButton({
    required this.url,
    required this.accent,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final integrations = parseCalendarIntegrationLinks(url);

    Future<void> openIntegration(CalendarIntegrationLink integration) async {
      if (integration.url.trim().isEmpty) return;
      final uri = Uri.parse(normalizeCalendarUrl(integration.url));
      await _launchPublicUri(uri);
    }

    if (integrations.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            children: [
              for (final integration in integrations)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    width: double.infinity,
                    child: Material(
                      color: accent,
                      borderRadius: BorderRadius.circular(999),
                      child: InkWell(
                        onTap: () => openIntegration(integration),
                        borderRadius: BorderRadius.circular(999),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 26,
                            vertical: 20,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _calendarProviderIcon(integration.provider),
                                size: 25,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  integration.displayLabel,
                                  style: GoogleFonts.outfit(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                size: 30,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _calendarProviderIcon(CalendarProviderType provider) {
  return switch (provider) {
    CalendarProviderType.calendly => Icons.calendar_month_outlined,
    CalendarProviderType.googleCalendar => Icons.event_available_outlined,
    CalendarProviderType.microsoftTeams => Icons.video_call_outlined,
    CalendarProviderType.custom => Icons.add_link_rounded,
  };
}

// ─── Forms Section ────────────────────────────────────────────────────────────

class _FormsSection extends StatefulWidget {
  final DigitalCardModel card;
  final Color accent;
  final Color textColor;
  const _FormsSection({
    required this.card,
    required this.accent,
    required this.textColor,
  });

  @override
  State<_FormsSection> createState() => _FormsSectionState();
}

class _FormsSectionState extends State<_FormsSection> {
  List<SmartFormModel> _forms = const [];
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadForms();
  }

  Future<void> _loadForms() async {
    try {
      final forms = await CardRepository.fetchSmartFormsForDisplay(
        cardId: widget.card.id,
        orgId: widget.card.orgId,
      );
      final activeForms = forms.where((f) => f.isActive).toList();
      if (!mounted) return;
      setState(() {
        _forms = activeForms.isNotEmpty ? activeForms : forms;
        _loading = false;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_loadFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Text(
              'No se pudieron cargar los formularios.',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                color: widget.textColor.withValues(alpha: 0.65),
              ),
            ),
          ),
        ),
      );
    }
    if (_forms.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Formulario de contacto',
          textColor: widget.textColor,
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final form in _forms)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _FormCard(
                        form: form,
                        card: widget.card,
                        accent: widget.accent,
                        textColor: widget.textColor,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FormCard extends StatefulWidget {
  final SmartFormModel form;
  final DigitalCardModel card;
  final Color accent;
  final Color textColor;
  const _FormCard({
    required this.form,
    required this.card,
    required this.accent,
    required this.textColor,
  });

  @override
  State<_FormCard> createState() => _FormCardState();
}

class _FormCardState extends State<_FormCard> {
  bool _expanded = false;
  bool _submitting = false;
  final Map<String, TextEditingController> _ctrl = {};

  @override
  void initState() {
    super.initState();
    for (final f in widget.form.fields) {
      _ctrl[f.id] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  SmartFormFieldModel? _referenceNameField(List<SmartFormFieldModel> fields) {
    for (final field in fields) {
      if (field.fieldType == SmartFormFieldType.text) {
        return field;
      }
    }

    for (final field in fields) {
      if (field.label.toLowerCase().contains('nombre')) {
        return field;
      }
    }

    return fields.isNotEmpty ? fields.first : null;
  }

  Future<void> _submit() async {
    final fields = widget.form.fields;
    // Validate required
    for (final f in fields) {
      if (f.isRequired && (_ctrl[f.id]?.text.trim().isEmpty ?? true)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Por favor completa: ${f.label}'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      final formData = {
        for (final f in fields) f.label: _ctrl[f.id]!.text.trim(),
      };
      final deviceId = await getStableVisitorId();
      if (deviceId != null && deviceId.isNotEmpty) {
        formData['_client_device_id'] = deviceId;
      }
      final nameField = _referenceNameField(fields);
      final name = nameField == null
          ? ''
          : (_ctrl[nameField.id]?.text.trim() ?? '');
      final email = fields
          .where(
            (f) =>
                f.fieldType == SmartFormFieldType.email ||
                f.label.toLowerCase().contains('correo'),
          )
          .map((f) => _ctrl[f.id]?.text.trim() ?? '')
          .where((v) => v.isNotEmpty)
          .firstOrNull;
      final phone = fields
          .where(
            (f) =>
                f.fieldType == SmartFormFieldType.phone ||
                f.label.toLowerCase().contains('tel') ||
                f.label.toLowerCase().contains('cel'),
          )
          .map((f) => _ctrl[f.id]?.text.trim() ?? '')
          .where((v) => v.isNotEmpty)
          .firstOrNull;
      final company = fields
          .where((f) => f.label.toLowerCase().contains('empresa'))
          .map((f) => _ctrl[f.id]?.text.trim() ?? '')
          .where((v) => v.isNotEmpty)
          .firstOrNull;

      await LeadRepository.submitFormLead(
        cardId: widget.card.id,
        formType: widget.form.id,
        name: name.isEmpty ? 'Anónimo' : name,
        email: email,
        phone: phone,
        company: company,
        formData: formData,
      );
      await AnalyticsRepository.recordInteraction(
        cardId: widget.card.id,
        source: 'form',
        smartFormId: widget.form.id,
      );
      if (mounted) {
        for (final controller in _ctrl.values) {
          controller.clear();
        }
        setState(() {
          _submitting = false;
          _expanded = false;
        });
        TapLoopToast.show(
          context,
          'Solicitud enviada satisfactoriamente.',
          TapLoopToastType.success,
        );
      }
    } catch (e) {
      debugPrint('[PublicCardView] submit form error: $e');
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar. Intenta de nuevo.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    const tileBorder = Color(0xFFE5E7EB);
    const tileBg = Colors.white;
    final surfaceTextColor = _contrastTextColor(tileBg);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: tileBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: tileBorder, width: 1.2),
              ),
              child: Row(
                children: [
                  Icon(Icons.dynamic_form_rounded, size: 24, color: accent),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      widget.form.name,
                      style: GoogleFonts.outfit(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: surfaceTextColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 24,
                    color: surfaceTextColor,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: _expanded
                ? Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                    decoration: BoxDecoration(
                      color: tileBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: tileBorder, width: 1.2),
                    ),
                    child: _FormBody(
                      fields: widget.form.fields,
                      ctrl: _ctrl,
                      accent: accent,
                      textColor: surfaceTextColor,
                      submitting: _submitting,
                      onSubmit: _submit,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _FormBody extends StatelessWidget {
  static const int _maxFieldLength = 200;
  final List<SmartFormFieldModel> fields;
  final Map<String, TextEditingController> ctrl;
  final Color accent;
  final Color textColor;
  final bool submitting;
  final VoidCallback onSubmit;
  const _FormBody({
    required this.fields,
    required this.ctrl,
    required this.accent,
    required this.textColor,
    required this.submitting,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    const borderCol = Color(0xFFE5E7EB);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in fields) ...[
          _buildField(f, borderCol, textColor),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 4),
        Material(
          color: accent,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: submitting ? null : onSubmit,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: Center(
                child: submitting
                    ? const TapLoopProgressIndicator(color: Colors.white)
                    : Text(
                        'Enviar',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildField(
    SmartFormFieldModel field,
    Color borderCol,
    Color textColor,
  ) {
    final label = field.label;
    final required = field.isRequired;
    final controller = ctrl[field.id]!;

    InputDecoration decoration = InputDecoration(
      labelText: required ? '$label *' : label,
      hintText: field.placeholder,
      counterText: '',
      labelStyle: GoogleFonts.dmSans(
        fontSize: 13,
        color: textColor.withValues(alpha: 0.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: borderCol),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: borderCol),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
      filled: false,
    );

    if (field.fieldType == SmartFormFieldType.textarea) {
      return TextField(
        controller: controller,
        maxLines: 3,
        keyboardType: TextInputType.multiline,
        inputFormatters: _inputFormattersForField(field.fieldType),
        maxLength: _maxFieldLength,
        style: GoogleFonts.dmSans(fontSize: 15, color: textColor),
        decoration: decoration,
      );
    }
    return TextField(
      controller: controller,
      maxLines: 1,
      keyboardType: _keyboardTypeForField(field.fieldType),
      inputFormatters: _inputFormattersForField(field.fieldType),
      maxLength: _maxFieldLength,
      style: GoogleFonts.dmSans(fontSize: 15, color: textColor),
      decoration: decoration,
    );
  }

  TextInputType _keyboardTypeForField(SmartFormFieldType fieldType) {
    switch (fieldType) {
      case SmartFormFieldType.phone:
        return TextInputType.phone;
      case SmartFormFieldType.email:
        return TextInputType.emailAddress;
      case SmartFormFieldType.number:
        return TextInputType.number;
      case SmartFormFieldType.textarea:
        return TextInputType.multiline;
      case SmartFormFieldType.text:
        return TextInputType.text;
    }
  }

  List<TextInputFormatter> _inputFormattersForField(
    SmartFormFieldType fieldType,
  ) {
    switch (fieldType) {
      case SmartFormFieldType.number:
        return [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(_maxFieldLength),
        ];
      case SmartFormFieldType.phone:
        return [
          FilteringTextInputFormatter.allow(RegExp(r"[0-9+\-\s().]")),
          LengthLimitingTextInputFormatter(_maxFieldLength),
        ];
      case SmartFormFieldType.email:
        return [
          FilteringTextInputFormatter.deny(RegExp(r"\s")),
          LengthLimitingTextInputFormatter(_maxFieldLength),
        ];
      case SmartFormFieldType.textarea:
        return [
          FilteringTextInputFormatter.allow(
            RegExp(r'[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ\s.,;:!¡?¿()#@&/_\-\n]'),
          ),
          LengthLimitingTextInputFormatter(_maxFieldLength),
        ];
      case SmartFormFieldType.text:
        return [
          FilteringTextInputFormatter.allow(
            RegExp(r'[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ\s.,;:!¡?¿()#@&/_\-]'),
          ),
          LengthLimitingTextInputFormatter(_maxFieldLength),
        ];
    }
  }
}

// ─── NFC Activation Page ──────────────────────────────────────────────────────

class _NfcActivationPage extends StatelessWidget {
  final String serial;
  final bool isLoggedIn;
  final bool activating;
  final String? error;
  final VoidCallback onActivate;
  final VoidCallback onLogin;

  const _NfcActivationPage({
    required this.serial,
    required this.isLoggedIn,
    required this.activating,
    required this.error,
    required this.onActivate,
    required this.onLogin,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final loggedIn = appState.isAuthenticated;
        final logoUrl = appState.currentCard?.companyLogoUrl;
        return Scaffold(
          backgroundColor: AppColors.surface,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 40,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (logoUrl != null && logoUrl.isNotEmpty) ...[
                        Image.network(
                          logoUrl,
                          height: 46,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 40),
                      ],
                      // NFC icon
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.nfc,
                          size: 48,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        loggedIn
                            ? 'Activa tu tarjeta digital'
                            : 'Esta tarjeta está lista para activarse',
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.black,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        loggedIn
                            ? 'Esta tarjeta NFC todavía no está vinculada a ninguna cuenta. ¿Deseas vincularla a tu cuenta?'
                            : 'Crea una cuenta o inicia sesión para vincular esta tarjeta NFC a tu perfil.',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          color: AppColors.grey,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            error!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                      const SizedBox(height: 36),
                      if (loggedIn) ...[
                        // ── Logged in: show "Link" button ──
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: activating ? null : onActivate,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                            child: activating
                                ? const TapLoopProgressIndicator(
                                    color: Colors.white,
                                  )
                                : Text(
                                    'Vincular con mi cuenta',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () => context.go('/'),
                          child: Text(
                            'Cancelar',
                            style: GoogleFonts.inter(
                              color: AppColors.grey,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ] else ...[
                        // ── Not logged in: show register/login CTAs ──
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: () => context.go('/?pendingNfc=$serial'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              'Ir a inicio',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton(
                            onPressed: onLogin,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(color: AppColors.primary),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              'Ya tengo cuenta',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                      // Serial chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.credit_card,
                              size: 14,
                              color: AppColors.grey,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              serial,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppColors.grey,
                                fontWeight: FontWeight.w500,
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
          ),
        );
      },
    );
  }
}

// ─── Load error (network/connectivity, not "card doesn't exist") ─────────────

class _LoadErrorPage extends StatelessWidget {
  final String? errorDetail;
  final VoidCallback onRetry;
  const _LoadErrorPage({required this.errorDetail, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.wifi_off_rounded,
                  size: 36,
                  color: AppColors.grey,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'No se pudo cargar el perfil',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Revisa tu conexión a internet e intenta de nuevo.',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.grey),
              ),
              if (errorDetail != null) ...[
                const SizedBox(height: 12),
                Text(
                  errorDetail!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: AppColors.error,
                  ),
                ),
              ],
              const SizedBox(height: 32),
              GestureDetector(
                onTap: onRetry,
                child: Text(
                  'Reintentar →',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Not Found ────────────────────────────────────────────────────────────────

class _NotFoundPage extends StatelessWidget {
  final String slug;
  final String? errorDetail;
  const _NotFoundPage({required this.slug, this.errorDetail});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_off_outlined,
                  size: 36,
                  color: AppColors.grey,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Tarjeta no encontrada',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'La tarjeta /$slug no existe o fue desactivada.',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.grey),
              ),
              if (errorDetail != null) ...[
                const SizedBox(height: 12),
                Text(
                  errorDetail!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: AppColors.error,
                  ),
                ),
              ],
              const SizedBox(height: 32),
              GestureDetector(
                onTap: () async {
                  final uri = Uri.parse('https://liomont.taploop.com.mx');
                  await _launchPublicUri(uri);
                },
                child: Text(
                  'Ir al inicio →',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
