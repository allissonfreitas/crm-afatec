-- ---------------------------------------------------------------------
-- 07_papel_integracao.sql  (opcional, recomendado)
--
-- Cria um papel proprio para o Agente Express falar com o CRM, em vez de
-- entregar a `service_role` a ele.
--
-- Por que: a `service_role` ignora RLS e enxerga o Postgres inteiro — o
-- zapmax, o ianews, o carrossel, o afatecpay, o auth.users de todo mundo.
-- Se algum dia ela vazar do agente, vaza tudo. O papel abaixo so consegue
-- executar tres funcoes do schema `crm` e mais nada.
--
-- Como usar: o token do agente deixa de ser a service_role e passa a ser
-- um JWT assinado com o mesmo JWT_SECRET do Supabase, com o claim
-- {"role": "crm_integracao"}. O PostgREST le esse claim e entra no banco
-- com este papel.
--
-- Idempotente. Nao altera nada no schema `public`.
-- ---------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'crm_integracao') then
    create role crm_integracao nologin noinherit;
  end if;
end $$;

-- o PostgREST entra como `authenticator` e troca de papel conforme o JWT;
-- sem este grant ele nao consegue assumir o papel novo
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticator') then
    execute 'grant crm_integracao to authenticator';
  end if;
end $$;

-- o minimo: ver o schema e executar as tres funcoes de integracao.
-- Nenhum select, insert, update ou delete direto em tabela.
grant usage on schema crm to crm_integracao;

grant execute on function crm.registrar_atendimento_whatsapp(text,text,text,text,text,boolean) to crm_integracao;
grant execute on function crm.registrar_chamada_whatsapp(text,text,text,jsonb)                 to crm_integracao;
grant execute on function crm.abrir_oportunidade_whatsapp(uuid,text,text)                      to crm_integracao;

-- garantia explicita de que nao ha porta lateral
revoke all on all tables    in schema crm from crm_integracao;
revoke all on all sequences in schema crm from crm_integracao;
