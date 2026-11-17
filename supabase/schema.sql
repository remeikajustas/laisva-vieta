-- Operacija "Laisva vieta" - visa Supabase schema (galutine busena po penkiu migraciju; paskutines - lv_admin_role, lv_mission_times).
-- Projektas: laisva-vieta (ref ymffiqwouoglefvvzfru, eu-central-1). Jau pritaikyta; sis failas - atkurimui.
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.lv_players (
  name_lower text primary key,
  name       text not null,
  pass_hash  text not null,
  token      uuid not null default gen_random_uuid(),
  best       jsonb not null default '{}'::jsonb,
  total      int  not null default 0,
  updated    timestamptz not null default now(),
  fails      int  not null default 0,
  locked_until timestamptz,
  is_admin   boolean not null default false,
  best_time  jsonb not null default '{}'::jsonb   -- best (lowest) server-measured seconds per mission
);
alter table public.lv_players add column if not exists is_admin boolean not null default false;
alter table public.lv_players add column if not exists best_time jsonb not null default '{}'::jsonb;
create table if not exists public.lv_runs (
  id uuid primary key default gen_random_uuid(),
  name_lower text not null references public.lv_players(name_lower) on delete cascade,
  mission text not null,
  started timestamptz not null default now()
);
create index if not exists lv_runs_player on public.lv_runs(name_lower);
-- RLS be taisykliu: tiesiogiai lenteliu niekas nepasiekia, viskas tik per funkcijas.
alter table public.lv_players enable row level security;
alter table public.lv_runs enable row level security;

