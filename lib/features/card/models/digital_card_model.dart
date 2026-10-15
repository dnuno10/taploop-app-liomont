import 'package:flutter/material.dart';
import 'social_link_model.dart';
import 'contact_item_model.dart';
import 'smart_form_model.dart';

enum CardThemeStyle { white, black }

CardThemeStyle _themeStyleFromString(String s) {
  switch (s) {
    case 'black':
      return CardThemeStyle.black;
    default:
      return CardThemeStyle.white;
  }
}

enum CardLayoutStyle { centered, leftAligned, banner }

CardLayoutStyle _layoutStyleFromString(String s) {
  switch (s) {
    case 'leftAligned':
      return CardLayoutStyle.leftAligned;
    case 'banner':
      return CardLayoutStyle.banner;
    default:
      return CardLayoutStyle.centered;
  }
}

enum CardProfileDesign { classic, modern }

CardProfileDesign _profileDesignFromString(String s) {
  switch (s) {
    case 'modern':
      return CardProfileDesign.modern;
    default:
      return CardProfileDesign.classic;
  }
}

extension CardProfileDesignX on CardProfileDesign {
  CardLayoutStyle get compatibleLayoutStyle {
    return switch (this) {
      CardProfileDesign.classic => CardLayoutStyle.centered,
      CardProfileDesign.modern => CardLayoutStyle.banner,
    };
  }
}

enum CardBgStyle { plain, gradient, mesh, stripes }

CardBgStyle _bgStyleFromString(String s) {
  switch (s) {
    case 'gradient':
      return CardBgStyle.gradient;
    case 'mesh':
      return CardBgStyle.mesh;
    case 'stripes':
      return CardBgStyle.stripes;
    default:
      return CardBgStyle.plain;
  }
}

class DigitalCardModel {
  final String id;
  final String? userId;
  final String? orgId;
  // Profile
  final String name;
  final String jobTitle;
  final String company;
  final String? profilePhotoUrl;
  final String? companyLogoUrl;
  final String? bio;
  // Design
  final CardThemeStyle themeStyle;
  final Color primaryColor;
  final Color? backgroundColorStart;
  final Color? backgroundColorEnd;
  final CardLayoutStyle layoutStyle;
  final CardProfileDesign profileDesign;
  final Color iconColor;
  // Design
  final CardBgStyle bgStyle;
  final Color? bgColor;
  final Color? bgColorEnd;
  final bool showVerifiedBadge;

  bool get textColorIsDark => themeStyle == CardThemeStyle.black;
  bool get usesModernProfileDesign => profileDesign == CardProfileDesign.modern;
  // Forms & Calendar
  final List<String> enabledForms;
  final bool calendarEnabled;
  final String? calendarUrl;
  // Contact
  final List<ContactItemModel> contactItems;
  // Social
  final List<SocialLinkModel> socialLinks;
  // SmartForms (en memoria, no persisten en BD directamente en este model)
  final List<SmartFormModel> smartForms;
  // Meta
  final String publicSlug;
  final bool isActive;
  final DateTime? deactivatedAt;
  final String? deactivationReason;
  final String? deactivatedBy;
  final DateTime? updatedAt;

  const DigitalCardModel({
    required this.id,
    this.userId,
    this.orgId,
    required this.name,
    required this.jobTitle,
    required this.company,
    this.profilePhotoUrl,
    this.companyLogoUrl,
    this.bio,
    this.themeStyle = CardThemeStyle.black,
    this.primaryColor = const Color(0xFFEF6820),
    this.backgroundColorStart,
    this.backgroundColorEnd,
    this.layoutStyle = CardLayoutStyle.centered,
    this.profileDesign = CardProfileDesign.classic,
    this.iconColor = const Color(0xFFEF6820),
    this.bgStyle = CardBgStyle.plain,
    this.bgColor = Colors.white,
    this.bgColorEnd = Colors.white,
    this.showVerifiedBadge = false,
    this.enabledForms = const [],
    this.calendarEnabled = false,
    this.calendarUrl,
    required this.contactItems,
    required this.socialLinks,
    this.smartForms = const [],
    required this.publicSlug,
    this.isActive = true,
    this.deactivatedAt,
    this.deactivationReason,
    this.deactivatedBy,
    this.updatedAt,
  });

