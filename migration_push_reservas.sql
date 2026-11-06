-- =============================================================================
-- AVISOS PUSH de reserva nueva (llegan aunque el panel esté cerrado)
--
-- Flujo: INSERT en reservas -> trigger -> pg_net llama a la edge function
-- `push-reserva` con el id -> la función lee la reserva, la marca como avisada
-- (una sola vez) y manda el push a los equipos suscritos del dueño y recepción.
-- =============================================================================
create extension if not exists pg_net with schema extensions;

-- Claves VAPID. Sin políticas RLS: solo las lee la edge function (service role).
create table if not exists public.push_config (clave text primary key, valor text not null);
alter table public.push_config enable row level security;
insert into public.push_config (clave, valor) values
  ('vapid_public',  'PEGAR_AQUI_LA_CLAVE_PUBLICA'),
  ('vapid_private', 'PEGAR_AQUI_LA_CLAVE_PRIVADA')
on conflict (clave) do nothing;

create table if not exists public.push_suscripciones (
  id          uuid primary key default gen_random_uuid(),
  barberia_id uuid not null references public.barberias(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  endpoint    text not null unique,
  p256dh      text not null,
  auth        text not null,
  created_at  timestamptz not null default now()
);
alter table public.push_suscripciones enable row level security;
-- Sin políticas: se toca solo desde las funciones de abajo y la edge function.

alter table public.reservas add column if not exists push_enviado_at timestamptz;

-- Clave pública para que el navegador se suscriba (la privada nunca sale).
create or replace function public.push_clave_publica()
returns text language sql security definer set search_path to 'public' as $$
  select valor from push_config where clave = 'vapid_public';
$$;

create or replace function public.registrar_push(p_endpoint text, p_p256dh text, p_auth text)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if auth.uid() is null or auth_barberia_id() is null or auth_rol() not in ('dueno','recepcion') then
    raise exception 'No autorizado';
  end if;
  if coalesce(p_endpoint,'') = '' or coalesce(p_p256dh,'') = '' or coalesce(p_auth,'') = '' then
    raise exception 'Suscripción incompleta';
  end if;
  insert into push_suscripciones (barberia_id, user_id, endpoint, p256dh, auth)
  values (auth_barberia_id(), auth.uid(), p_endpoint, p_p256dh, p_auth)
  on conflict (endpoint) do update
    set barberia_id = excluded.barberia_id, user_id = excluded.user_id,
        p256dh = excluded.p256dh, auth = excluded.auth;
end;
$$;

create or replace function public.quitar_push(p_endpoint text)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if auth.uid() is null then raise exception 'No autorizado'; end if;
  delete from push_suscripciones where endpoint = p_endpoint and user_id = auth.uid();
end;
$$;

revoke execute on function public.registrar_push(text,text,text) from public, anon;
revoke execute on function public.quitar_push(text) from public, anon;
grant execute on function public.registrar_push(text,text,text) to authenticated;
grant execute on function public.quitar_push(text) to authenticated;

-- Trigger: avisa a la edge function. Si la llamada falla, la reserva igual se crea.
create or replace function public.trg_reserva_push()
returns trigger language plpgsql security definer set search_path to 'public', 'extensions' as $$
begin
  begin
    perform net.http_post(
      url := 'https://dqoqykngmtxtvbokxbzp.supabase.co/functions/v1/push-reserva',
      headers := '{"Content-Type":"application/json"}'::jsonb,
      body := jsonb_build_object('reserva_id', new.id)
    );
  exception when others then
    null;
  end;
  return new;
end;
$$;
drop trigger if exists reservas_push on public.reservas;
create trigger reservas_push after insert on public.reservas
  for each row execute function public.trg_reserva_push();
