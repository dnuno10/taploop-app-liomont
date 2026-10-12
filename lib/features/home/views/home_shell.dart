import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/data/app_state.dart';
import '../../../core/data/repositories/card_repository.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/card_initial_setup_state.dart';
import '../../../core/widgets/taploop_loading_view.dart';
import '../../../core/widgets/taploop_logo.dart';
import '../../../core/widgets/taploop_motion.dart';
import '../../../core/widgets/taploop_progress_indicator.dart';
import '../../../core/widgets/taploop_toast.dart';
import '../../admin/views/admin_view.dart';
import '../../analytics/views/analytics_dashboard_view.dart';
import '../../analytics/views/lead_intelligence_view.dart';
import '../../analytics/views/team_performance_view.dart';
import '../../card/models/digital_card_model.dart';
import '../../card/views/edit_card_view.dart';
import '../../card/views/share_card_view.dart';
import 'dashboard_view.dart';
import 'settings_view.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  bool _creatingCard = false;
  bool _savingVerifiedBadge = false;
  bool _showProfileLoading = true;
  Timer? _profileLoadingTimer;

  @override
  void initState() {
    super.initState();
    _profileLoadingTimer = Timer(const Duration(milliseconds: 950), () {
      if (mounted) setState(() => _showProfileLoading = false);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadCardsIfMissing();
    });
  }

  @override
  void dispose() {
    _profileLoadingTimer?.cancel();
    super.dispose();
  }

  void _loadCardsIfMissing() async {
    final user = appState.currentUser;
    if (appState.loadingCard || user == null || appState.userCards.isNotEmpty) {
      return;
    }

    appState.setLoadingCard(true);
    try {
      final cards = await AuthService.fetchUserCards(user.id);
      if (mounted) appState.setCards(cards);
    } finally {
      if (mounted) appState.setLoadingCard(false);
    }
  }

  Future<void> _createCard() async {
    final user = appState.currentUser;
    if (user == null || _creatingCard) return;

    setState(() => _creatingCard = true);
    try {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: CardInitialSetupState(
              createNewCardOnLink: true,
              onLinked: () {
                if (Navigator.of(dialogContext).canPop()) {
                  Navigator.of(dialogContext).pop();
                }
                if (mounted) {
                  setState(() => _index = 1);
                }
              },
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo iniciar la vinculación de la tarjeta.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _creatingCard = false);
    }
  }

  // Index 6 (AdminView) is only kept for users with an admin-level role.
  // _navItems below must stay filtered in sync with this, index-for-index.
  static const int _adminViewIndex = 6;

  List<Widget> get _views {
    final views = [
      DashboardView(onNavigate: (i) => setState(() => _index = i)),
      const EditCardView(),
      const ShareCardView(),
      const AnalyticsDashboardView(),
      const LeadIntelligenceView(),
      const TeamPerformanceView(),
      const AdminView(),
      const SettingsView(),
    ];
    if (appState.currentUser?.isAdmin != true) {
      views.removeAt(_adminViewIndex);
    }
    return views;
  }

  Future<void> _setVerifiedBadge(bool value) async {
    final card = appState.currentCard;
    if (card == null || card.id.isEmpty || _savingVerifiedBadge) return;
    final previous = card.showVerifiedBadge;
    final updated = card.copyWith(showVerifiedBadge: value);

    setState(() => _savingVerifiedBadge = true);
    appState.updateCard(updated);
    try {
      await CardRepository.updateVerifiedBadge(
        cardId: card.id,
        showVerifiedBadge: value,
      );
    } catch (_) {
      appState.updateCard(card.copyWith(showVerifiedBadge: previous));
      if (mounted) {
        TapLoopToast.show(
          context,
          'No se pudo actualizar la marca de verificado.',
          TapLoopToastType.warning,
        );
      }
    } finally {
      if (mounted) setState(() => _savingVerifiedBadge = false);
    }
  }

  static List<_NavItem> get _navItems {
    final items = [
      const _NavItem(
        icon: Icons.home_rounded,
        activeIcon: Icons.home_rounded,
        label: 'Inicio',
      ),
      const _NavItem(
        icon: Icons.badge_outlined,
        activeIcon: Icons.badge_rounded,
        label: 'Perfil digital',
      ),
      const _NavItem(
        icon: Icons.share_outlined,
        activeIcon: Icons.share_rounded,
        label: 'Compartir',
      ),
      const _NavItem(
        icon: Icons.query_stats_outlined,
        activeIcon: Icons.query_stats_rounded,
        label: 'Analíticas',
      ),
      const _NavItem(
        icon: Icons.assignment_ind_outlined,
        activeIcon: Icons.assignment_ind_rounded,
        label: 'Leads',
      ),
      const _NavItem(
        icon: Icons.groups_outlined,
        activeIcon: Icons.groups_rounded,
        label: 'Equipo',
      ),
      const _NavItem(
        icon: Icons.admin_panel_settings_outlined,
        activeIcon: Icons.admin_panel_settings_rounded,
        label: 'Administración',
      ),
      const _NavItem(
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings_rounded,
        label: 'Configuración',
      ),
    ];
    if (appState.currentUser?.isAdmin != true) {
      items.removeAt(_adminViewIndex);
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final isDesktop = Responsive.isDesktop(context);
        final views = _views;
        // If the role changes (or on an edge-case first frame) and _index
        // still points at a tab that got filtered out, fall back to the
        // last valid tab instead of indexing out of range.
        final effectiveIndex = views.isEmpty
            ? 0
            : _index.clamp(0, views.length - 1);
        final loadingInitialCard =
            appState.loadingCard && appState.currentCard == null;

        if (_showProfileLoading || loadingInitialCard) {
          return const TapLoopLoadingView(scaffold: true);
        }

        if (isDesktop) {
          return _DesktopShell(
            index: effectiveIndex,
            views: views,
            cards: appState.userCards,
            currentCard: appState.currentCard,
            savingVerifiedBadge: _savingVerifiedBadge,
            onTap: (value) => setState(() => _index = value),
            onVerifiedChanged: _setVerifiedBadge,
          );
        }

        return _MobileShell(
          index: effectiveIndex,
          views: views,
          cards: appState.userCards,
          currentCard: appState.currentCard,
          creatingCard: _creatingCard,
          onTap: (value) => setState(() => _index = value),
          onSelectCard: appState.selectCardById,
          onCreateCard: _createCard,
        );
      },
    );
  }
}

