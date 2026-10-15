-- Edicion cruzada de perfiles LIOMONT <-> PROMOFARMA desde la seccion de
-- Administracion de liomont.taploop.com.mx.
--
-- NO modifica politicas RLS, tablas ni funciones existentes. Solo crea
-- funciones NUEVAS (prefijo lp_admin_) que unicamente llama la app de Liomont,
-- cuando un admin edita un perfil de la OTRA organizacion vinculada.
-- app.taploop.com.mx y el resto de organizaciones no se ven afectados.
--
-- Cada funcion valida que:
--   1. quien llama sea admin/owner/super_admin de LIOMONT o PROMOFARMA, y
--   2. la tarjeta/registro pertenezca a LIOMONT o PROMOFARMA.
-- Si no se cumple, lanza 'lp_admin_not_allowed' y no escribe nada.
--
-- Requiere haber ejecutado antes add_liomont_promofarma_directory_rpc.sql.
-- Ejecutar completo en Supabase SQL Editor.

-- ─── Helpers ─────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.lp_admin_is_linked_org(p_org_id uuid)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_org_id IS NOT NULL AND p_org_id IN (
    '293f05a3-9115-4b72-a4ac-2c4d3a8af83e'::uuid, -- LIOMONT
    '4a7357d3-5222-4555-aaa9-f5cbe7b1d81d'::uuid  -- PROMOFARMA
  );
$$;

CREATE OR REPLACE FUNCTION public.lp_admin_caller_allowed()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = auth.uid()
      AND lower(u.role) IN ('admin', 'owner', 'super_admin')
      AND public.lp_admin_is_linked_org(u.org_id)
  );
$$;

