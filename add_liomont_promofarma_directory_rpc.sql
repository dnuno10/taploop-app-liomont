-- Directorio compartido de LIOMONT + PROMOFARMA para la seccion de
-- Administracion de liomont.taploop.com.mx.
--
-- NO modifica politicas RLS, funciones ni tablas existentes: solo crea una
-- funcion nueva de SOLO LECTURA que unicamente llama la app de Liomont.
-- app.taploop.com.mx y el resto de organizaciones no se ven afectados.
--
-- La funcion devuelve datos solo si quien la llama es admin de LIOMONT o
-- PROMOFARMA; para cualquier otro usuario devuelve una lista vacia.
--
-- Ejecutar completo en Supabase SQL Editor.

CREATE OR REPLACE FUNCTION public.get_liomont_promofarma_directory()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH linked_orgs(id) AS (
    VALUES
      ('293f05a3-9115-4b72-a4ac-2c4d3a8af83e'::uuid), -- LIOMONT
      ('4a7357d3-5222-4555-aaa9-f5cbe7b1d81d'::uuid)  -- PROMOFARMA
  ),
  caller AS (
    SELECT u.id
    FROM public.users u
    WHERE u.id = auth.uid()
      AND lower(u.role) IN ('admin', 'owner', 'super_admin')
      AND u.org_id IN (SELECT id FROM linked_orgs)
  )
  SELECT coalesce(jsonb_agg(entry ORDER BY entry->>'name'), '[]'::jsonb)
  FROM (
    SELECT jsonb_build_object(
      'id', u.id,
      'name', u.name,
      'email', u.email,
      'job_title', u.job_title,
      'photo_url', u.photo_url,
      'role', u.role,
      'org_id', u.org_id,
      'org_name', o.name,
      'nfc_serials', coalesce((
        SELECT jsonb_agg(n.serial)
        FROM public.nfc_cards n
        JOIN public.digital_cards ndc ON ndc.id = n.digital_card_id
        WHERE ndc.user_id = u.id
      ), '[]'::jsonb),
      'card', (
        SELECT to_jsonb(dc) || jsonb_build_object(
          'contact_items', coalesce((
            SELECT jsonb_agg(to_jsonb(ci) ORDER BY ci.sort_order)
            FROM public.contact_items ci
            WHERE ci.card_id = dc.id
          ), '[]'::jsonb),
          'social_links', coalesce((
            SELECT jsonb_agg(to_jsonb(sl) ORDER BY sl.sort_order)
            FROM public.social_links sl
            WHERE sl.card_id = dc.id
          ), '[]'::jsonb),
          'smart_forms', coalesce((
            SELECT jsonb_agg(to_jsonb(sf) ORDER BY sf.created_at)
            FROM public.smart_forms sf
            WHERE sf.card_id = dc.id
          ), '[]'::jsonb)
        )
        FROM public.digital_cards dc
        WHERE dc.user_id = u.id
        ORDER BY dc.created_at, dc.id
        LIMIT 1
      )
    ) AS entry
    FROM public.users u
    LEFT JOIN public.organizations o ON o.id = u.org_id
    WHERE u.org_id IN (SELECT id FROM linked_orgs)
      AND u.is_active = true
      AND EXISTS (SELECT 1 FROM caller)
  ) entries;
$$;

REVOKE ALL ON FUNCTION public.get_liomont_promofarma_directory() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_liomont_promofarma_directory() TO authenticated;

NOTIFY pgrst, 'reload schema';
