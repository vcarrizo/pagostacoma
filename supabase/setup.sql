-- =====================================================================
--  Planificación de Pagos TACOMA · estructura en Supabase
--  Ejecutar UNA vez en: Supabase → SQL Editor → New query → Run
--  (se puede volver a correr sin romper nada)
-- =====================================================================

-- 1) Tablas ------------------------------------------------------------

-- Cheques del último listado cargado, por empresa emisora
create table if not exists public.cheques (
  empresa_cuit   text          not null,          -- CUIT de la empresa del listado (ej. 30718171306)
  clave          text          not null,          -- id único del cheque dentro de la empresa (n:<nro>)
  empresa        text,                            -- "30718171306 - KERF SAS"
  numero         text,                            -- Nro. de cheque
  fecha_pago     date          not null,
  fecha_emision  date,
  importe        numeric(18,2) not null,
  cuit           text,                            -- CUIT beneficiario
  razon          text,                            -- Razón social beneficiario
  estado         text,                            -- estado tal cual viene del banco
  cat            text,                            -- activo | pendacep | pagado | anulado
  primary key (empresa_cuit, clave)
);
create index if not exists cheques_fecha_pago_idx on public.cheques (fecha_pago);

-- Historial de cargas (quién subió qué y cuándo)
create table if not exists public.cargas (
  id             bigint generated always as identity primary key,
  empresa_cuit   text        not null,
  empresa        text,
  archivo        text,
  descarga_banco text,                            -- "Fecha de descarga" que figura en el listado
  cantidad       int,
  cargado_por    text,
  cargado_at     timestamptz not null default now()
);
create index if not exists cargas_empresa_fecha_idx on public.cargas (empresa_cuit, cargado_at desc);

-- Usuarios que pueden CARGAR listados (el resto solo puede ver)
create table if not exists public.admins (
  email text primary key
);

-- 2) Seguridad (Row Level Security) -------------------------------------

alter table public.cheques enable row level security;
alter table public.cargas  enable row level security;
alter table public.admins  enable row level security;

grant usage on schema public to authenticated;
grant select on public.cheques, public.cargas to authenticated;
revoke all on public.cheques, public.cargas, public.admins from anon;

drop policy if exists "usuarios logueados leen cheques" on public.cheques;
create policy "usuarios logueados leen cheques" on public.cheques
  for select to authenticated using (true);

drop policy if exists "usuarios logueados leen cargas" on public.cargas;
create policy "usuarios logueados leen cargas" on public.cargas
  for select to authenticated using (true);
-- admins: sin políticas => nadie la lee/escribe desde la web; se consulta solo vía es_admin()

-- 3) Funciones ----------------------------------------------------------

create or replace function public.es_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.admins
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

-- Reemplaza todos los cheques de una empresa por los del nuevo listado (atómico)
create or replace function public.reemplazar_listado(
  p_empresa_cuit text,
  p_empresa      text,
  p_archivo      text,
  p_descarga     text,
  p_filas        jsonb
)
returns int
language plpgsql security definer
set search_path = public
as $$
declare
  n int;
begin
  if not public.es_admin() then
    raise exception 'Tu usuario no tiene permiso para cargar listados' using errcode = '42501';
  end if;
  if p_filas is null or jsonb_array_length(p_filas) = 0 then
    raise exception 'El listado no tiene cheques';
  end if;

  delete from public.cheques where empresa_cuit = p_empresa_cuit;

  insert into public.cheques
    (empresa_cuit, clave, empresa, numero, fecha_pago, fecha_emision, importe, cuit, razon, estado, cat)
  select p_empresa_cuit, f.clave, p_empresa, f.numero, f.fecha_pago, f.fecha_emision, f.importe,
         f.cuit, f.razon, f.estado, f.cat
  from jsonb_to_recordset(p_filas) as f(
    clave text, numero text, fecha_pago date, fecha_emision date, importe numeric,
    cuit text, razon text, estado text, cat text
  )
  on conflict (empresa_cuit, clave) do update
    set numero = excluded.numero, fecha_pago = excluded.fecha_pago, fecha_emision = excluded.fecha_emision,
        importe = excluded.importe, cuit = excluded.cuit, razon = excluded.razon,
        estado = excluded.estado, cat = excluded.cat;
  get diagnostics n = row_count;

  insert into public.cargas (empresa_cuit, empresa, archivo, descarga_banco, cantidad, cargado_por)
  values (p_empresa_cuit, p_empresa, p_archivo, p_descarga, n, auth.jwt() ->> 'email');

  return n;
end;
$$;

revoke execute on function public.es_admin() from public, anon;
revoke execute on function public.reemplazar_listado(text, text, text, text, jsonb) from public, anon;
grant execute on function public.es_admin() to authenticated;
grant execute on function public.reemplazar_listado(text, text, text, text, jsonb) to authenticated;

-- 4) Administradores ----------------------------------------------------
--    Agregá acá (o después, con otro insert) los emails que pueden cargar listados.
insert into public.admins (email) values ('vcarrizo2010@gmail.com')
on conflict (email) do nothing;