class _DesktopShell extends StatelessWidget {
  final int index;
  final List<Widget> views;
  final List<DigitalCardModel> cards;
  final DigitalCardModel? currentCard;
  final bool savingVerifiedBadge;
  final ValueChanged<int> onTap;
  final ValueChanged<bool> onVerifiedChanged;

  const _DesktopShell({
    required this.index,
    required this.views,
    required this.cards,
    required this.currentCard,
    required this.savingVerifiedBadge,
    required this.onTap,
    required this.onVerifiedChanged,
  });

  @override
  Widget build(BuildContext context) {
    final user = appState.currentUser;
    final profilePhotoUrl =
        currentCard?.profilePhotoUrl?.trim().isNotEmpty == true
        ? currentCard!.profilePhotoUrl
        : user?.photoUrl;

    return Scaffold(
      backgroundColor: context.bgSubtle,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(
                width: 292,
                decoration: BoxDecoration(
                  color: context.bgCard,
                  borderRadius: BorderRadius.circular(4),
                  border: Border(
                    right: BorderSide(color: context.borderStrongSoft),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(28, 34, 28, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: TapLoopLogo(height: 36, showText: false),
                    ),
                    const SizedBox(height: 44),
                    if (cards.isNotEmpty) ...[
                      _CardWorkspaceSection(
                        cards: cards,
                        currentCard: currentCard,
                      ),
                    ],
                    const SizedBox(height: 34),
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          ..._HomeShellState._navItems.asMap().entries.map(
                            (entry) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _DesktopNavTile(
                                item: entry.value,
                                active: index == entry.key,
                                onTap: () => onTap(entry.key),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _SidebarAccountCard(
                      name: user?.name.isNotEmpty == true
                          ? user!.name
                          : 'Equipo TapLoop',
                      email: user?.email ?? '',
                      initials: user?.initials ?? 'TL',
                      photoUrl: profilePhotoUrl,
                    ),
                    const SizedBox(height: 18),
                    const _CorporateAccessBadge(),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: context.bgCard,
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(4),
                    ),
                    border: Border(
                      top: BorderSide(color: context.borderStrongSoft),
                      right: BorderSide(color: context.borderStrongSoft),
                      bottom: BorderSide(color: context.borderStrongSoft),
                    ),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: Column(
                    children: [
                      _DesktopTopBar(
                        currentCard: currentCard,
                        savingVerifiedBadge: savingVerifiedBadge,
                        onVerifiedChanged: onVerifiedChanged,
                      ),
                      Expanded(
                        child: TapLoopAnimatedIndexedStack(
                          index: index,
                          children: views,
                        ),
                      ),
                    ],
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

class _CorporateAccessBadge extends StatelessWidget {
  const _CorporateAccessBadge();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ACCESO CORPORATIVO',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w600,
            color: context.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Image.asset(
          'assets/images/liomont.png',
          height: 16,
          fit: BoxFit.contain,
        ),
      ],
    );
  }
}

class _DesktopTopBar extends StatelessWidget {
  final DigitalCardModel? currentCard;
  final bool savingVerifiedBadge;
  final ValueChanged<bool> onVerifiedChanged;

  const _DesktopTopBar({
    required this.currentCard,
    required this.savingVerifiedBadge,
    required this.onVerifiedChanged,
  });

  @override
  Widget build(BuildContext context) {
    final user = appState.currentUser;
    final title = currentCard != null
        ? _cardTitle(currentCard!, 0)
        : user?.name ?? 'TapLoop';
    final imageUrl = currentCard?.profilePhotoUrl?.trim().isNotEmpty == true
        ? currentCard!.profilePhotoUrl
        : user?.photoUrl;
    final incomplete = _isProfileIncomplete(currentCard);
    final verified = currentCard?.showVerifiedBadge ?? false;

    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 26),
      decoration: BoxDecoration(
        color: context.bgCard,
        border: Border(bottom: BorderSide(color: context.borderStrongSoft)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1000;
          final tight = constraints.maxWidth < 780;

          return Row(
            children: [
              SizedBox(
                width: compact ? 230 : 274,
                child: _TopProfileSummary(title: title),
              ),
              const Spacer(),
              if (!tight) ...[
                _TopStatusPill(
                  icon: incomplete
                      ? Icons.info_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  label: incomplete ? 'Perfil incompleto' : 'Perfil completo',
                  accent: incomplete
                      ? const Color(0xFF5B72FF)
                      : AppColors.success,
                ),
                const SizedBox(width: 10),
              ],
              if (!compact) ...[
                _VerifiedBadge(
                  verified: verified,
                  saving: savingVerifiedBadge,
                  onChanged: currentCard == null ? null : onVerifiedChanged,
                ),
                const SizedBox(width: 10),
                _TopCircleAction(
                  icon: Icons.notifications_none_rounded,
                  onTap: () {},
                ),
                const SizedBox(width: 10),
              ],
              _TopAvatar(
                imageUrl: imageUrl,
                initials: _profileInitials(title, user?.initials ?? 'TL'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TopProfileSummary extends StatelessWidget {
  final String title;

  const _TopProfileSummary({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.borderStrongSoft, width: 1.2),
      ),
      child: Row(
        children: [
          Icon(
            Icons.person_outline_rounded,
            size: 21,
            color: context.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Perfil seleccionado',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(
                    color: context.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: context.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
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

class _TopStatusPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;

  const _TopStatusPill({
    required this.icon,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.borderStrongSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 7),
          Text(
            label,
            style: GoogleFonts.dmSans(
              color: context.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  final bool verified;
  final bool saving;
  final ValueChanged<bool>? onChanged;

  const _VerifiedBadge({
    required this.verified,
    required this.saving,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFF2F5BFF);
    const inactiveColor = Color(0xFF94A3B8);
    final accent = verified ? activeColor : inactiveColor;
    final disabled = onChanged == null || saving;

    return Opacity(
      opacity: disabled && !saving ? 0.62 : 1,
      child: MouseRegion(
        cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: disabled ? null : () => onChanged!(!verified),
          child: Container(
            height: 46,
            padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
            decoration: BoxDecoration(
              color: context.bgCard,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: verified
                    ? activeColor.withValues(alpha: 0.25)
                    : context.borderStrongSoft,
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_rounded, size: 22, color: accent),
                const SizedBox(width: 8),
                Text(
                  verified ? 'Verificado' : 'Sin verificar',
                  style: GoogleFonts.dmSans(
                    color: verified ? context.textPrimary : context.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 10),
                IgnorePointer(
                  child: Transform.scale(
                    scale: 0.82,
                    child: Switch.adaptive(
                      value: verified,
                      onChanged: disabled ? null : onChanged,
                      activeTrackColor: activeColor.withValues(alpha: 0.26),
                      activeThumbColor: activeColor,
                      inactiveTrackColor: inactiveColor.withValues(alpha: 0.22),
                      inactiveThumbColor: inactiveColor,
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

class _TopCircleAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _TopCircleAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TapLoopPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      hoverColor: TapLoopMotion.hoverSurfaceColor(context),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: context.bgCard,
          shape: BoxShape.circle,
          border: Border.all(color: context.borderStrongSoft, width: 1.2),
        ),
        child: Icon(icon, size: 22, color: context.textPrimary),
      ),
    );
  }
}

class _TopAvatar extends StatelessWidget {
  final String? imageUrl;
  final String initials;

  const _TopAvatar({required this.imageUrl, required this.initials});

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    final hasImage = url != null && url.isNotEmpty;

    return SizedBox(
      width: 44,
      height: 44,
      child: hasImage
          ? ClipOval(child: Image.network(url, fit: BoxFit.cover))
          : Center(
              child: Text(
                initials,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: context.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
    );
  }
}

class _MobileShell extends StatelessWidget {
  final int index;
  final List<Widget> views;
  final List<DigitalCardModel> cards;
  final DigitalCardModel? currentCard;
  final bool creatingCard;
  final ValueChanged<int> onTap;
  final ValueChanged<String> onSelectCard;
  final Future<void> Function() onCreateCard;

  const _MobileShell({
    required this.index,
    required this.views,
    required this.cards,
    required this.currentCard,
    required this.creatingCard,
    required this.onTap,
    required this.onSelectCard,
    required this.onCreateCard,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgSubtle,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Container(
            decoration: BoxDecoration(
              color: context.bgCard,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border.all(color: context.borderStrongSoft, width: 1.5),
            ),
            clipBehavior: Clip.hardEdge,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 2),
                  child: Row(
                    children: [
                      Text(
                        'ACCESO CORPORATIVO',
                        style: TextStyle(
                          fontSize: 9,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                          color: context.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Image.asset(
                        'assets/images/liomont.png',
                        height: 12,
                        fit: BoxFit.contain,
                      ),
                    ],
                  ),
                ),
                if (cards.isNotEmpty)
                  _MobileCardToolbar(
                    cards: cards,
                    currentCard: currentCard,
                    creatingCard: creatingCard,
                    onSelectCard: onSelectCard,
                    onCreateCard: onCreateCard,
                  ),
                Expanded(
                  child: TapLoopAnimatedIndexedStack(
                    index: index,
                    children: views,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: _MobileNavBar(index: index, onTap: onTap),
      ),
    );
  }
}

class _MobileNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;

  const _MobileNavBar({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 66,
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.borderStrongSoft, width: 1.4),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _HomeShellState._navItems.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final item = _HomeShellState._navItems[i];
          return _MobileNavChip(
            item: item,
            active: index == i,
            onTap: () => onTap(i),
          );
        },
      ),
    );
  }
}

class _MobileNavChip extends StatefulWidget {
  final _NavItem item;
  final bool active;
  final VoidCallback onTap;

  const _MobileNavChip({
    required this.item,
    required this.active,
    required this.onTap,
  });

  @override
  State<_MobileNavChip> createState() => _MobileNavChipState();
}

class _MobileNavChipState extends State<_MobileNavChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final foreground = active ? AppColors.primary : context.textSecondary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: TapLoopMotion.fast,
        curve: TapLoopMotion.standard,
        child: AnimatedContainer(
          duration: TapLoopMotion.fast,
          curve: TapLoopMotion.standard,
          constraints: const BoxConstraints(minWidth: 54),
          padding: EdgeInsets.symmetric(
            horizontal: active ? 14 : 12,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: active
                ? AppColors.primary.withValues(alpha: 0.07)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: TapLoopMotion.fast,
                child: Icon(
                  active ? widget.item.activeIcon : widget.item.icon,
                  key: ValueKey(active),
                  size: 19,
                  color: foreground,
                ),
              ),
              AnimatedSize(
                duration: TapLoopMotion.fast,
                curve: TapLoopMotion.standard,
                child: active
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 96),
                            child: Text(
                              widget.item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.dmSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: foreground,
                              ),
                            ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardWorkspaceSection extends StatelessWidget {
  final List<DigitalCardModel> cards;
  final DigitalCardModel? currentCard;

  const _CardWorkspaceSection({required this.cards, required this.currentCard});

  @override
  Widget build(BuildContext context) {
    final selectedCard = currentCard ?? cards.first;

    return _SelectedCardSummary(card: selectedCard);
  }
}

class _MobileCardToolbar extends StatelessWidget {
  final List<DigitalCardModel> cards;
  final DigitalCardModel? currentCard;
  final bool creatingCard;
  final ValueChanged<String> onSelectCard;
  final Future<void> Function() onCreateCard;

  const _MobileCardToolbar({
    required this.cards,
    required this.currentCard,
    required this.creatingCard,
    required this.onSelectCard,
    required this.onCreateCard,
  });

  @override
  Widget build(BuildContext context) {
    final selectedCard = currentCard ?? cards.first;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: context.bgCard,
        border: Border(bottom: BorderSide(color: context.borderStrongSoft)),
      ),
      child: Row(
        children: [
          Expanded(
            child: cards.length > 1
                ? _CardDropdown(
                    cards: cards,
                    currentCard: selectedCard,
                    onSelectCard: onSelectCard,
                    compact: true,
                    onCreateCard: onCreateCard,
                    onOpenDigitalProfile: () {},
                  )
                : _SelectedCardSummary(card: selectedCard, compact: true),
          ),
          const SizedBox(width: 10),
          IconButton.filled(
            onPressed: creatingCard ? null : onCreateCard,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
            ),
            icon: creatingCard
                ? const TapLoopProgressIndicator(color: Colors.white)
                : const Icon(Icons.add_card_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _CardDropdown extends StatelessWidget {
  final List<DigitalCardModel> cards;
  final DigitalCardModel currentCard;
  final ValueChanged<String> onSelectCard;
  final Future<void> Function() onCreateCard;
  final VoidCallback onOpenDigitalProfile;
  final bool compact;

  const _CardDropdown({
    required this.cards,
    required this.currentCard,
    required this.onSelectCard,
    required this.onCreateCard,
    required this.onOpenDigitalProfile,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return _StyledPopupMenu<String>(
      onSelected: (value) {
        if (value == '__new_profile' || value == '__link_card') {
          onCreateCard();
          return;
        }
        if (value == '__digital_profile') {
          onOpenDigitalProfile();
          return;
        }
        onSelectCard(value);
      },
      items: [
        ...cards.map(
          (card) => _StyledPopupEntry<String>(
            value: card.id,
            icon: Icons.person_outline_rounded,
            label: _cardTitle(card, cards.indexOf(card)),
            trailing: card.id == currentCard.id
                ? const Icon(Icons.check_rounded, size: 18)
                : null,
          ),
        ),
        const _StyledPopupEntry<String>.divider(),
        const _StyledPopupEntry<String>(
          value: '__new_profile',
          icon: Icons.person_add_alt_1_rounded,
          label: 'Nuevo perfil',
          trailing: Icon(Icons.workspace_premium_rounded, size: 18),
        ),
        const _StyledPopupEntry<String>(
          value: '__link_card',
          icon: Icons.add_card_rounded,
          label: 'Vincular tarjeta',
        ),
        const _StyledPopupEntry<String>(
          value: '__digital_profile',
          icon: Icons.person_outline_rounded,
          label: 'Perfil digital',
        ),
      ],
      child: _ProfileSelectorShell(
        compact: compact,
        child: Row(
          children: [
            Expanded(
              child: Text(
                _cardTitle(currentCard, 0),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedCardSummary extends StatelessWidget {
  final DigitalCardModel card;
  final bool compact;

  const _SelectedCardSummary({required this.card, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return _ProfileSelectorShell(
      compact: compact,
      child: Row(
        children: [
          Expanded(
            child: Text(
              _cardTitle(card, 0),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSelectorShell extends StatelessWidget {
  final Widget child;
  final bool compact;

  const _ProfileSelectorShell({required this.child, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        20,
        compact ? 10 : 14,
        16,
        compact ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(compact ? 18 : 20),
        border: Border.all(color: context.borderStrongSoft, width: 1.1),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: DefaultTextStyle(
              style: GoogleFonts.outfit(
                color: context.textPrimary,
                fontSize: compact ? 15 : 16,
                fontWeight: FontWeight.w800,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!compact) ...[
                    Text(
                      'Perfil activo',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                        color: context.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  child,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StyledPopupEntry<T> {
  final T? value;
  final IconData? icon;
  final String label;
  final Widget? trailing;
  final bool divider;

  const _StyledPopupEntry({
    required T this.value,
    required IconData this.icon,
    required this.label,
    this.trailing,
  }) : divider = false;

  const _StyledPopupEntry.divider()
    : value = null,
      icon = null,
      label = '',
      trailing = null,
      divider = true;
}

class _StyledPopupMenu<T> extends StatefulWidget {
  final Widget child;
  final List<_StyledPopupEntry<T>> items;
  final ValueChanged<T> onSelected;
  final double menuWidth;

  const _StyledPopupMenu({
    required this.child,
    required this.items,
    required this.onSelected,
    this.menuWidth = 220,
  });

  @override
  State<_StyledPopupMenu<T>> createState() => _StyledPopupMenuState<T>();
}

class _StyledPopupMenuState<T> extends State<_StyledPopupMenu<T>> {
  final _anchorKey = GlobalKey();
  bool _hovered = false;
  bool _pressed = false;

  Future<void> _show() async {
    final anchorContext = _anchorKey.currentContext;
    final overlay = Navigator.of(context).overlay?.context.findRenderObject();
    final renderObject = anchorContext?.findRenderObject();
    if (anchorContext == null ||
        overlay is! RenderBox ||
        renderObject is! RenderBox) {
      return;
    }

    final anchorOffset = renderObject.localToGlobal(
      Offset.zero,
      ancestor: overlay,
    );
    final anchorSize = renderObject.size;
    final dividerCount = widget.items.where((item) => item.divider).length;
    final optionCount = widget.items.length - dividerCount;
    final estimatedHeight = (optionCount * 48.0) + (dividerCount * 8.0) + 12;
    final below = overlay.size.height - anchorOffset.dy - anchorSize.height;
    final above = anchorOffset.dy;
    final openBelow = below >= estimatedHeight || below >= above;
    final left = anchorOffset.dx
        .clamp(8.0, math.max(8.0, overlay.size.width - widget.menuWidth - 8))
        .toDouble();
    final top = openBelow
        ? anchorOffset.dy + anchorSize.height + 8
        : math.max(8.0, anchorOffset.dy - estimatedHeight - 8);

    final selected = await showMenu<T>(
      context: context,
      position: RelativeRect.fromLTRB(
        left,
        top,
        overlay.size.width - left - widget.menuWidth,
        overlay.size.height - top,
      ),
      color: context.bgCard,
      surfaceTintColor: Colors.transparent,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      constraints: BoxConstraints(
        minWidth: widget.menuWidth,
        maxWidth: widget.menuWidth,
      ),
      items: widget.items.map<PopupMenuEntry<T>>((item) {
        if (item.divider) {
          return const PopupMenuDivider(height: 8);
        }

        return PopupMenuItem<T>(
          value: item.value as T,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Icon(item.icon, size: 20, color: context.textPrimary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  item.label,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(
                    color: context.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (item.trailing != null) ...[
                const SizedBox(width: 10),
                IconTheme(
                  data: IconThemeData(color: context.textMuted, size: 18),
                  child: item.trailing!,
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );

    if (selected != null && mounted) {
      widget.onSelected(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      key: _anchorKey,
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) {
        setState(() {
          _hovered = false;
          _pressed = false;
        });
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _show,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed
              ? 0.992
              : _hovered
              ? 1.004
              : 1,
          duration: TapLoopMotion.fast,
          curve: TapLoopMotion.standard,
          child: widget.child,
        ),
      ),
    );
  }
}

class _DesktopNavTile extends StatefulWidget {
  final _NavItem item;
  final bool active;
  final VoidCallback onTap;

  const _DesktopNavTile({
    required this.item,
    required this.active,
    required this.onTap,
  });

  @override
  State<_DesktopNavTile> createState() => _DesktopNavTileState();
}

class _DesktopNavTileState extends State<_DesktopNavTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.active;
    final foreground = selected ? AppColors.primary : context.textSecondary;
    final hoverColor = TapLoopMotion.hoverSurfaceColor(context);
    final idleColor = context.bgCard;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: TapLoopMotion.fast,
          curve: TapLoopMotion.standard,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.06)
                : _hovered
                ? hoverColor
                : idleColor,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.fromLTRB(20, 11, 20, 11),
          child: Row(
            children: [
              AnimatedSwitcher(
                duration: TapLoopMotion.fast,
                switchInCurve: TapLoopMotion.entrance,
                switchOutCurve: TapLoopMotion.exit,
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  selected ? widget.item.activeIcon : widget.item.icon,
                  key: ValueKey(selected),
                  size: 20,
                  color: foreground,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: AnimatedDefaultTextStyle(
                  duration: TapLoopMotion.fast,
                  curve: TapLoopMotion.standard,
                  style: GoogleFonts.dmSans(
                    color: foreground,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                  ),
                  child: Text(widget.item.label),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarAccountCard extends StatelessWidget {
  final String name;
  final String email;
  final String initials;
  final String? photoUrl;

  const _SidebarAccountCard({
    required this.name,
    required this.email,
    required this.initials,
    required this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final displayedInitials = initials.length > 2
        ? initials.substring(0, 2)
        : initials;
    final imageUrl = photoUrl?.trim();
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderStrongSoft, width: 1.1),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              image: hasImage
                  ? DecorationImage(
                      image: NetworkImage(imageUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: hasImage
                ? null
                : Text(
                    displayedInitials,
                    style: GoogleFonts.outfit(
                      color: AppColors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: context.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(
                    color: context.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _StyledPopupMenu<String>(
            menuWidth: 176,
            onSelected: (value) async {
              if (value != 'logout') return;
              await AuthService.signOut();
              appState.clear();
            },
            items: const [
              _StyledPopupEntry<String>(
                value: 'logout',
                icon: Icons.logout_rounded,
                label: 'Cerrar sesión',
              ),
            ],
            child: Icon(
              Icons.more_vert_rounded,
              color: context.textSecondary,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

String _cardTitle(DigitalCardModel card, int index) {
  final name = card.name.trim();
  if (name.isNotEmpty) return name;
  return 'Tarjeta ${index + 1}';
}

bool _isProfileIncomplete(DigitalCardModel? card) {
  if (card == null) return true;
  return card.name.trim().isEmpty ||
      card.jobTitle.trim().isEmpty ||
      card.company.trim().isEmpty ||
      card.publicSlug.trim().isEmpty ||
      card.contactItems.isEmpty;
}

String _profileInitials(String title, String fallback) {
  final source = title.trim().isNotEmpty ? title.trim() : fallback.trim();
  if (source.isEmpty) return 'TL';
  final parts = source.split(RegExp(r'\s+'));
  if (parts.length >= 2) {
    return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
  }
  return source[0].toUpperCase();
}