  factory DigitalCardModel.fromJson(
    Map<String, dynamic> json, {
    List<ContactItemModel> contactItems = const [],
    List<SocialLinkModel> socialLinks = const [],
    List<SmartFormModel> smartForms = const [],
  }) {
    final primaryColorVal = (json['primary_color'] as num?)?.toInt();
    final bgColorVal = (json['bg_color'] as num?)?.toInt();
    final bgColorEndVal = (json['bg_color_end'] as num?)?.toInt();
    final bgColorStartVal = (json['background_color_start'] as num?)?.toInt();
    final bgColorEndDbVal = (json['background_color_end'] as num?)?.toInt();
    final iconColorVal = (json['icon_color'] as num?)?.toInt();
    final layoutStyle = _layoutStyleFromString(
      json['layout_style'] as String? ?? 'centered',
    );
    final profileDesign = _profileDesignFromString(
      json['profile_design'] as String? ??
          (layoutStyle == CardLayoutStyle.banner ? 'modern' : 'classic'),
    );

    return DigitalCardModel(
      id: json['id'] as String,
      userId: json['user_id'] as String?,
      orgId: json['org_id'] as String?,
      name: json['name'] as String? ?? '',
      jobTitle: json['job_title'] as String? ?? '',
      company: json['company'] as String? ?? '',
      bio: json['bio'] as String?,
      publicSlug: json['public_slug'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? true,
      deactivatedAt: json['deactivated_at'] != null
          ? DateTime.tryParse(json['deactivated_at'] as String)
          : null,
      deactivationReason: json['deactivation_reason'] as String?,
      deactivatedBy: json['deactivated_by'] as String?,
      themeStyle: _themeStyleFromString(
        json['theme_style'] as String? ?? 'white',
      ),
      layoutStyle: layoutStyle,
      profileDesign: profileDesign,
      iconColor: Color(iconColorVal ?? primaryColorVal ?? 0xFFEF6820),
      primaryColor: Color(primaryColorVal ?? 0xFFEF6820),
      backgroundColorStart: bgColorStartVal != null
          ? Color(bgColorStartVal)
          : null,
      backgroundColorEnd: bgColorEndDbVal != null
          ? Color(bgColorEndDbVal)
          : null,
      bgStyle: _bgStyleFromString(json['bg_style'] as String? ?? 'plain'),
      bgColor: bgColorVal != null ? Color(bgColorVal) : null,
      bgColorEnd: bgColorEndVal != null ? Color(bgColorEndVal) : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      profilePhotoUrl: json['profile_photo_url'] as String?,
      companyLogoUrl: json['company_logo'] as String?,
      showVerifiedBadge: json['show_verified_badge'] as bool? ?? false,
      enabledForms: (json['enabled_forms'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(),
      calendarEnabled: json['calendar_enabled'] as bool? ?? false,
      calendarUrl: json['calendar_url'] as String?,
      contactItems: contactItems,
      socialLinks: socialLinks,
      smartForms: smartForms,
    );
  }

  /// Fields to upsert (excludes id, user_id, org_id — set those separately)
  Map<String, dynamic> toJson() => {
    'name': name,
    'job_title': jobTitle,
    'company': company,
    if (bio != null) 'bio': bio,
    'public_slug': publicSlug,
    'is_active': isActive,
    'deactivated_at': deactivatedAt?.toIso8601String(),
    'deactivation_reason': deactivationReason,
    'deactivated_by': deactivatedBy,
    'theme_style': themeStyle.name,
    'layout_style': profileDesign.compatibleLayoutStyle.name,
    'profile_design': profileDesign.name,
    'icon_color': iconColor.toARGB32(),
    'primary_color': primaryColor.toARGB32(),
    if (backgroundColorStart != null)
      'background_color_start': backgroundColorStart!.toARGB32(),
    if (backgroundColorEnd != null)
      'background_color_end': backgroundColorEnd!.toARGB32(),
    'bg_style': bgStyle.name,
    if (bgColor != null) 'bg_color': bgColor!.toARGB32(),
    if (bgColorEnd != null) 'bg_color_end': bgColorEnd!.toARGB32(),
    'enabled_forms': enabledForms,
    'calendar_enabled': calendarEnabled,
    'calendar_url': calendarUrl,
    if (profilePhotoUrl != null) 'profile_photo_url': profilePhotoUrl,
    'show_verified_badge': showVerifiedBadge,
  };

  String get publicUrl => 'https://liomont.taploop.com.mx/$publicSlug';

  DigitalCardModel copyWith({
    String? id,
    String? userId,
    String? orgId,
    String? name,
    String? jobTitle,
    String? company,
    String? profilePhotoUrl,
    String? companyLogoUrl,
    String? bio,
    CardThemeStyle? themeStyle,
    Color? primaryColor,
    Color? backgroundColorStart,
    Color? backgroundColorEnd,
    CardLayoutStyle? layoutStyle,
    CardProfileDesign? profileDesign,
    Color? iconColor,
    CardBgStyle? bgStyle,
    Color? bgColor,
    Color? bgColorEnd,
    bool? showVerifiedBadge,
    List<String>? enabledForms,
    bool? calendarEnabled,
    String? calendarUrl,
    List<ContactItemModel>? contactItems,
    List<SocialLinkModel>? socialLinks,
    List<SmartFormModel>? smartForms,
    String? publicSlug,
    bool? isActive,
    DateTime? deactivatedAt,
    String? deactivationReason,
    String? deactivatedBy,
    DateTime? updatedAt,
    // copyWith can't distinguish "not passed" from null, so removing the
    // photo needs an explicit flag.
    bool clearProfilePhoto = false,
  }) {
    return DigitalCardModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      orgId: orgId ?? this.orgId,
      name: name ?? this.name,
      jobTitle: jobTitle ?? this.jobTitle,
      company: company ?? this.company,
      profilePhotoUrl: clearProfilePhoto
          ? null
          : profilePhotoUrl ?? this.profilePhotoUrl,
      companyLogoUrl: companyLogoUrl ?? this.companyLogoUrl,
      bio: bio ?? this.bio,
      themeStyle: themeStyle ?? this.themeStyle,
      primaryColor: primaryColor ?? this.primaryColor,
      backgroundColorStart: backgroundColorStart ?? this.backgroundColorStart,
      backgroundColorEnd: backgroundColorEnd ?? this.backgroundColorEnd,
      layoutStyle: layoutStyle ?? this.layoutStyle,
      profileDesign: profileDesign ?? this.profileDesign,
      iconColor: iconColor ?? this.iconColor,
      bgStyle: bgStyle ?? this.bgStyle,
      bgColor: bgColor ?? this.bgColor,
      bgColorEnd: bgColorEnd ?? this.bgColorEnd,
      showVerifiedBadge: showVerifiedBadge ?? this.showVerifiedBadge,
      enabledForms: enabledForms ?? this.enabledForms,
      calendarEnabled: calendarEnabled ?? this.calendarEnabled,
      calendarUrl: calendarUrl ?? this.calendarUrl,
      contactItems: contactItems ?? this.contactItems,
      socialLinks: socialLinks ?? this.socialLinks,
      smartForms: smartForms ?? this.smartForms,
      publicSlug: publicSlug ?? this.publicSlug,
      isActive: isActive ?? this.isActive,
      deactivatedAt: deactivatedAt ?? this.deactivatedAt,
      deactivationReason: deactivationReason ?? this.deactivationReason,
      deactivatedBy: deactivatedBy ?? this.deactivatedBy,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
