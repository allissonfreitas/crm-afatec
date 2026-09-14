-- =====================================================================
-- CRM AFATEC - Chave de telefone tolerante ao nono dígito
-- Rodar DEPOIS de 03_seed.sql. Pode rodar num banco que já tem os
-- arquivos 01 a 03 aplicados: tudo aqui é idempotente.
--
-- Motivo: o WhatsApp entrega o número no JID sem garantia do nono dígito
-- (5531988887777 e 553188887777 são a mesma pessoa), e a central de
-- telefonia entrega no formato dela. Comparar string exata criaria dois
-- clientes para o mesmo contato. A chave abaixo colapsa as variações.
-- =====================================================================

-- Formato da chave: 55 + DDD + número SEM o nono dígito (celular BR).
-- Números de fora do Brasil ficam só com os dígitos, sem alteração.
create or replace function crm.chave_telefone(p text)
returns text language plpgsql immutable strict parallel safe as $$
declare d text; ddd text; resto text;
begin
  d := regexp_replace(p, '\D', '', 'g');
  if d = '' then
    return null;
  end if;

  -- número digitado sem DDI: assume Brasil
  if length(d) in (10, 11) then
    d := '55' || d;
  end if;

  -- Brasil: 55 + DDD(2) + 8 ou 9 dígitos
  if left(d, 2) = '55' and length(d) in (12, 13) then
    ddd   := substr(d, 3, 2);
    resto := substr(d, 5);
    -- celular novo (9 dígitos comecando em 9) vira o formato antigo de 8
    if length(resto) = 9 and left(resto, 1) = '9' then
      resto := substr(resto, 2);
    end if;
    return '55' || ddd || resto;
  end if;

  return d;
end $$;

grant execute on function crm.chave_telefone(text) to authenticated, service_role;

-- ---------------------------------------------------------------------
-- Colunas de chave
-- ---------------------------------------------------------------------
alter table crm.clientes
  add column if not exists telefone_chave text
    generated always as (crm.chave_telefone(telefone)) stored,
  add column if not exists whatsapp_chave text
    generated always as (crm.chave_telefone(whatsapp)) stored;

alter table crm.contatos
  add column if not exists telefone_chave text
    generated always as (crm.chave_telefone(telefone)) stored;

alter table crm.chamadas
  add column if not exists origem_chave text
    generated always as (crm.chave_telefone(numero_origem)) stored;

create index if not exists clientes_tel_chave_idx  on crm.clientes(telefone_chave);
create index if not exists clientes_zap_chave_idx  on crm.clientes(whatsapp_chave);
create index if not exists contatos_tel_chave_idx  on crm.contatos(telefone_chave);
create index if not exists chamadas_origem_chave_idx on crm.chamadas(origem_chave);

-- ---------------------------------------------------------------------
-- O vínculo da chamada passa a usar a chave
-- ---------------------------------------------------------------------
create or replace function crm.tg_chamada_vincula()
returns trigger language plpgsql security definer set search_path = crm, public as $$
declare v_cliente uuid; v_contato uuid; v_chave text;
begin
  -- as colunas GENERATED ainda não existem num trigger BEFORE
  v_chave := crm.chave_telefone(new.numero_origem);

  if new.cliente_id is null and v_chave is not null then
    select c.id into v_cliente from crm.clientes c
      where c.telefone_chave = v_chave
         or c.whatsapp_chave = v_chave
      limit 1;

    if v_cliente is null then
      select ct.cliente_id, ct.id into v_cliente, v_contato
        from crm.contatos ct
        where ct.telefone_chave = v_chave
        limit 1;
    end if;

    new.cliente_id := v_cliente;
    new.contato_id := coalesce(new.contato_id, v_contato);
  end if;

  if new.atendente_id is null and new.ramal is not null then
    select p.id into new.atendente_id from crm.profiles p where p.ramal = new.ramal limit 1;
  end if;

  return new;
end $$;

-- ---------------------------------------------------------------------
-- Busca de cliente por telefone, para quem integra de fora (Agente Express)
-- ---------------------------------------------------------------------
create or replace function crm.cliente_por_telefone(p_telefone text)
returns uuid language sql stable security definer set search_path = crm, public as $$
  select c.id from crm.clientes c
   where c.telefone_chave = crm.chave_telefone(p_telefone)
      or c.whatsapp_chave = crm.chave_telefone(p_telefone)
   limit 1
$$;

-- Cria o cliente se ainda não existir, e devolve o id nos dois casos.
-- Idempotente: pode ser chamada a cada mensagem que chega no WhatsApp.
create or replace function crm.upsert_cliente_whatsapp(
  p_telefone text,
  p_nome     text default null,
  p_origem   text default 'WhatsApp'
) returns uuid language plpgsql security definer set search_path = crm, public as $$
declare v_id uuid; v_origem int;
begin
  if p_telefone is null or crm.chave_telefone(p_telefone) is null then
    return null;
  end if;

  v_id := crm.cliente_por_telefone(p_telefone);
  if v_id is not null then
    -- contato já conhecido: só completa o WhatsApp se estava vazio
    update crm.clientes
       set whatsapp = coalesce(whatsapp, p_telefone)
     where id = v_id;
    return v_id;
  end if;

  select id into v_origem from crm.origens where nome = p_origem limit 1;

  insert into crm.clientes (tipo, nome, telefone, whatsapp, status, origem_id)
  values ('pf',
          coalesce(nullif(trim(p_nome), ''), 'Lead WhatsApp ' || p_telefone),
          p_telefone, p_telefone, 'lead', v_origem)
  returning id into v_id;

  return v_id;
end $$;

revoke all on function crm.cliente_por_telefone(text)               from public, anon;
revoke all on function crm.upsert_cliente_whatsapp(text,text,text)  from public, anon;
grant execute on function crm.cliente_por_telefone(text)              to authenticated, service_role;
grant execute on function crm.upsert_cliente_whatsapp(text,text,text) to authenticated, service_role;
