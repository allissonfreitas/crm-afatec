-- =====================================================================
-- CRM AFATEC - Schema base
-- Alvo: Supabase self-hosted (PostgreSQL 15+) na VPS
-- Rodar no SQL Editor do Studio ou: psql -f 01_schema.sql
-- Ordem: 01_schema.sql -> 02_rls.sql -> 03_seed.sql
-- =====================================================================

create extension if not exists pgcrypto;
create extension if not exists unaccent;

-- unaccent() e STABLE; o wrapper IMMUTABLE permite usar em indice
create or replace function public.f_unaccent(text)
returns text language sql immutable strict parallel safe as $$
  select public.unaccent('public.unaccent', $1)
$$;

-- ---------------------------------------------------------------------
-- 1. Tipos
-- ---------------------------------------------------------------------
do $$ begin
  create type papel_usuario as enum ('admin','gestor','vendedor','atendente');
exception when duplicate_object then null; end $$;

do $$ begin
  create type tipo_pessoa as enum ('pf','pj');
exception when duplicate_object then null; end $$;

do $$ begin
  create type status_cliente as enum ('lead','prospect','ativo','inativo','perdido');
exception when duplicate_object then null; end $$;

do $$ begin
  create type tipo_etapa as enum ('aberta','ganho','perdido');
exception when duplicate_object then null; end $$;

do $$ begin
  create type status_oportunidade as enum ('aberta','ganha','perdida');
exception when duplicate_object then null; end $$;

do $$ begin
  create type tipo_atividade as enum ('ligacao','reuniao','email','whatsapp','visita','tarefa','proposta');
exception when duplicate_object then null; end $$;

do $$ begin
  create type direcao_chamada as enum ('entrada','saida');
exception when duplicate_object then null; end $$;

do $$ begin
  create type status_chamada as enum ('tocando','em_atendimento','atendida','perdida','ocupado','nao_atendida','falha','cancelada');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------
-- 2. Utilitários
-- ---------------------------------------------------------------------
create or replace function public.tg_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- Normaliza telefone para E.164 simplificado (só dígitos, com DDI 55)
create or replace function public.normaliza_telefone(p text)
returns text language sql immutable as $$
  select case
    when p is null or regexp_replace(p,'\D','','g') = '' then null
    when length(regexp_replace(p,'\D','','g')) in (10,11)
      then '55' || regexp_replace(p,'\D','','g')
    else regexp_replace(p,'\D','','g')
  end
$$;

-- ---------------------------------------------------------------------
-- 3. Usuários da equipe (espelho de auth.users)
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  nome        text not null default '',
  email       text,
  telefone    text,
  ramal       text,                       -- casa a ligação com o atendente
  avatar_url  text,
  papel       papel_usuario not null default 'vendedor',
  ativo       boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index if not exists profiles_ramal_uidx on public.profiles(ramal) where ramal is not null;
drop trigger if exists set_updated_at on public.profiles;
create trigger set_updated_at before update on public.profiles
  for each row execute function public.tg_set_updated_at();

-- Cria o profile automaticamente quando um usuário é criado no Auth
create or replace function public.tg_novo_usuario()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, nome, email)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'nome', new.raw_user_meta_data->>'full_name', split_part(new.email,'@',1)),
    new.email
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.tg_novo_usuario();

-- ---------------------------------------------------------------------
-- 4. Configuração da empresa (logo, cores, dados)
-- ---------------------------------------------------------------------
create table if not exists public.configuracoes (
  id             smallint primary key default 1 check (id = 1),
  nome_empresa   text not null default 'Afatec',
  cnpj           text,
  telefone       text,
  email          text,
  site           text,
  endereco       text,
  logo_url       text,                    -- storage: bucket "publico", caminho marca/logo.png
  logo_escura_url text,
  favicon_url    text,
  cor_primaria   text not null default '#0B5FFF',
  cor_secundaria text not null default '#0A2540',
  fuso           text not null default 'America/Sao_Paulo',
  updated_at     timestamptz not null default now()
);
drop trigger if exists set_updated_at on public.configuracoes;
create trigger set_updated_at before update on public.configuracoes
  for each row execute function public.tg_set_updated_at();

-- ---------------------------------------------------------------------
-- 5. Cadastros auxiliares
-- ---------------------------------------------------------------------
create table if not exists public.origens (
  id serial primary key,
  nome text not null unique,
  ativo boolean not null default true
);

create table if not exists public.motivos_perda (
  id serial primary key,
  nome text not null unique,
  ativo boolean not null default true
);

