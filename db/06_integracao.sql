-- ---------------------------------------------------------------------
-- 06_integracao.sql
-- O que o Agente Express (afatec-agent-core) chama no CRM.
--
-- Tudo aqui vive no schema `crm`. Nada cria, altera ou revoga no schema
-- `public`, que neste Supabase pertence ao zapmax em producao.
--
-- O script e idempotente: pode rodar de novo sem quebrar nada.
--
-- Desenho em docs/INTEGRACAO-AGENTE-EXPRESS.md. A ideia e o agente fazer
-- UMA chamada HTTP por atendimento, e o banco resolver o resto — porque o
-- webhook do agente processa a mensagem de forma sincrona e uma chamada
-- lenta ao CRM nao pode atrasar a resposta ao cliente.
-- ---------------------------------------------------------------------

-- Marca de origem externa. E o que deixa a integracao reescrever a mesma
-- atividade em vez de criar uma linha por mensagem do WhatsApp.
alter table crm.atividades add column if not exists ref_externa text;

create unique index if not exists atividades_ref_externa_uidx
  on crm.atividades (ref_externa) where ref_externa is not null;


-- ---------------------------------------------------------------------
-- Oportunidade a partir do WhatsApp
--
-- Nao duplica: se o cliente ja tem oportunidade aberta, devolve aquela.
-- Sem isso o funil encheria de uma oportunidade por conversa.
-- ---------------------------------------------------------------------
create or replace function crm.abrir_oportunidade_whatsapp(
  p_cliente_id uuid,
  p_titulo     text default null,
  p_origem     text default 'WhatsApp'
) returns uuid
language plpgsql security definer set search_path = crm, public as $$
declare v_op uuid; v_funil uuid; v_etapa uuid; v_origem int; v_nome text;
begin
  if p_cliente_id is null then
    return null;
  end if;

  select o.id into v_op
    from crm.oportunidades o
   where o.cliente_id = p_cliente_id and o.status = 'aberta'
   order by o.created_at
   limit 1;

  if v_op is not null then
    return v_op;
  end if;

  select f.id into v_funil
    from crm.funis f
   where f.ativo
   order by f.padrao desc, f.ordem, f.nome
   limit 1;

  if v_funil is null then
    raise exception 'nenhum funil ativo no CRM';
  end if;

  select e.id into v_etapa
    from crm.etapas e
   where e.funil_id = v_funil and e.tipo = 'aberta'
   order by e.ordem
   limit 1;

  if v_etapa is null then
    raise exception 'o funil % nao tem etapa aberta', v_funil;
  end if;

  select o.id into v_origem from crm.origens o where o.nome = p_origem limit 1;
  select c.nome into v_nome from crm.clientes c where c.id = p_cliente_id;

  insert into crm.oportunidades (titulo, cliente_id, funil_id, etapa_id, origem_id)
  values (
    coalesce(nullif(trim(p_titulo), ''), 'WhatsApp — ' || coalesce(v_nome, 'novo contato')),
    p_cliente_id, v_funil, v_etapa, v_origem
  )
  returning id into v_op;

  return v_op;
end $$;


