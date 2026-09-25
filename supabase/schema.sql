-- =====================================================================
-- Esquema para "Prorrateo de Impresión" — histórico de Reportes Ricoh
-- Ejecutar una sola vez en: Supabase → tu proyecto → SQL Editor → New query
-- =====================================================================

create table if not exists printer_batches (
  id bigint generated always as identity primary key,
  nombre_archivo text not null,
  etiqueta text,
  fecha_desde date,
  fecha_hasta date,
  total_registros integer default 0,
  creado_en timestamptz default now()
);

create table if not exists printer_records (
  id bigint generated always as identity primary key,
  batch_id bigint references printer_batches(id) on delete cascade,
  fecha timestamptz,
  usuario text not null,
  nombre text,
  departamento text,
  ceco text,
  dispositivo text,
  serie text,
  descripcion text,
  tipo text,
  total integer,
  creado_en timestamptz default now()
);

create index if not exists idx_printer_records_usuario on printer_records (usuario);
create index if not exists idx_printer_records_fecha on printer_records (fecha);
create index if not exists idx_printer_batches_nombre on printer_batches (nombre_archivo);

-- RLS: se habilita porque Supabase lo exige para tablas expuestas por la API,
-- pero se deja en modo permisivo porque el aplicativo es interno y usa la
-- anon key solo para leer/escribir estas dos tablas. Si el archivo HTML se
-- fuera a publicar en un sitio de acceso público, conviene restringir estas
-- políticas (por ejemplo, solo lectura, o añadir autenticación).
alter table printer_batches enable row level security;
alter table printer_records enable row level security;

drop policy if exists "allow all batches" on printer_batches;
create policy "allow all batches" on printer_batches for all using (true) with check (true);

drop policy if exists "allow all records" on printer_records;
create policy "allow all records" on printer_records for all using (true) with check (true);

-- =====================================================================
-- Función para el módulo de Anomalías: total de impresiones por usuario
-- y por día calendario (huso horario de Lima), agregado en el servidor.
-- Si ya habías ejecutado la primera versión de este script, solo necesitas
-- ejecutar esta parte nueva (CREATE OR REPLACE no rompe nada existente).
-- =====================================================================
create or replace function public.printer_daily_totals()
returns table (
  usuario text,
  nombre text,
  fecha_dia date,
  total bigint,
  bn bigint,
  color bigint
)
language sql
stable
as $$
  select
    r.usuario,
    (array_agg(r.nombre) filter (where r.nombre is not null and r.nombre <> ''))[1] as nombre,
    (r.fecha at time zone 'America/Lima')::date as fecha_dia,
    sum(r.total)::bigint as total,
    coalesce(sum(r.total) filter (where upper(r.tipo) = 'BN'), 0)::bigint as bn,
    coalesce(sum(r.total) filter (where upper(r.tipo) <> 'BN' or r.tipo is null), 0)::bigint as color
  from printer_records r
  where r.fecha is not null
  group by r.usuario, (r.fecha at time zone 'America/Lima')::date;
$$;

grant execute on function public.printer_daily_totals() to anon, authenticated;

-- =====================================================================
-- Base de Centros de Costo (antes vivía solo dentro del HTML/Cecos.xlsx).
-- Se sincroniza automáticamente: al abrir la app, si estas tablas están
-- vacías se siembran con los datos incorporados en el archivo; después,
-- cada vez que subas un Cecos.xlsx o edites un usuario desde la app,
-- se actualiza aquí y queda disponible para todos los que usen la app.
-- =====================================================================
create table if not exists ceco_users (
  usuario text primary key,
  nombre text,
  ceco text,
  actualizado_en timestamptz default now()
);

create table if not exists ceco_scopes (
  ceco text primary key,
  ambito text not null check (ambito in ('consumo','pecuaria')),
  actualizado_en timestamptz default now()
);

alter table ceco_users enable row level security;
alter table ceco_scopes enable row level security;

drop policy if exists "allow all ceco_users" on ceco_users;
create policy "allow all ceco_users" on ceco_users for all using (true) with check (true);

drop policy if exists "allow all ceco_scopes" on ceco_scopes;
create policy "allow all ceco_scopes" on ceco_scopes for all using (true) with check (true);

-- =====================================================================
-- Funciones para el "Informe de consumo": arman el dashboard agregando
-- en el servidor todo el historial guardado (agrupado por mes, hora Lima),
-- para que la pantalla NO dependa de volver a cargar los Reportes cada vez.
-- p_desde/p_hasta son opcionales — si van null, se usa todo el historial.
-- =====================================================================
create or replace function public.informe_por_usuario(p_desde date default null, p_hasta date default null)
returns table (
  usuario text,
  nombre text,
  departamento text,
  periodo text, -- 'YYYY-MM' del mes, hora Lima
  total bigint,
  bn bigint,
  color bigint
)
language sql stable as $$
  select
    r.usuario,
    (array_agg(r.nombre) filter (where r.nombre is not null and r.nombre <> ''))[1] as nombre,
    (array_agg(r.departamento) filter (where r.departamento is not null and r.departamento <> ''))[1] as departamento,
    to_char(r.fecha at time zone 'America/Lima', 'YYYY-MM') as periodo,
    sum(r.total)::bigint as total,
    coalesce(sum(r.total) filter (where upper(r.tipo) = 'BN'), 0)::bigint as bn,
    coalesce(sum(r.total) filter (where upper(r.tipo) <> 'BN' or r.tipo is null), 0)::bigint as color
  from printer_records r
  where r.fecha is not null
    and (p_desde is null or (r.fecha at time zone 'America/Lima')::date >= p_desde)
    and (p_hasta is null or (r.fecha at time zone 'America/Lima')::date <= p_hasta)
  group by r.usuario, to_char(r.fecha at time zone 'America/Lima', 'YYYY-MM');
