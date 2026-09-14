-- =====================================================================
-- CRM AFATEC - Trava de acesso ao CRM
-- Rodar DEPOIS de 04_telefone_chave.sql. Idempotente.
--
-- PROBLEMA QUE ISTO CORRIGE
-- O auth.users deste Supabase é compartilhado por vários aplicativos.
-- As políticas originais do CRM liberavam leitura para qualquer sessão
-- autenticada (`using (true)`), e crm.profiles nascia com ativo = true.
-- Resultado: um cadastro novo em QUALQUER outro app do mesmo Supabase
-- entrava no CRM e enxergava a carteira de clientes inteira.
--
-- Agora só entra quem tem linha ATIVA em crm.profiles, e a linha nasce
-- inativa: o administrador libera quem é da equipe.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Quem tem acesso ao CRM
-- ---------------------------------------------------------------------
create or replace function crm.tem_acesso()
returns boolean language sql stable security definer set search_path = crm, public as $$
  select exists (
    select 1 from crm.profiles
     where id = auth.uid() and ativo
  )
$$;

revoke all on function crm.tem_acesso() from public, anon;
grant execute on function crm.tem_acesso() to authenticated, service_role;

-- ---------------------------------------------------------------------
-- 2. Profile novo nasce INATIVO
--    (quem já está ativo hoje continua ativo — nada é revogado aqui)
-- ---------------------------------------------------------------------
alter table crm.profiles alter column ativo set default false;

-- ---------------------------------------------------------------------
-- 3. Toda leitura passa a exigir acesso ao CRM
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  -- tabelas cuja policy de select era `using (true)`
  foreach t in array array[
    'profiles','configuracoes','origens','motivos_perda','produtos','funis','etapas',
    'clientes','contatos','oportunidades','oportunidade_itens','oportunidade_historico',
    'atividades','notas','anexos','chamadas','chamada_eventos'
  ] loop
    execute format('drop policy if exists %1$s_select on crm.%1$s', t);
    execute format(
      'create policy %1$s_select on crm.%1$s for select to authenticated using (crm.tem_acesso())', t);
  end loop;
end $$;

-- os nomes que fogem do padrão <tabela>_select
drop policy if exists config_select on crm.configuracoes;
drop policy if exists oport_select on crm.oportunidades;
drop policy if exists oport_itens_select on crm.oportunidade_itens;
drop policy if exists oport_hist_select on crm.oportunidade_historico;

-- ---------------------------------------------------------------------
-- 4. Toda escrita também
-- ---------------------------------------------------------------------
drop policy if exists clientes_insert on crm.clientes;
create policy clientes_insert on crm.clientes
  for insert to authenticated with check (crm.tem_acesso());

drop policy if exists oport_insert on crm.oportunidades;
create policy oport_insert on crm.oportunidades
  for insert to authenticated with check (crm.tem_acesso());

drop policy if exists atividades_insert on crm.atividades;
create policy atividades_insert on crm.atividades
  for insert to authenticated with check (crm.tem_acesso());

drop policy if exists chamadas_insert on crm.chamadas;
create policy chamadas_insert on crm.chamadas
  for insert to authenticated with check (crm.tem_acesso());

drop policy if exists notas_insert on crm.notas;
create policy notas_insert on crm.notas
  for insert to authenticated with check (crm.tem_acesso() and autor_id = auth.uid());

drop policy if exists anexos_insert on crm.anexos;
create policy anexos_insert on crm.anexos
  for insert to authenticated with check (crm.tem_acesso() and autor_id = auth.uid());

-- profiles: cada um edita o seu, admin edita todos, e só quem é do CRM
drop policy if exists profiles_update_self on crm.profiles;
create policy profiles_update_self on crm.profiles
  for update to authenticated
  using (crm.tem_acesso() and (id = auth.uid() or crm.e_admin()))
  with check (crm.tem_acesso() and (id = auth.uid() or crm.e_admin()));

-- ---------------------------------------------------------------------
-- 5. Storage: anexos e gravações só para a equipe do CRM
--    (crm-marca continua público: é a logo na tela de login)
-- ---------------------------------------------------------------------
drop policy if exists crm_anexos_equipe on storage.objects;
create policy crm_anexos_equipe on storage.objects
  for all to authenticated
  using (bucket_id in ('crm-anexos','crm-gravacoes') and crm.tem_acesso())
  with check (bucket_id in ('crm-anexos','crm-gravacoes') and crm.tem_acesso());

-- ---------------------------------------------------------------------
-- 6. Conferência
-- ---------------------------------------------------------------------
-- Quem está ativo no CRM hoje:
--   select nome, email, papel, ativo from crm.profiles order by ativo desc, nome;
-- Para liberar alguém da equipe:
--   update crm.profiles set ativo = true, papel = 'vendedor' where email = 'fulano@afatec.net';