create table if not exists public.produtos (
  id          uuid primary key default gen_random_uuid(),
  nome        text not null,
  sku         text unique,
  descricao   text,
  preco       numeric(14,2) not null default 0,
  unidade     text default 'un',
  ativo       boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
drop trigger if exists set_updated_at on public.produtos;
create trigger set_updated_at before update on public.produtos
  for each row execute function public.tg_set_updated_at();

-- ---------------------------------------------------------------------
-- 6. Clientes e contatos
-- ---------------------------------------------------------------------
create table if not exists public.clientes (
  id             uuid primary key default gen_random_uuid(),
  tipo           tipo_pessoa not null default 'pj',
  nome           text not null,                 -- razão social ou nome da pessoa
  nome_fantasia  text,
  documento      text,                          -- CPF/CNPJ só com dígitos
  email          text,
  telefone       text,
  telefone_norm  text generated always as (public.normaliza_telefone(telefone)) stored,
  whatsapp       text,
  whatsapp_norm  text generated always as (public.normaliza_telefone(whatsapp)) stored,
  site           text,
  cep            text,
  logradouro     text,
  numero         text,
  complemento    text,
  bairro         text,
  cidade         text,
  uf             char(2),
  status         status_cliente not null default 'lead',
  origem_id      int references public.origens(id) on delete set null,
  responsavel_id uuid references public.profiles(id) on delete set null,
  tags           text[] not null default '{}',
  observacoes    text,
  created_by     uuid references public.profiles(id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create unique index if not exists clientes_documento_uidx on public.clientes(documento) where documento is not null;
create index if not exists clientes_responsavel_idx on public.clientes(responsavel_id);
create index if not exists clientes_status_idx        on public.clientes(status);
create index if not exists clientes_telefone_idx      on public.clientes(telefone_norm);
create index if not exists clientes_whatsapp_idx      on public.clientes(whatsapp_norm);
create index if not exists clientes_busca_idx on public.clientes
  using gin (to_tsvector('portuguese', public.f_unaccent(coalesce(nome,'') || ' ' || coalesce(nome_fantasia,'') || ' ' || coalesce(email,''))));
drop trigger if exists set_updated_at on public.clientes;
create trigger set_updated_at before update on public.clientes
  for each row execute function public.tg_set_updated_at();

create table if not exists public.contatos (
  id            uuid primary key default gen_random_uuid(),
  cliente_id    uuid not null references public.clientes(id) on delete cascade,
  nome          text not null,
  cargo         text,
  email         text,
  telefone      text,
  telefone_norm text generated always as (public.normaliza_telefone(telefone)) stored,
  whatsapp      text,
  principal     boolean not null default false,
  observacoes   text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists contatos_cliente_idx  on public.contatos(cliente_id);
create index if not exists contatos_telefone_idx on public.contatos(telefone_norm);
drop trigger if exists set_updated_at on public.contatos;
create trigger set_updated_at before update on public.contatos
  for each row execute function public.tg_set_updated_at();

-- ---------------------------------------------------------------------
-- 7. Funil de vendas
-- ---------------------------------------------------------------------
create table if not exists public.funis (
  id     uuid primary key default gen_random_uuid(),
  nome   text not null,
  ordem  int not null default 0,
  padrao boolean not null default false,
  ativo  boolean not null default true
);

create table if not exists public.etapas (
  id            uuid primary key default gen_random_uuid(),
  funil_id      uuid not null references public.funis(id) on delete cascade,
  nome          text not null,
  ordem         int not null default 0,
  probabilidade int not null default 0 check (probabilidade between 0 and 100),
  cor           text default '#94A3B8',
  tipo          tipo_etapa not null default 'aberta',
  unique (funil_id, nome)
);
create index if not exists etapas_funil_idx on public.etapas(funil_id, ordem);

create table if not exists public.oportunidades (
  id                  uuid primary key default gen_random_uuid(),
  titulo              text not null,
  cliente_id          uuid not null references public.clientes(id) on delete cascade,
  contato_id          uuid references public.contatos(id) on delete set null,
  funil_id            uuid not null references public.funis(id),
  etapa_id            uuid not null references public.etapas(id),
  valor               numeric(14,2) not null default 0,
  probabilidade       int not null default 0 check (probabilidade between 0 and 100),
  previsao_fechamento date,
  status              status_oportunidade not null default 'aberta',
  motivo_perda_id     int references public.motivos_perda(id) on delete set null,
  origem_id           int references public.origens(id) on delete set null,
  responsavel_id      uuid references public.profiles(id) on delete set null,
  ganha_em            timestamptz,
  perdida_em          timestamptz,
  ordem               int not null default 0,     -- posição no kanban
  observacoes         text,
  created_by          uuid references public.profiles(id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index if not exists oport_cliente_idx     on public.oportunidades(cliente_id);
create index if not exists oport_etapa_idx       on public.oportunidades(etapa_id, ordem);
create index if not exists oport_responsavel_idx on public.oportunidades(responsavel_id);
create index if not exists oport_status_idx      on public.oportunidades(status);
drop trigger if exists set_updated_at on public.oportunidades;
create trigger set_updated_at before update on public.oportunidades
  for each row execute function public.tg_set_updated_at();

-- Histórico de movimentação entre etapas (para relatório de conversão)
create table if not exists public.oportunidade_historico (
  id               bigserial primary key,
  oportunidade_id  uuid not null references public.oportunidades(id) on delete cascade,
  etapa_anterior   uuid references public.etapas(id) on delete set null,
  etapa_nova       uuid references public.etapas(id) on delete set null,
  status_anterior  status_oportunidade,
  status_novo      status_oportunidade,
  autor_id         uuid references public.profiles(id) on delete set null,
  criado_em        timestamptz not null default now()
);
create index if not exists oport_hist_idx on public.oportunidade_historico(oportunidade_id, criado_em desc);

create or replace function public.tg_oportunidade_historico()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (tg_op = 'UPDATE' and (new.etapa_id is distinct from old.etapa_id
                            or new.status is distinct from old.status)) then
    insert into public.oportunidade_historico
      (oportunidade_id, etapa_anterior, etapa_nova, status_anterior, status_novo, autor_id)
    values (new.id, old.etapa_id, new.etapa_id, old.status, new.status, auth.uid());

    if new.status = 'ganha' and old.status <> 'ganha' then new.ganha_em := now(); end if;
    if new.status = 'perdida' and old.status <> 'perdida' then new.perdida_em := now(); end if;
  end if;
  return new;
end $$;

drop trigger if exists oportunidade_historico on public.oportunidades;
create trigger oportunidade_historico before update on public.oportunidades
  for each row execute function public.tg_oportunidade_historico();

create table if not exists public.oportunidade_itens (
  id              uuid primary key default gen_random_uuid(),
  oportunidade_id uuid not null references public.oportunidades(id) on delete cascade,
  produto_id      uuid references public.produtos(id) on delete set null,
  descricao       text not null,
  quantidade      numeric(14,3) not null default 1,
  preco_unitario  numeric(14,2) not null default 0,
  desconto        numeric(14,2) not null default 0,
  total           numeric(14,2) generated always as (quantidade * preco_unitario - desconto) stored
);
create index if not exists oport_itens_idx on public.oportunidade_itens(oportunidade_id);

-- ---------------------------------------------------------------------
-- 8. Atividades, notas e anexos
-- ---------------------------------------------------------------------
create table if not exists public.atividades (
  id              uuid primary key default gen_random_uuid(),
  tipo            tipo_atividade not null default 'tarefa',
  titulo          text not null,
  descricao       text,
  cliente_id      uuid references public.clientes(id) on delete cascade,
  contato_id      uuid references public.contatos(id) on delete set null,
  oportunidade_id uuid references public.oportunidades(id) on delete cascade,
  responsavel_id  uuid references public.profiles(id) on delete set null,
  inicio          timestamptz,
  fim             timestamptz,
  concluida       boolean not null default false,
  concluida_em    timestamptz,
  created_by      uuid references public.profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists atividades_responsavel_idx on public.atividades(responsavel_id, concluida, inicio);
create index if not exists atividades_cliente_idx     on public.atividades(cliente_id);
create index if not exists atividades_oport_idx       on public.atividades(oportunidade_id);
drop trigger if exists set_updated_at on public.atividades;
create trigger set_updated_at before update on public.atividades
  for each row execute function public.tg_set_updated_at();

create table if not exists public.notas (
  id              uuid primary key default gen_random_uuid(),
  cliente_id      uuid references public.clientes(id) on delete cascade,
  oportunidade_id uuid references public.oportunidades(id) on delete cascade,
  texto           text not null,
  autor_id        uuid references public.profiles(id) on delete set null,
  created_at      timestamptz not null default now()
);
create index if not exists notas_cliente_idx on public.notas(cliente_id, created_at desc);
create index if not exists notas_oport_idx   on public.notas(oportunidade_id, created_at desc);

create table if not exists public.anexos (
  id              uuid primary key default gen_random_uuid(),
  cliente_id      uuid references public.clientes(id) on delete cascade,
  oportunidade_id uuid references public.oportunidades(id) on delete cascade,
  nome            text not null,
  caminho         text not null,           -- storage: bucket "anexos"
  mime            text,
  tamanho         bigint,
  autor_id        uuid references public.profiles(id) on delete set null,
  created_at      timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 9. TELEFONIA - ligação de entrada
-- ---------------------------------------------------------------------
create table if not exists public.chamadas (
  id                 uuid primary key default gen_random_uuid(),
  provedor           text not null default 'generico',   -- asterisk, 3cx, zenvia, twilio, evolution...
  id_externo         text,                               -- uniqueid/callsid do provedor
  direcao            direcao_chamada not null default 'entrada',
  status             status_chamada not null default 'tocando',
  numero_origem      text,
  numero_origem_norm text generated always as (public.normaliza_telefone(numero_origem)) stored,
  numero_destino     text,
  ramal              text,
  fila               text,
  cliente_id         uuid references public.clientes(id) on delete set null,
  contato_id         uuid references public.contatos(id) on delete set null,
  oportunidade_id    uuid references public.oportunidades(id) on delete set null,
  atendente_id       uuid references public.profiles(id) on delete set null,
  iniciada_em        timestamptz not null default now(),
  atendida_em        timestamptz,
  encerrada_em       timestamptz,
  espera_segundos    int generated always as (
                       case when atendida_em is not null
                         then greatest(0, extract(epoch from (atendida_em - iniciada_em))::int) end) stored,
  duracao_segundos   int generated always as (
                       case when atendida_em is not null and encerrada_em is not null
                         then greatest(0, extract(epoch from (encerrada_em - atendida_em))::int) end) stored,
  gravacao_url       text,
  transcricao        text,
  resumo             text,                   -- resumo gerado por IA, opcional
  motivo             text,                   -- porque não foi atendida, etc.
  observacoes        text,
  payload            jsonb not null default '{}'::jsonb,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create unique index if not exists chamadas_externo_uidx on public.chamadas(provedor, id_externo) where id_externo is not null;
create index if not exists chamadas_origem_idx     on public.chamadas(numero_origem_norm);
create index if not exists chamadas_cliente_idx    on public.chamadas(cliente_id, iniciada_em desc);
create index if not exists chamadas_atendente_idx  on public.chamadas(atendente_id, iniciada_em desc);
create index if not exists chamadas_abertas_idx    on public.chamadas(status) where status in ('tocando','em_atendimento');
drop trigger if exists set_updated_at on public.chamadas;
create trigger set_updated_at before update on public.chamadas
  for each row execute function public.tg_set_updated_at();

create table if not exists public.chamada_eventos (
  id          bigserial primary key,
  chamada_id  uuid not null references public.chamadas(id) on delete cascade,
  evento      text not null,               -- ringing, answered, hangup, transfer, recording
  ocorrido_em timestamptz not null default now(),
  payload     jsonb not null default '{}'::jsonb
);
create index if not exists chamada_eventos_idx on public.chamada_eventos(chamada_id, ocorrido_em);

-- Vincula automaticamente a chamada ao cliente/contato pelo telefone
create or replace function public.tg_chamada_vincula()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_cliente uuid; v_contato uuid; v_num text;
begin
  -- numero_origem_norm e coluna GENERATED: ainda nao esta preenchida num trigger BEFORE
  v_num := public.normaliza_telefone(new.numero_origem);

  if new.cliente_id is null and v_num is not null then
    select c.id into v_cliente from public.clientes c
      where c.telefone_norm = v_num
         or c.whatsapp_norm = v_num
      limit 1;

    if v_cliente is null then
      select ct.cliente_id, ct.id into v_cliente, v_contato
        from public.contatos ct
        where ct.telefone_norm = v_num
        limit 1;
    end if;

    new.cliente_id := v_cliente;
    new.contato_id := coalesce(new.contato_id, v_contato);
  end if;

  -- casa o ramal com o atendente
  if new.atendente_id is null and new.ramal is not null then
    select p.id into new.atendente_id from public.profiles p where p.ramal = new.ramal limit 1;
  end if;

  return new;
end $$;

drop trigger if exists chamada_vincula on public.chamadas;
create trigger chamada_vincula before insert or update of numero_origem, ramal on public.chamadas
  for each row execute function public.tg_chamada_vincula();

-- Registra a chamada na timeline como atividade concluída ao encerrar
create or replace function public.tg_chamada_atividade()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- só registra quando a ligação realmente encerrou, para a duração ficar certa
  if new.encerrada_em is not null and old.encerrada_em is null then
    insert into public.atividades
      (tipo, titulo, descricao, cliente_id, contato_id, oportunidade_id,
       responsavel_id, inicio, fim, concluida, concluida_em)
    values (
      'ligacao',
      case new.direcao when 'entrada' then 'Ligação recebida' else 'Ligação realizada' end
        || coalesce(' de ' || new.numero_origem, ''),
      coalesce(new.resumo, new.observacoes),
      new.cliente_id, new.contato_id, new.oportunidade_id,
      new.atendente_id, new.iniciada_em, new.encerrada_em,
      true, now()
    );
  end if;
  return new;
end $$;

drop trigger if exists chamada_atividade on public.chamadas;
create trigger chamada_atividade after update on public.chamadas
  for each row execute function public.tg_chamada_atividade();

-- Ponto único de entrada para o webhook da telefonia (upsert idempotente).
-- Chamar via PostgREST: POST /rest/v1/rpc/registrar_chamada
create or replace function public.registrar_chamada(
  p_provedor       text,
  p_id_externo     text,
  p_evento         text,                       -- ringing | answered | hangup
  p_direcao        direcao_chamada default 'entrada',
  p_numero_origem  text default null,
  p_numero_destino text default null,
  p_ramal          text default null,
  p_fila           text default null,
  p_gravacao_url   text default null,
  p_motivo         text default null,
  p_payload        jsonb default '{}'::jsonb
) returns public.chamadas
language plpgsql security definer set search_path = public as $$
declare v public.chamadas;
begin
  insert into public.chamadas as ch
    (provedor, id_externo, direcao, status, numero_origem, numero_destino, ramal, fila, payload)
  values
    (p_provedor, p_id_externo, p_direcao, 'tocando', p_numero_origem, p_numero_destino, p_ramal, p_fila, p_payload)
  on conflict (provedor, id_externo) where id_externo is not null
  do update set
    ramal          = coalesce(excluded.ramal, ch.ramal),
    numero_destino = coalesce(excluded.numero_destino, ch.numero_destino),
    payload        = ch.payload || excluded.payload
  returning * into v;

  update public.chamadas set
    status = case p_evento
               when 'answered' then 'atendida'::status_chamada
               when 'hangup'   then (case when atendida_em is not null
                                          then 'atendida'::status_chamada
                                          else 'perdida'::status_chamada end)
               else status end,
    atendida_em  = case when p_evento = 'answered' then coalesce(atendida_em, now()) else atendida_em end,
    encerrada_em = case when p_evento = 'hangup'   then coalesce(encerrada_em, now()) else encerrada_em end,
    gravacao_url = coalesce(p_gravacao_url, gravacao_url),
    motivo       = coalesce(p_motivo, motivo)
  where id = v.id
  returning * into v;

  insert into public.chamada_eventos (chamada_id, evento, payload)
  values (v.id, p_evento, p_payload);

  return v;
end $$;

revoke all on function public.registrar_chamada(text,text,text,direcao_chamada,text,text,text,text,text,text,jsonb) from public, anon;
grant execute on function public.registrar_chamada(text,text,text,direcao_chamada,text,text,text,text,text,text,jsonb) to authenticated, service_role;

-- ---------------------------------------------------------------------
-- 10. Views de apoio (dashboard)
-- ---------------------------------------------------------------------
create or replace view public.vw_funil_resumo as
select e.funil_id, e.id as etapa_id, e.nome as etapa, e.ordem,
       count(o.id) as qtd, coalesce(sum(o.valor),0) as valor_total
from public.etapas e
left join public.oportunidades o on o.etapa_id = e.id and o.status = 'aberta'
group by e.funil_id, e.id, e.nome, e.ordem;

create or replace view public.vw_chamadas_hoje as
select date_trunc('hour', iniciada_em) as hora,
       count(*) filter (where direcao='entrada')                   as entradas,
       count(*) filter (where status in ('perdida','nao_atendida')) as perdidas,
       round(avg(espera_segundos)) as espera_media_seg,
       round(avg(duracao_segundos)) as duracao_media_seg
from public.chamadas
where iniciada_em >= date_trunc('day', now() at time zone 'America/Sao_Paulo')
group by 1 order by 1;

-- Realtime do "liguin": publica a tabela de chamadas
do $$ begin
  alter publication supabase_realtime add table public.chamadas;
exception when duplicate_object then null; when undefined_object then null; end $$;
