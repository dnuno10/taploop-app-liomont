-- Reportes para administradores de LIOMONT y PROMOFARMA en
-- liomont.taploop.com.mx:
--   * lp_admin_nfc_reference(): relacion serial NFC <-> colaborador
--     (nombre, empresa, correo, organizacion).
--   * lp_admin_leads_directory(p_user_id): leads de un colaborador, o de
--     todos los colaboradores de LIOMONT + PROMOFARMA si p_user_id es null.
--
-- NO modifica politicas RLS, tablas ni funciones existentes. Solo crea 2
-- funciones NUEVAS de solo lectura. Solo devuelven datos si quien llama es
-- admin/owner/super_admin de LIOMONT o PROMOFARMA, y solo de esas 2 orgs.
-- app.taploop.com.mx y el resto de organizaciones no se ven afectados.
--
-- Requiere haber ejecutado antes add_liomont_promofarma_admin_edit_rpcs.sql
-- (usa lp_admin_caller_allowed y lp_admin_is_linked_org).
-- Ejecutar completo en Supabase SQL Editor.

CREATE OR REPLACE FUNCTION public.lp_admin_nfc_reference()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.lp_admin_caller_allowed() THEN
    RAISE EXCEPTION 'lp_admin_not_allowed' USING ERRCODE = '42501';
  END IF;

  RETURN coalesce((
    SELECT jsonb_agg(row_data ORDER BY row_data->>'user_name', row_data->>'serial')
    FROM (
      SELECT jsonb_build_object(
        'serial', n.serial,
        'assigned_at', n.assigned_at,
        'card_id', dc.id,
        'public_slug', dc.public_slug,
        'user_id', u.id,
        'user_name', coalesce(nullif(dc.name, ''), u.name),
        'user_email', u.email,
        'company', coalesce(nullif(dc.company, ''), o.name),
        'org_id', o.id,
        'org_name', o.name
      ) AS row_data
      FROM public.nfc_cards n
      JOIN public.digital_cards dc ON dc.id = n.digital_card_id
      LEFT JOIN public.users u ON u.id = dc.user_id
      LEFT JOIN public.organizations o ON o.id = coalesce(u.org_id, dc.org_id)
      WHERE n.serial IS NOT NULL
        AND (
          public.lp_admin_is_linked_org(dc.org_id)
          OR public.lp_admin_is_linked_org(u.org_id)
        )
    ) rows
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.lp_admin_leads_directory(
  p_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.lp_admin_caller_allowed() THEN
    RAISE EXCEPTION 'lp_admin_not_allowed' USING ERRCODE = '42501';
  END IF;

  RETURN coalesce((
    SELECT jsonb_agg(row_data ORDER BY row_data->>'last_seen' DESC NULLS LAST)
    FROM (
      SELECT jsonb_build_object(
        'id', l.id,
        'name', l.name,
        'company', l.company,
        'location', l.location,
        'form_type', l.form_type,
        'form_data', l.form_data,
        'pipeline_stage', l.pipeline_stage,
        'is_converted', l.is_converted,
        'first_seen', l.first_seen,
        'last_seen', coalesce(l.last_seen, l.created_at),
        'created_at', l.created_at,
        'collaborator_id', u.id,
        'collaborator_name', coalesce(nullif(dc.name, ''), u.name),
        'collaborator_email', u.email,
        'org_name', o.name
      ) AS row_data
      FROM public.leads l
      JOIN public.digital_cards dc ON dc.id = l.card_id
      LEFT JOIN public.users u ON u.id = dc.user_id
      LEFT JOIN public.organizations o ON o.id = coalesce(u.org_id, dc.org_id)
      WHERE (
          public.lp_admin_is_linked_org(dc.org_id)
          OR public.lp_admin_is_linked_org(u.org_id)
        )
        AND (p_user_id IS NULL OR dc.user_id = p_user_id)
    ) rows
  ), '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.lp_admin_nfc_reference() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lp_admin_leads_directory(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lp_admin_nfc_reference() TO authenticated;
GRANT EXECUTE ON FUNCTION public.lp_admin_leads_directory(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