CREATE OR REPLACE FUNCTION public.lp_admin_assert_card(p_card_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.lp_admin_caller_allowed() OR NOT EXISTS (
    SELECT 1
    FROM public.digital_cards dc
    LEFT JOIN public.users owner ON owner.id = dc.user_id
    WHERE dc.id = p_card_id
      AND (
        public.lp_admin_is_linked_org(dc.org_id)
        OR public.lp_admin_is_linked_org(owner.org_id)
      )
  ) THEN
    RAISE EXCEPTION 'lp_admin_not_allowed' USING ERRCODE = '42501';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.lp_admin_caller_allowed() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lp_admin_assert_card(uuid) FROM PUBLIC;

-- ─── Organizacion (nombre + configuracion compartida) ───────────────────────

CREATE OR REPLACE FUNCTION public.lp_admin_get_org(p_org_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result jsonb;
BEGIN
  IF NOT public.lp_admin_caller_allowed()
     OR NOT public.lp_admin_is_linked_org(p_org_id) THEN
    RAISE EXCEPTION 'lp_admin_not_allowed' USING ERRCODE = '42501';
  END IF;

  SELECT jsonb_build_object(
    'id', o.id,
    'name', o.name,
    'company_logo', o.company_logo,
    'shared_design_enabled', o.shared_design_enabled,
    'shared_forms_enabled', o.shared_forms_enabled,
    'shared_integrations_enabled', o.shared_integrations_enabled,
    'shared_links_enabled', o.shared_links_enabled,
    'shared_template_card_id', o.shared_template_card_id
  )
  INTO result
  FROM public.organizations o
  WHERE o.id = p_org_id;

  RETURN result;
END;
$$;

-- ─── Tarjeta: datos, foto, diseno, integraciones ────────────────────────────
-- Solo actualiza las columnas presentes en p_payload. Nunca cambia id,
-- user_id, org_id ni created_at.

CREATE OR REPLACE FUNCTION public.lp_admin_update_card(
  p_card_id uuid,
  p_payload jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r public.digital_cards;
  updated public.digital_cards;
BEGIN
  PERFORM public.lp_admin_assert_card(p_card_id);

  IF p_payload ? 'public_slug' AND EXISTS (
    SELECT 1 FROM public.digital_cards
    WHERE public_slug = p_payload->>'public_slug' AND id <> p_card_id
  ) THEN
    RAISE EXCEPTION 'lp_admin_slug_taken' USING ERRCODE = '23505';
  END IF;

  r := jsonb_populate_record(NULL::public.digital_cards, p_payload);

  UPDATE public.digital_cards d SET
    name = CASE WHEN p_payload ? 'name' THEN r.name ELSE d.name END,
    job_title = CASE WHEN p_payload ? 'job_title' THEN r.job_title ELSE d.job_title END,
    company = CASE WHEN p_payload ? 'company' THEN r.company ELSE d.company END,
    bio = CASE WHEN p_payload ? 'bio' THEN r.bio ELSE d.bio END,
    public_slug = CASE WHEN p_payload ? 'public_slug' THEN r.public_slug ELSE d.public_slug END,
    is_active = CASE WHEN p_payload ? 'is_active' THEN coalesce(r.is_active, d.is_active) ELSE d.is_active END,
    theme_style = CASE WHEN p_payload ? 'theme_style' THEN r.theme_style ELSE d.theme_style END,
    layout_style = CASE WHEN p_payload ? 'layout_style' THEN r.layout_style ELSE d.layout_style END,
    primary_color = CASE WHEN p_payload ? 'primary_color' THEN r.primary_color ELSE d.primary_color END,
    background_color_start = CASE WHEN p_payload ? 'background_color_start' THEN r.background_color_start ELSE d.background_color_start END,
    background_color_end = CASE WHEN p_payload ? 'background_color_end' THEN r.background_color_end ELSE d.background_color_end END,
    bg_style = CASE WHEN p_payload ? 'bg_style' THEN r.bg_style ELSE d.bg_style END,
    bg_color = CASE WHEN p_payload ? 'bg_color' THEN r.bg_color ELSE d.bg_color END,
    bg_color_end = CASE WHEN p_payload ? 'bg_color_end' THEN r.bg_color_end ELSE d.bg_color_end END,
    profile_photo_url = CASE WHEN p_payload ? 'profile_photo_url' THEN r.profile_photo_url ELSE d.profile_photo_url END,
    enabled_forms = CASE WHEN p_payload ? 'enabled_forms' THEN r.enabled_forms ELSE d.enabled_forms END,
    calendar_enabled = CASE WHEN p_payload ? 'calendar_enabled' THEN r.calendar_enabled ELSE d.calendar_enabled END,
    calendar_url = CASE WHEN p_payload ? 'calendar_url' THEN r.calendar_url ELSE d.calendar_url END,
    deactivated_at = CASE WHEN p_payload ? 'deactivated_at' THEN r.deactivated_at ELSE d.deactivated_at END,
    deactivation_reason = CASE WHEN p_payload ? 'deactivation_reason' THEN r.deactivation_reason ELSE d.deactivation_reason END,
    deactivated_by = CASE WHEN p_payload ? 'deactivated_by' THEN r.deactivated_by ELSE d.deactivated_by END,
    show_verified_badge = CASE WHEN p_payload ? 'show_verified_badge' THEN coalesce(r.show_verified_badge, d.show_verified_badge) ELSE d.show_verified_badge END,
    profile_design = CASE WHEN p_payload ? 'profile_design' THEN coalesce(r.profile_design, d.profile_design) ELSE d.profile_design END,
    icon_color = CASE WHEN p_payload ? 'icon_color' THEN r.icon_color ELSE d.icon_color END
  WHERE d.id = p_card_id
  RETURNING d.* INTO updated;

  RETURN to_jsonb(updated);
END;
$$;

-- ─── Contactos ───────────────────────────────────────────────────────────────
-- p_items: arreglo JSON. Con "id" existente de la tarjeta => actualiza;
-- sin "id" => inserta (sort_order al final si no viene).

CREATE OR REPLACE FUNCTION public.lp_admin_upsert_contact_items(
  p_card_id uuid,
  p_items jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  item jsonb;
  r public.contact_items;
  saved public.contact_items;
  item_id uuid;
  result jsonb := '[]'::jsonb;
BEGIN
  PERFORM public.lp_admin_assert_card(p_card_id);

  FOR item IN SELECT * FROM jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  LOOP
    r := jsonb_populate_record(NULL::public.contact_items, item);
    item_id := nullif(item->>'id', '')::uuid;

    IF item_id IS NOT NULL THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.contact_items
        WHERE id = item_id AND card_id = p_card_id
      ) THEN
        RAISE EXCEPTION 'lp_admin_not_allowed' USING ERRCODE = '42501';
      END IF;

      UPDATE public.contact_items c SET
        type = CASE WHEN item ? 'type' THEN r.type ELSE c.type END,
        value = CASE WHEN item ? 'value' THEN r.value ELSE c.value END,
        label = CASE WHEN item ? 'label' THEN r.label ELSE c.label END,
        is_visible = CASE WHEN item ? 'is_visible' THEN r.is_visible ELSE c.is_visible END,
        sort_order = CASE WHEN item ? 'sort_order' THEN r.sort_order ELSE c.sort_order END
      WHERE c.id = item_id
      RETURNING c.* INTO saved;
    ELSE
      INSERT INTO public.contact_items (card_id, type, value, label, is_visible, sort_order)
      VALUES (
        p_card_id,
        r.type,
        r.value,
        r.label,
        coalesce(r.is_visible, true),
        coalesce(
          r.sort_order,
          (SELECT coalesce(max(sort_order), -1) + 1
           FROM public.contact_items WHERE card_id = p_card_id)
        )
      )
      RETURNING * INTO saved;
    END IF;

    result := result || jsonb_build_array(to_jsonb(saved));
  END LOOP;

  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.lp_admin_delete_contact_item(p_item_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_card_id uuid;
BEGIN
  SELECT card_id INTO v_card_id FROM public.contact_items WHERE id = p_item_id;
  IF v_card_id IS NULL THEN
    RAISE EXCEPTION 'lp_admin_not_found' USING ERRCODE = 'P0002';
  END IF;
  PERFORM public.lp_admin_assert_card(v_card_id);

  UPDATE public.visit_events SET contact_item_id = NULL
  WHERE contact_item_id = p_item_id;
  DELETE FROM public.contact_items WHERE id = p_item_id;
END;
$$;

-- ─── Enlaces / redes ─────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.lp_admin_upsert_social_links(
  p_card_id uuid,
  p_links jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  link jsonb;
  r public.social_links;
  saved public.social_links;
  link_id uuid;
  result jsonb := '[]'::jsonb;
BEGIN
  PERFORM public.lp_admin_assert_card(p_card_id);

  FOR link IN SELECT * FROM jsonb_array_elements(coalesce(p_links, '[]'::jsonb))
  LOOP
    r := jsonb_populate_record(NULL::public.social_links, link);
    link_id := nullif(link->>'id', '')::uuid;

    IF link_id IS NOT NULL THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.social_links
        WHERE id = link_id AND card_id = p_card_id
      ) THEN
        RAISE EXCEPTION 'lp_admin_not_allowed' USING ERRCODE = '42501';
      END IF;

      UPDATE public.social_links s SET
        platform = CASE WHEN link ? 'platform' THEN r.platform ELSE s.platform END,
        url = CASE WHEN link ? 'url' THEN r.url ELSE s.url END,
        custom_label = CASE WHEN link ? 'custom_label' THEN r.custom_label ELSE s.custom_label END,
        icon_key = CASE WHEN link ? 'icon_key' THEN r.icon_key ELSE s.icon_key END,
        is_visible = CASE WHEN link ? 'is_visible' THEN r.is_visible ELSE s.is_visible END,
        sort_order = CASE WHEN link ? 'sort_order' THEN r.sort_order ELSE s.sort_order END
      WHERE s.id = link_id
      RETURNING s.* INTO saved;
    ELSE
      INSERT INTO public.social_links (card_id, platform, url, custom_label, icon_key, is_visible, sort_order)
      VALUES (
        p_card_id,
        r.platform,
        r.url,
        r.custom_label,
        r.icon_key,
        coalesce(r.is_visible, true),
        coalesce(
          r.sort_order,
          (SELECT coalesce(max(sort_order), -1) + 1
           FROM public.social_links WHERE card_id = p_card_id)
        )
      )
      RETURNING * INTO saved;
    END IF;

    result := result || jsonb_build_array(to_jsonb(saved));
  END LOOP;

  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.lp_admin_delete_social_link(p_link_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_card_id uuid;
BEGIN
  SELECT card_id INTO v_card_id FROM public.social_links WHERE id = p_link_id;
  IF v_card_id IS NULL THEN
    RAISE EXCEPTION 'lp_admin_not_found' USING ERRCODE = 'P0002';
  END IF;
  PERFORM public.lp_admin_assert_card(v_card_id);

  UPDATE public.visit_events SET social_link_id = NULL
  WHERE social_link_id = p_link_id;
  DELETE FROM public.social_links WHERE id = p_link_id;
END;
$$;

-- ─── Formularios ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.lp_admin_list_smart_forms(p_card_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.lp_admin_assert_card(p_card_id);
  RETURN coalesce((
    SELECT jsonb_agg(to_jsonb(sf) ORDER BY sf.created_at)
    FROM public.smart_forms sf
    WHERE sf.card_id = p_card_id
  ), '[]'::jsonb);
END;
$$;

-- Con "id" existente de la tarjeta => actualiza; sin "id" => inserta.
CREATE OR REPLACE FUNCTION public.lp_admin_upsert_smart_form(
  p_card_id uuid,
  p_form jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r public.smart_forms;
  saved public.smart_forms;
  form_id uuid;
BEGIN
  PERFORM public.lp_admin_assert_card(p_card_id);
  r := jsonb_populate_record(NULL::public.smart_forms, p_form);
  form_id := nullif(p_form->>'id', '')::uuid;

  IF form_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.smart_forms
      WHERE id = form_id AND card_id = p_card_id
    ) THEN
      RAISE EXCEPTION 'lp_admin_not_allowed' USING ERRCODE = '42501';
    END IF;

    UPDATE public.smart_forms f SET
      name = CASE WHEN p_form ? 'name' THEN r.name ELSE f.name END,
      description = CASE WHEN p_form ? 'description' THEN r.description ELSE f.description END,
      success_message = CASE WHEN p_form ? 'success_message' THEN coalesce(r.success_message, f.success_message) ELSE f.success_message END,
      included_fields = CASE WHEN p_form ? 'included_fields' THEN coalesce(r.included_fields, f.included_fields) ELSE f.included_fields END,
      is_active = CASE WHEN p_form ? 'is_active' THEN r.is_active ELSE f.is_active END
    WHERE f.id = form_id
    RETURNING f.* INTO saved;
  ELSE
    INSERT INTO public.smart_forms (card_id, name, description, success_message, included_fields, is_active)
    VALUES (
      p_card_id,
      r.name,
      r.description,
      coalesce(r.success_message, 'Gracias, recibimos tu información.'),
      coalesce(r.included_fields, '["name", "email", "phone", "message"]'::jsonb),
      coalesce(r.is_active, true)
    )
    RETURNING * INTO saved;
  END IF;

  RETURN to_jsonb(saved);
END;
$$;

CREATE OR REPLACE FUNCTION public.lp_admin_delete_smart_form(p_form_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_card_id uuid;
BEGIN
  SELECT card_id INTO v_card_id FROM public.smart_forms WHERE id = p_form_id;
  IF v_card_id IS NULL THEN
    RAISE EXCEPTION 'lp_admin_not_found' USING ERRCODE = 'P0002';
  END IF;
  PERFORM public.lp_admin_assert_card(v_card_id);

  DELETE FROM public.form_submissions WHERE form_id = p_form_id;
  UPDATE public.visit_events SET smart_form_id = NULL
  WHERE smart_form_id = p_form_id;
  DELETE FROM public.smart_forms WHERE id = p_form_id;
END;
$$;

-- ─── Permisos de ejecucion ───────────────────────────────────────────────────

REVOKE ALL ON FUNCTION public.lp_admin_get_org(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lp_admin_update_card(uuid, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lp_admin_upsert_contact_items(uuid, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lp_admin_delete_contact_item(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lp_admin_upsert_social_links(uuid, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lp_admin_delete_social_link(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lp_admin_list_smart_forms(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lp_admin_upsert_smart_form(uuid, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lp_admin_delete_smart_form(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.lp_admin_get_org(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.lp_admin_update_card(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.lp_admin_upsert_contact_items(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.lp_admin_delete_contact_item(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.lp_admin_upsert_social_links(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.lp_admin_delete_social_link(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.lp_admin_list_smart_forms(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.lp_admin_upsert_smart_form(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.lp_admin_delete_smart_form(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
