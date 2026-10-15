import '../../services/supabase_service.dart';
import '../../../features/card/models/contact_item_model.dart';
import '../../../features/card/models/digital_card_model.dart';
import '../../../features/card/models/smart_form_model.dart';
import '../../../features/card/models/social_link_model.dart';

/// Routes reads/writes for cards of the OTHER linked org (Liomont ↔
/// Promofarma) through the `lp_admin_*` RPCs, because the shared database's
/// RLS only lets admins touch their own org.
///
/// Only cards explicitly registered via [registerCard] (done by the admin
/// view when opening a linked-org member) are routed here; every other card
/// keeps using the regular table queries in CardRepository unchanged.
class LinkedAdminGateway {
  LinkedAdminGateway._();

  static final _db = SupabaseService.client;

  static final Set<String> _cardIds = {};
  static final Set<String> _orgIds = {};
  // item id → card id (contact/social models don't carry their card id).
  static final Map<String, String> _contactCardIds = {};
  static final Map<String, String> _socialCardIds = {};
  static final Set<String> _formIds = {};

  static void registerCard(DigitalCardModel card, {String? orgId}) {
    if (card.id.isEmpty) return;
    _cardIds.add(card.id);
    final effectiveOrgId = (orgId ?? card.orgId)?.trim();
    if (effectiveOrgId != null && effectiveOrgId.isNotEmpty) {
      _orgIds.add(effectiveOrgId);
    }
    for (final item in card.contactItems) {
      _contactCardIds[item.id] = card.id;
    }
    for (final link in card.socialLinks) {
      _socialCardIds[link.id] = card.id;
    }
    _formIds.addAll(card.smartForms.map((f) => f.id));
  }

  static Future<bool>? _availability;

  /// Whether the `lp_admin_*` RPCs are installed and the current user may
  /// use them (admin of Liomont/Promofarma). Checked once per session.
  static Future<bool> isAvailable(String adminOrgId) {
    return _availability ??= () async {
      try {
        await _db.rpc('lp_admin_get_org', params: {'p_org_id': adminOrgId});
        return true;
      } catch (_) {
        _availability = null; // allow a retry later (e.g. SQL just installed)
        return false;
      }
    }();
  }

  static bool handlesCard(String? cardId) =>
      cardId != null && _cardIds.contains(cardId);
  static bool handlesOrg(String? orgId) =>
      orgId != null && _orgIds.contains(orgId);
  static String? contactCardId(String itemId) => _contactCardIds[itemId];
  static String? socialCardId(String linkId) => _socialCardIds[linkId];
  static bool handlesForm(String id) => _formIds.contains(id);

  // ─── Organization ─────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> fetchOrg(String orgId) async {
    final result = await _db.rpc(
      'lp_admin_get_org',
      params: {'p_org_id': orgId},
    );
    return result == null ? null : Map<String, dynamic>.from(result as Map);
  }

  // ─── Card ─────────────────────────────────────────────────────────────────

  static Future<void> updateCard(
    String cardId,
    Map<String, dynamic> payload,
  ) async {
    await _db.rpc(
      'lp_admin_update_card',
      params: {'p_card_id': cardId, 'p_payload': payload},
    );
  }

  // ─── Contact items ────────────────────────────────────────────────────────

  static Future<List<ContactItemModel>> upsertContactItems(
    String cardId,
    List<Map<String, dynamic>> items,
  ) async {
    final result = await _db.rpc(
      'lp_admin_upsert_contact_items',
      params: {'p_card_id': cardId, 'p_items': items},
    );
    final saved = (result as List)
        .cast<Map<String, dynamic>>()
        .map(ContactItemModel.fromJson)
        .toList();
    for (final item in saved) {
      _contactCardIds[item.id] = cardId;
    }
    return saved;
  }

  static Future<void> deleteContactItem(String itemId) async {
    await _db.rpc(
      'lp_admin_delete_contact_item',
      params: {'p_item_id': itemId},
    );
    _contactCardIds.remove(itemId);
  }

  // ─── Social links ─────────────────────────────────────────────────────────

  static Future<List<SocialLinkModel>> upsertSocialLinks(
    String cardId,
    List<Map<String, dynamic>> links,
  ) async {
    final result = await _db.rpc(
      'lp_admin_upsert_social_links',
      params: {'p_card_id': cardId, 'p_links': links},
    );
    final saved = (result as List)
        .cast<Map<String, dynamic>>()
        .map(SocialLinkModel.fromJson)
        .toList();
    for (final link in saved) {
      _socialCardIds[link.id] = cardId;
    }
    return saved;
  }

  static Future<void> deleteSocialLink(String linkId) async {
    await _db.rpc('lp_admin_delete_social_link', params: {'p_link_id': linkId});
    _socialCardIds.remove(linkId);
  }

  // ─── Smart forms ──────────────────────────────────────────────────────────

  static Future<List<SmartFormModel>> fetchSmartForms(String cardId) async {
    final result = await _db.rpc(
      'lp_admin_list_smart_forms',
      params: {'p_card_id': cardId},
    );
    final forms = (result as List)
        .cast<Map<String, dynamic>>()
        .map((row) => SmartFormModel.fromJson(row))
        .toList();
    _formIds.addAll(forms.map((f) => f.id));
    return forms;
  }

  static Future<SmartFormModel> upsertSmartForm(
    String cardId,
    Map<String, dynamic> form,
  ) async {
    final result = await _db.rpc(
      'lp_admin_upsert_smart_form',
      params: {'p_card_id': cardId, 'p_form': form},
    );
    final saved = SmartFormModel.fromJson(
      Map<String, dynamic>.from(result as Map),
    );
    _formIds.add(saved.id);
    return saved;
  }

  static Future<void> deleteSmartForm(String formId) async {
    await _db.rpc('lp_admin_delete_smart_form', params: {'p_form_id': formId});
    _formIds.remove(formId);
  }
}
