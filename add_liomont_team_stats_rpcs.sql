-- Acelera la carga de Administracion / Equipo / Analiticas en
-- liomont.taploop.com.mx: en lugar de descargar TODOS los visit_events y
-- leads de cada tarjeta para contarlos en el navegador, la base de datos
-- devuelve ya los conteos agrupados.
--
-- NO modifica politicas RLS, tablas ni funciones existentes. Solo crea 2
-- funciones NUEVAS de solo lectura con SECURITY INVOKER: se ejecutan con los
-- permisos del usuario que las llama, asi que respetan exactamente el mismo
-- RLS que las consultas actuales (no dan acceso a nada nuevo).
-- Solo las llama la app de Liomont; app.taploop.com.mx no se ve afectado.
--
-- Si estas funciones no existen, la app sigue funcionando con el metodo
-- anterior (mas lento).
--
-- Ejecutar completo en Supabase SQL Editor.

-- Conteos de visit_events por tarjeta, fuente y enlace. day_bucket es el dia
-- (0-6) dentro de los 7 dias que empiezan en p_since, o null si el evento
-- cae fuera de ese rango.
CREATE OR REPLACE FUNCTION public.liomont_team_visit_stats(
  p_card_ids uuid[],
  p_since timestamptz
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb)
  FROM (
    SELECT
      ve.card_id,
      ve.source,
      ve.contact_item_id,
      ve.social_link_id,
      CASE
        WHEN ve."timestamp" >= p_since
         AND ve."timestamp" < p_since + interval '7 days'
        THEN floor(extract(epoch FROM (ve."timestamp" - p_since)) / 86400)::int
      END AS day_bucket,
      count(*) AS event_count
    FROM public.visit_events ve
    WHERE ve.card_id = ANY (p_card_ids)
    GROUP BY 1, 2, 3, 4, 5
  ) s;
$$;

-- Conteo de leads y leads convertidos por tarjeta.
CREATE OR REPLACE FUNCTION public.liomont_team_lead_stats(p_card_ids uuid[])
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb)
  FROM (
    SELECT
      l.card_id,
      count(*) AS lead_count,
      count(*) FILTER (WHERE coalesce(l.is_converted, false)) AS converted_count
    FROM public.leads l
    WHERE l.card_id = ANY (p_card_ids)
    GROUP BY l.card_id
  ) s;
$$;

REVOKE ALL ON FUNCTION public.liomont_team_visit_stats(uuid[], timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.liomont_team_lead_stats(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.liomont_team_visit_stats(uuid[], timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.liomont_team_lead_stats(uuid[]) TO authenticated;

NOTIFY pgrst, 'reload schema';
