-- Validacion de slugs publicos para liomont.taploop.com.mx.
--
-- liomont_is_slug_available(p_slug, p_card_id): true si NINGUNA otra tarjeta
-- (de cualquier organizacion) usa ese slug, sin distinguir mayusculas ni
-- espacios. El enlace publico liomont.taploop.com.mx/<slug> busca en todas
-- las tarjetas, por eso la revision debe ser global y no limitada por RLS.
--
-- Solo devuelve true/false: no expone datos de ninguna tarjeta.
-- NO modifica politicas RLS, tablas ni funciones existentes; es una funcion
-- NUEVA de solo lectura que solo llama la app de Liomont.
--
-- Ejecutar completo en Supabase SQL Editor.

CREATE OR REPLACE FUNCTION public.liomont_is_slug_available(
  p_slug text,
  p_card_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT NOT EXISTS (
    SELECT 1
    FROM public.digital_cards dc
    WHERE lower(btrim(dc.public_slug)) = lower(btrim(p_slug))
      AND (p_card_id IS NULL OR dc.id <> p_card_id)
  );
$$;

REVOKE ALL ON FUNCTION public.liomont_is_slug_available(text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.liomont_is_slug_available(text, uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ─── Opcional: revisar si YA existen slugs repetidos ─────────────────────────
-- (solo lectura; si devuelve filas, esos perfiles comparten enlace publico)
--
-- SELECT lower(btrim(public_slug)) AS slug, count(*) AS tarjetas,
--        array_agg(id) AS card_ids
-- FROM public.digital_cards
-- WHERE public_slug IS NOT NULL AND btrim(public_slug) <> ''
-- GROUP BY 1
-- HAVING count(*) > 1
-- ORDER BY 2 DESC;