create or replace function public.lv_register(p_name text, p_pass text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare t uuid; n text := btrim(p_name);
begin
  if n is null or p_pass is null or char_length(n) not between 3 and 16 or char_length(p_pass) not between 4 and 64
     or n ~ '[<>&"''`\\/%;[:cntrl:]]' then
    return json_build_object('error','bad_input'); end if;
  if (select count(*) from lv_players) >= 2000 then return json_build_object('error','full'); end if;
  if (select count(*) from lv_players where updated > now() - interval '1 hour' and total = 0) >= 60 then
    return json_build_object('error','full'); end if;
  begin
    insert into lv_players(name_lower,name,pass_hash) values (lower(n), n, crypt(p_pass, gen_salt('bf'))) returning token into t;
  exception when unique_violation then return json_build_object('error','taken'); end;
  return json_build_object('name',n,'token',t,'best','{}'::jsonb);
end $$;

-- Uzrakinimas (5 blogi bandymai -> 10 min) negalioja irenginiui, kuris jau turi zaidejo token (p_device).
drop function if exists public.lv_login(text,text);
create or replace function public.lv_login(p_name text, p_pass text, p_device uuid default null) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare r lv_players; known boolean;
begin
  if p_name is null or p_pass is null or char_length(p_pass) > 64 then return json_build_object('error','invalid'); end if;
  select * into r from lv_players where name_lower = lower(btrim(p_name));
  if not found then return json_build_object('error','invalid'); end if;
  known := p_device is not null and p_device = r.token;
  if not known and r.locked_until is not null and r.locked_until > now() then return json_build_object('error','locked'); end if;
  if r.pass_hash <> crypt(p_pass, r.pass_hash) then
    if not known then
      update lv_players set fails = case when fails >= 4 then 0 else fails + 1 end,
                            locked_until = case when fails >= 4 then now() + interval '10 minutes' else locked_until end
       where name_lower = r.name_lower;
    end if;
    return json_build_object('error','invalid');
  end if;
  if known then update lv_players set fails = 0, locked_until = null where name_lower = r.name_lower and (fails <> 0 or locked_until is not null); end if;
  return json_build_object('name',r.name,'token',r.token,'best',r.best,'best_time',r.best_time,'admin',r.is_admin);
end $$;

create or replace function public.lv_resume(p_name text, p_token uuid) returns json
language plpgsql security definer set search_path = public as $$
declare r lv_players;
begin
  select * into r from lv_players where name_lower = lower(btrim(p_name)) and token = p_token;
  if not found then return json_build_object('error','invalid'); end if;
  return json_build_object('name',r.name,'token',r.token,'best',r.best,'best_time',r.best_time,'admin',r.is_admin);
end $$;

create or replace function public.lv_start(p_name text, p_token uuid, p_mission text) returns json
language plpgsql security definer set search_path = public as $$
declare nl text := lower(btrim(p_name)); rid uuid;
begin
  if p_mission is null or p_mission !~ '^m[1-6]$' then return json_build_object('error','bad_input'); end if;
  perform 1 from lv_players where name_lower = nl and token = p_token;
  if not found then return json_build_object('error','invalid'); end if;
  delete from lv_runs where name_lower = nl or started < now() - interval '1 day';
  insert into lv_runs(name_lower, mission) values (nl, p_mission) returning id into rid;
  return json_build_object('run', rid);
end $$;

create or replace function public.lv_finish(p_name text, p_token uuid, p_run uuid, p_score int) returns json
language plpgsql security definer set search_path = public as $$
-- Elapsed time is measured on the server (lv_start -> lv_finish), so it cannot be forged in the browser.
declare nl text := lower(btrim(p_name)); r lv_runs; el numeric; lim int; cap int; nb jsonb; nt jsonb; tot int;
begin
  perform 1 from lv_players where name_lower = nl and token = p_token;
  if not found then return json_build_object('error','invalid'); end if;
  delete from lv_runs where id = p_run and name_lower = nl returning * into r;   -- bilietas vienkartinis
  if not found then return json_build_object('error','rejected'); end if;
  select v.lim, v.cap into lim, cap from (values
    ('m1',240, 6000),('m2',270, 8000),('m3',300,10000),('m4',300,16000),('m5',300,22000),('m6',420,42000)) v(m,lim,cap) where v.m = r.mission;
  el := round(extract(epoch from now() - r.started)::numeric, 1);
  if p_score is null or p_score < 0 or el < 15 or el > 7200 or p_score > cap + 2500 + lim * 5 then
    return json_build_object('error','rejected'); end if;
  update lv_players p set
     best = p.best || jsonb_build_object(r.mission, greatest(coalesce((p.best->>r.mission)::int,0), p_score)),
     best_time = p.best_time || jsonb_build_object(r.mission, least(coalesce((p.best_time->>r.mission)::numeric, el), el)),
     updated = now()
   where p.name_lower = nl returning best, best_time into nb, nt;
  select coalesce(sum(value::numeric),0)::int into tot from jsonb_each_text(nb);
  update lv_players set total = tot where name_lower = nl;
  return json_build_object('ok',true,'best',nb,'total',tot,'time',el,'best_time',nt);
end $$;

-- Ranking: more missions completed first, then lower sum of best times, then more points.
create or replace function public.lv_board() returns json
language sql security definer set search_path = public as $$
  select coalesce(json_agg(q),'[]'::json) from (
    select name, total, missions, secs from (
      select name, total, updated,
             (select count(*) from jsonb_object_keys(best_time))::int as missions,
             (select coalesce(sum(value::numeric),0) from jsonb_each_text(best_time)) as secs
        from lv_players where not is_admin) s
    order by missions desc, secs asc, total desc, updated asc limit 15) q;
$$;

-- Admin: player list with lock status. Caller must be an admin (name + token).
create or replace function public.lv_admin_list(p_name text, p_token uuid) returns json
language plpgsql security definer set search_path = public as $$
begin
  perform 1 from lv_players where name_lower = lower(btrim(p_name)) and token = p_token and is_admin;
  if not found then return json_build_object('error','forbidden'); end if;
  return (select coalesce(json_agg(q),'[]'::json) from (
    select name, total, fails, (locked_until is not null and locked_until > now()) as locked, locked_until, updated
      from lv_players where not is_admin order by updated desc limit 500) q);
end $$;

-- Admin: clear lockout; with p_newpass also set a new password and rotate the token (logs the player out everywhere).
create or replace function public.lv_admin_unlock(p_name text, p_token uuid, p_target text, p_newpass text default null) returns json
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform 1 from lv_players where name_lower = lower(btrim(p_name)) and token = p_token and is_admin;
  if not found then return json_build_object('error','forbidden'); end if;
  if p_target is null or (p_newpass is not null and char_length(p_newpass) not between 4 and 64) then
    return json_build_object('error','bad_input'); end if;
  update lv_players set fails = 0, locked_until = null,
         pass_hash = case when p_newpass is null then pass_hash else crypt(p_newpass, gen_salt('bf')) end,
         token     = case when p_newpass is null then token else gen_random_uuid() end
   where name_lower = lower(btrim(p_target)) and not is_admin;
  if not found then return json_build_object('error','not_found'); end if;
  return json_build_object('ok',true,'password_changed',p_newpass is not null);
end $$;
-- Admin account itself is created by hand (is_admin = true); its password is not stored in this file.

drop function if exists public.lv_save(text,uuid,jsonb);

revoke all on function public.lv_register(text,text), public.lv_login(text,text,uuid), public.lv_resume(text,uuid),
  public.lv_start(text,uuid,text), public.lv_finish(text,uuid,uuid,int), public.lv_board() from public;
grant execute on function public.lv_register(text,text), public.lv_login(text,text,uuid), public.lv_resume(text,uuid),
  public.lv_start(text,uuid,text), public.lv_finish(text,uuid,uuid,int), public.lv_board() to anon, authenticated;
revoke all on function public.lv_admin_list(text,uuid), public.lv_admin_unlock(text,uuid,text,text) from public;
grant execute on function public.lv_admin_list(text,uuid), public.lv_admin_unlock(text,uuid,text,text) to anon, authenticated;
