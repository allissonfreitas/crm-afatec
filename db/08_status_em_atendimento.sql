-- ---------------------------------------------------------------------
-- 08_status_em_atendimento.sql
--
-- Conserta o mapa de status de crm.registrar_chamada.
--
-- Antes: `answered` gravava direto `atendida`, e o enum `em_atendimento`
-- nunca era usado. Como o pop-up so fica na tela enquanto a chamada esta
-- `tocando` ou `em_atendimento`, atender fazia o card sumir — exatamente
-- quando o atendente mais precisa dele na frente.
--
-- Depois: `answered` grava `em_atendimento` e `hangup` fecha em
-- `atendida`. O card acompanha a ligacao do toque ao desligar, e
-- `atendida` volta a significar o que o nome diz: acabou e foi atendida.
--
-- `duracao_segundos` e `espera_segundos` nao mudam: sao colunas geradas a
-- partir de atendida_em / encerrada_em, nao do status.
--
-- Idempotente. So substitui a funcao; nao mexe em tabela nem no schema
-- public.
-- ---------------------------------------------------------------------

create or replace function crm.registrar_chamada(
  p_provedor       text,
  p_id_externo     text,
  p_evento         text,                       -- ringing | answered | hangup
  p_direcao        crm.direcao_chamada default 'entrada',
  p_numero_origem  text default null,
  p_numero_destino text default null,
  p_ramal          text default null,
  p_fila           text default null,
  p_gravacao_url   text default null,
  p_motivo         text default null,
  p_payload        jsonb default '{}'::jsonb
) returns crm.chamadas
language plpgsql security definer set search_path = crm, public as $$
declare v crm.chamadas;
begin
  insert into crm.chamadas as ch
    (provedor, id_externo, direcao, status, numero_origem, numero_destino, ramal, fila, payload)
  values
    (p_provedor, p_id_externo, p_direcao, 'tocando', p_numero_origem, p_numero_destino, p_ramal, p_fila, p_payload)
  on conflict (provedor, id_externo) where id_externo is not null
  do update set
    ramal          = coalesce(excluded.ramal, ch.ramal),
    numero_destino = coalesce(excluded.numero_destino, ch.numero_destino),
    payload        = ch.payload || excluded.payload
  returning * into v;

  update crm.chamadas set
    status = case p_evento
               -- em curso: o pop-up continua na tela ate desligar
               when 'answered' then 'em_atendimento'::crm.status_chamada
               when 'hangup'   then (case when atendida_em is not null
                                          then 'atendida'::crm.status_chamada
                                          else 'perdida'::crm.status_chamada end)
               else status end,
    atendida_em  = case when p_evento = 'answered' then coalesce(atendida_em, now()) else atendida_em end,
    encerrada_em = case when p_evento = 'hangup'   then coalesce(encerrada_em, now()) else encerrada_em end,
    gravacao_url = coalesce(p_gravacao_url, gravacao_url),
    motivo       = coalesce(p_motivo, motivo)
  where id = v.id
  returning * into v;

  insert into crm.chamada_eventos (chamada_id, evento, payload)
  values (v.id, p_evento, p_payload);

  return v;
end $$;

revoke all on function crm.registrar_chamada(text,text,text,crm.direcao_chamada,text,text,text,text,text,text,jsonb) from public, anon;
grant execute on function crm.registrar_chamada(text,text,text,crm.direcao_chamada,text,text,text,text,text,text,jsonb) to authenticated, service_role;