$$;
grant execute on function public.informe_por_usuario(date, date) to anon, authenticated;

create or replace function public.informe_por_dispositivo(p_desde date default null, p_hasta date default null)
returns table (
  dispositivo text,
  serie text,
  periodo text,
  total bigint,
  bn bigint,
  color bigint
)
language sql stable as $$
  select
    (array_agg(r.dispositivo) filter (where r.dispositivo is not null and r.dispositivo <> ''))[1] as dispositivo,
    coalesce(nullif(r.serie,''), r.dispositivo) as serie,
    to_char(r.fecha at time zone 'America/Lima', 'YYYY-MM') as periodo,
    sum(r.total)::bigint as total,
    coalesce(sum(r.total) filter (where upper(r.tipo) = 'BN'), 0)::bigint as bn,
    coalesce(sum(r.total) filter (where upper(r.tipo) <> 'BN' or r.tipo is null), 0)::bigint as color
  from printer_records r
  where r.fecha is not null and (r.dispositivo is not null or r.serie is not null)
    and (p_desde is null or (r.fecha at time zone 'America/Lima')::date >= p_desde)
    and (p_hasta is null or (r.fecha at time zone 'America/Lima')::date <= p_hasta)
  group by coalesce(nullif(r.serie,''), r.dispositivo), to_char(r.fecha at time zone 'America/Lima', 'YYYY-MM');
$$;
grant execute on function public.informe_por_dispositivo(date, date) to anon, authenticated;

create or replace function public.printer_records_date_range()
returns table(min_fecha date, max_fecha date)
language sql stable as $$
  select min((fecha at time zone 'America/Lima')::date), max((fecha at time zone 'America/Lima')::date)
  from printer_records where fecha is not null;
$$;
grant execute on function public.printer_records_date_range() to anon, authenticated;





-- =====================================================================
-- CONSOLIDACIÓN: empresa por prefijo de CeCo, usuarios sin CeCo y
-- consumo por empresa (lógica de helpdesk-web, adaptada a este esquema).
-- =====================================================================
create or replace function public.empresa_from_ceco(p_ceco text)
returns text language sql immutable as $$
  select case
    when p_ceco is null or btrim(p_ceco) = '' then null
    when lower(btrim(p_ceco)) = 'bedrock' then 'Bedrock'
    when upper(left(btrim(p_ceco),2)) = 'MP' then 'MP San Antonio'
    when upper(left(btrim(p_ceco),2)) = 'PG' then 'Protein Group'
    when upper(left(btrim(p_ceco),2)) = 'TA' then 'Técnica Avícola'
    when upper(left(btrim(p_ceco),2)) = 'CH' then 'Charcucorp'
    when upper(left(btrim(p_ceco),2)) = 'OF' then 'Oregon Foods'
    when upper(left(btrim(p_ceco),2)) = 'VA' then 'Valora'
    else 'Desconocida'
  end;
$$;
grant execute on function public.empresa_from_ceco(text) to anon, authenticated;

create or replace function public.usuarios_sin_ceco()
returns table (usuario text, nombre text, total bigint, motivo text)
language sql stable as $$
  select r.usuario,
    (array_agg(r.nombre) filter (where r.nombre is not null and r.nombre <> ''))[1],
    sum(r.total)::bigint,
    case when cu.usuario is null then 'no_encontrado' else 'sin_ceco' end
  from printer_records r
  left join ceco_users cu on cu.usuario = r.usuario
  where cu.usuario is null or coalesce(btrim(cu.ceco), '') = ''
  group by r.usuario, cu.usuario
  order by 3 desc;
$$;
grant execute on function public.usuarios_sin_ceco() to anon, authenticated;

create or replace function public.informe_por_empresa(p_desde date default null, p_hasta date default null)
returns table (empresa text, usuarios bigint, total bigint, bn bigint, color bigint)
language sql stable as $$
  select coalesce(public.empresa_from_ceco(cu.ceco), 'Sin empresa'),
    count(distinct r.usuario)::bigint,
    sum(r.total)::bigint,
    coalesce(sum(r.total) filter (where upper(r.tipo) = 'BN'), 0)::bigint,
    coalesce(sum(r.total) filter (where upper(r.tipo) <> 'BN' or r.tipo is null), 0)::bigint
  from printer_records r
  left join ceco_users cu on cu.usuario = r.usuario
  where r.fecha is not null
    and (p_desde is null or (r.fecha at time zone 'America/Lima')::date >= p_desde)
    and (p_hasta is null or (r.fecha at time zone 'America/Lima')::date <= p_hasta)
  group by 1;
$$;
grant execute on function public.informe_por_empresa(date, date) to anon, authenticated;