-- ---------------------------------------------------------------------
-- Ponto unico de entrada do agente: uma conversa de WhatsApp vira
-- cliente + atividade, e opcionalmente oportunidade.
--
-- Idempotente pela `ref`: sem ref, usa contato + dia, entao o agente nao
-- precisa guardar estado nenhum — chamar a cada mensagem so atualiza o
-- resumo da conversa do dia em vez de poluir a timeline.
-- ---------------------------------------------------------------------
create or replace function crm.registrar_atendimento_whatsapp(
  p_telefone           text,
  p_nome               text default null,
  p_resumo             text default null,
  p_agente             text default null,
  p_ref                text default null,
  p_abrir_oportunidade boolean default false
) returns jsonb
language plpgsql security definer set search_path = crm, public as $$
declare v_cliente uuid; v_ativ uuid; v_op uuid; v_ref text; v_titulo text; v_novo boolean;
begin
  v_cliente := crm.upsert_cliente_whatsapp(p_telefone, p_nome, 'WhatsApp');

  if v_cliente is null then
    raise exception 'telefone invalido: %', coalesce(p_telefone, '(nulo)');
  end if;

  v_novo := not exists (
    select 1 from crm.atividades a
     where a.cliente_id = v_cliente and a.tipo = 'whatsapp'
  );

  v_ref := coalesce(
    nullif(trim(p_ref), ''),
    'wa:' || crm.chave_telefone(p_telefone) || ':'
      || to_char((now() at time zone 'America/Sao_Paulo')::date, 'YYYY-MM-DD')
  );

  v_titulo := 'WhatsApp' || coalesce(' — ' || nullif(trim(p_agente), ''), '');

  insert into crm.atividades as a
    (tipo, titulo, descricao, cliente_id, inicio, fim, concluida, concluida_em, ref_externa)
  values
    ('whatsapp', v_titulo, nullif(trim(p_resumo), ''), v_cliente, now(), now(), true, now(), v_ref)
  on conflict (ref_externa) where ref_externa is not null do update set
    titulo     = excluded.titulo,
    descricao  = coalesce(excluded.descricao, a.descricao),
    fim        = now(),
    updated_at = now()
  returning a.id into v_ativ;

  if p_abrir_oportunidade then
    v_op := crm.abrir_oportunidade_whatsapp(v_cliente, null, 'WhatsApp');
    update crm.atividades set oportunidade_id = v_op where id = v_ativ;
  end if;

  return jsonb_build_object(
    'cliente_id',     v_cliente,
    'cliente_novo',   v_novo,
    'atividade_id',   v_ativ,
    'oportunidade_id', v_op,
    'ref',            v_ref
  );
end $$;


-- ---------------------------------------------------------------------
-- Chamada de voz do WhatsApp.
--
-- A Evolution avisa que entrou uma chamada, mas nao existe endpoint para
-- atende-la. Entao ela entra ja encerrada, como nao atendida, e o que
-- sobra de util e a tarefa de retornar — que e criada aqui em aberto, de
-- proposito: uma atividade ja concluida nao cobra ninguem.
-- ---------------------------------------------------------------------
create or replace function crm.registrar_chamada_whatsapp(
  p_id_externo text,
  p_telefone   text,
  p_nome       text default null,
  p_payload    jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path = crm, public as $$
declare v_cliente uuid; v_chamada uuid;
begin
  v_cliente := crm.upsert_cliente_whatsapp(p_telefone, p_nome, 'WhatsApp');

  insert into crm.chamadas as ch
    (provedor, id_externo, direcao, status, numero_origem, fila, cliente_id,
     encerrada_em, motivo, payload)
  values
    ('evolution', p_id_externo, 'entrada', 'nao_atendida', p_telefone, 'whatsapp', v_cliente,
     now(), 'Chamada de WhatsApp: a API nao permite atender', p_payload)
  on conflict (provedor, id_externo) where id_externo is not null
  do update set payload = ch.payload || excluded.payload
  returning ch.id into v_chamada;

  insert into crm.atividades
    (tipo, titulo, descricao, cliente_id, inicio, concluida, ref_externa)
  values
    ('tarefa',
     'Retornar chamada de WhatsApp de ' || p_telefone,
     'O contato tentou ligar pelo WhatsApp e nao ha como atender pela API.',
     v_cliente, now(), false, 'wacall:' || p_id_externo)
  on conflict (ref_externa) where ref_externa is not null do nothing;

  return jsonb_build_object('cliente_id', v_cliente, 'chamada_id', v_chamada);
end $$;


-- ---------------------------------------------------------------------
-- Permissoes: so o service_role (o agente, servidor a servidor). O anon
-- e a chave que vai no navegador — nada disso pode ficar aberto para ela.
-- ---------------------------------------------------------------------
revoke all on function crm.abrir_oportunidade_whatsapp(uuid,text,text)                    from public, anon;
revoke all on function crm.registrar_atendimento_whatsapp(text,text,text,text,text,boolean) from public, anon;
revoke all on function crm.registrar_chamada_whatsapp(text,text,text,jsonb)               from public, anon;

grant execute on function crm.abrir_oportunidade_whatsapp(uuid,text,text)                    to service_role;
grant execute on function crm.registrar_atendimento_whatsapp(text,text,text,text,text,boolean) to service_role;
grant execute on function crm.registrar_chamada_whatsapp(text,text,text,jsonb)               to service_role;
