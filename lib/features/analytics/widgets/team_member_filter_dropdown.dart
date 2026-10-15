import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/utils/search_text.dart';
import '../models/team_member_model.dart';

/// Capsule that opens a searchable member picker ("Todos" + every member).
///
/// The list is filtered as you type and built lazily, so it stays fluid
/// even with hundreds of profiles.
class TeamMemberFilterDropdown extends StatelessWidget {
  final List<TeamMemberModel> members;
  final String? selectedMemberId;
  final ValueChanged<String?> onChanged;
  final String allLabel;

  const TeamMemberFilterDropdown({
    super.key,
    required this.members,
    required this.selectedMemberId,
    required this.onChanged,
    this.allLabel = 'Todos',
  });

  static const _panelWidth = 340.0;
  static const _panelMaxHeight = 440.0;

  Future<void> _open(BuildContext context) async {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    const allSentinel = _AllMembersSelection();
    Object? result;

    if (narrow) {
      result = await showModalBottomSheet<Object>(
        context: context,
        isScrollControlled: true,
        backgroundColor: context.bgCard,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.7,
            child: _MemberPickerPanel(
              members: members,
              selectedMemberId: selectedMemberId,
              allLabel: allLabel,
              allSentinel: allSentinel,
            ),
          ),
        ),
      );
    } else {
      final box = context.findRenderObject() as RenderBox?;
      final overlay =
          Overlay.of(context).context.findRenderObject() as RenderBox?;
      if (box == null || overlay == null) return;
      final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
      final screen = overlay.size;
      final left = (origin.dx + box.size.width - _panelWidth).clamp(
        12.0,
        screen.width - _panelWidth - 12,
      );
      final top = origin.dy + box.size.height + 8;
      final maxHeight = (screen.height - top - 16).clamp(
        200.0,
        _panelMaxHeight,
      );

      result = await showDialog<Object>(
        context: context,
        barrierColor: Colors.transparent,
        builder: (dialogContext) => Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: _panelWidth,
              child: Material(
                color: dialogContext.bgCard,
                elevation: 10,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  height: maxHeight,
                  child: _MemberPickerPanel(
                    members: members,
                    selectedMemberId: selectedMemberId,
                    allLabel: allLabel,
                    allSentinel: allSentinel,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (result == null) return; // dismissed
    final next = result is String ? result : null;
    if (next != selectedMemberId) onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final selectedMember = selectedMemberId == null
        ? null
        : members.cast<TeamMemberModel?>().firstWhere(
            (member) => member?.id == selectedMemberId,
            orElse: () => null,
          );
    final label = selectedMember?.name.trim().isNotEmpty == true
        ? selectedMember!.name
        : allLabel;

    return Tooltip(
      message: 'Buscar y filtrar por miembro',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => _open(context),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: context.bgCard,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: context.borderStrongSoft, width: 1.1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: context.textSecondary,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: context.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Result used for the "Todos" option (a `null` result means dismissed).
class _AllMembersSelection {
  const _AllMembersSelection();
}

class _MemberPickerPanel extends StatefulWidget {
  final List<TeamMemberModel> members;
  final String? selectedMemberId;
  final String allLabel;
  final _AllMembersSelection allSentinel;

  const _MemberPickerPanel({
    required this.members,
    required this.selectedMemberId,
    required this.allLabel,
    required this.allSentinel,
  });

  @override
  State<_MemberPickerPanel> createState() => _MemberPickerPanelState();
}

class _MemberPickerPanelState extends State<_MemberPickerPanel> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  late final List<({TeamMemberModel member, String key})> _indexed;
  late List<TeamMemberModel> _results;
  String _query = '';

  @override
  void initState() {
    super.initState();
    final sorted = [...widget.members]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _indexed = [
      for (final member in sorted)
        (
          member: member,
          key: normalizeSearchText('${member.name} ${member.email}'),
        ),
    ];
    _results = sorted;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      final query = normalizeSearchText(value);
      setState(() {
        _query = query;
        _results = [
          for (final entry in _indexed)
            if (query.isEmpty || entry.key.contains(query)) entry.member,
        ];
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final showAll = _query.isEmpty;
    final itemCount = _results.length + (showAll ? 1 : 0);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            controller: _controller,
            autofocus: true,
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Buscar perfil por nombre o correo',
              hintStyle: GoogleFonts.dmSans(
                fontSize: 14,
                color: context.textMuted,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 20,
                color: context.textSecondary,
              ),
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) => value.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        tooltip: 'Limpiar',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _controller.clear();
                          _onChanged('');
                        },
                      ),
              ),
              filled: true,
              fillColor: context.bgSubtle,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: context.borderStrongSoft),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: context.borderStrongSoft),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
          ),
        ),
        Divider(height: 1, color: context.borderStrongSoft),
        Expanded(
          child: itemCount == 0
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'Sin resultados',
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: context.textSecondary,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: itemCount,
                  itemExtent: 46,
                  itemBuilder: (context, index) {
                    if (showAll && index == 0) {
                      return _PickerItem(
                        label: widget.allLabel,
                        selected: widget.selectedMemberId == null,
                        onTap: () =>
                            Navigator.of(context).pop(widget.allSentinel),
                      );
                    }
                    final member = _results[index - (showAll ? 1 : 0)];
                    return _PickerItem(
                      label: member.name.trim().isNotEmpty
                          ? member.name
                          : 'Miembro sin nombre',
                      selected: widget.selectedMemberId == member.id,
                      onTap: () => Navigator.of(context).pop(member.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PickerItem extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PickerItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 18,
              color: selected ? AppColors.primary : context.textMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
