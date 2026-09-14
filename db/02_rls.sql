-- =====================================================================
-- CRM AFATEC - Row Level Security (schema crm)
-- Rodar DEPOIS de 01_schema.sql
-- Nenhum grant ou revoke aqui toca o schema public.
-- Regra geral: equipe autenticada LÊ tudo; ESCREVE quem é dono ou gestor.
-- anon (chave pública sem login) não enxerga nada.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Helpers (security definer para não recair em RLS da própria profiles)
-- ---------------------------------------------------------------------
create or replace function crm.meu_papel()
returns crm.papel_usuario language sql stable security definer set search_path = crm, public as $$
  select papel from crm.profiles where id = auth.uid() and ativo
$$;

create or replace function crm.e_gestor()
returns boolean language sql stable security definer set search_path = crm, public as $$
  select coalesce((select papel in ('admin','gestor') from crm.profiles
                   where id = auth.uid() and ativo), false)
$$;

create or replace function crm.e_admin()
returns boolean language sql stable security definer set search_path = crm, public as $$
  select coalesce((select papel = 'admin' from crm.profiles
                   where id = auth.uid() and ativo), false)
$$;

grant execute on function crm.meu_papel(), crm.e_gestor(), crm.e_admin() to authenticated;

-- ---------------------------------------------------------------------
-- Liga RLS em tudo
-- ---------------------------------------------------------------------
alter table crm.profiles               enable row level security;
alter table crm.configuracoes          enable row level security;
alter table crm.origens                enable row level security;
alter table crm.motivos_perda          enable row level security;
alter table crm.produtos               enable row level security;
alter table crm.clientes               enable row level security;
alter table crm.contatos               enable row level security;
alter table crm.funis                  enable row level security;
alter table crm.etapas                 enable row level security;
alter table crm.oportunidades          enable row level security;
alter table crm.oportunidade_itens     enable row level security;
alter table crm.oportunidade_historico enable row level security;
alter table crm.atividades             enable row level security;
alter table crm.notas                  enable row level security;
alter table crm.anexos                 enable row level security;
alter table crm.chamadas               enable row level security;
alter table crm.chamada_eventos        enable row level security;

-- ---------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------
drop policy if exists profiles_select on crm.profiles;
create policy profiles_select on crm.profiles
  for select to authenticated using (true);

drop policy if exists profiles_update_self on crm.profiles;
create policy profiles_update_self on crm.profiles
  for update to authenticated
  using (id = auth.uid() or crm.e_admin())
  with check (id = auth.uid() or crm.e_admin());

drop policy if exists profiles_admin_all on crm.profiles;
create policy profiles_admin_all on crm.profiles
  for all to authenticated using (crm.e_admin()) with check (crm.e_admin());

-- Só admin muda papel de alguém (trava escalada de privilégio)
create or replace function crm.tg_protege_papel()
returns trigger language plpgsql security definer set search_path = crm, public as $$
begin
  -- auth.uid() nulo = SQL Editor / service_role / seed: deixa passar,
  -- senão não daria para promover o primeiro admin.
  if auth.uid() is null then
    return new;
  end if;
  if new.papel is distinct from old.papel and not crm.e_admin() then
    raise exception 'Somente administrador pode alterar o papel do usuário';
  end if;
  if new.ativo is distinct from old.ativo and not crm.e_admin() then
    raise exception 'Somente administrador pode ativar/desativar usuário';
  end if;
  return new;
end $$;
drop trigger if exists protege_papel on crm.profiles;
create trigger protege_papel before update on crm.profiles
  for each row execute function crm.tg_protege_papel();

-- ---------------------------------------------------------------------
-- configuracoes (logo, cores) - todos leem, admin escreve
-- ---------------------------------------------------------------------
drop policy if exists config_select on crm.configuracoes;
create policy config_select on crm.configuracoes
  for select to authenticated using (true);

drop policy if exists config_write on crm.configuracoes;
create policy config_write on crm.configuracoes
  for all to authenticated using (crm.e_admin()) with check (crm.e_admin());

-- ---------------------------------------------------------------------
-- Tabelas de apoio: leitura para todos, escrita para gestor+
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['origens','motivos_perda','produtos','funis','etapas'] loop
    execute format('drop policy if exists %1$s_select on crm.%1$s', t);
    execute format('create policy %1$s_select on crm.%1$s for select to authenticated using (true)', t);
    execute format('drop policy if exists %1$s_write on crm.%1$s', t);
    execute format('create policy %1$s_write on crm.%1$s for all to authenticated
                    using (crm.e_gestor()) with check (crm.e_gestor())', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- clientes
-- ---------------------------------------------------------------------
drop policy if exists clientes_select on crm.clientes;
create policy clientes_select on crm.clientes
  for select to authenticated using (true);

drop policy if exists clientes_insert on crm.clientes;
create policy clientes_insert on crm.clientes
  for insert to authenticated with check (auth.uid() is not null);

drop policy if exists clientes_update on crm.clientes;
create policy clientes_update on crm.clientes
  for update to authenticated
  using (crm.e_gestor() or responsavel_id = auth.uid() or created_by = auth.uid())
  with check (crm.e_gestor() or responsavel_id = auth.uid() or created_by = auth.uid());

drop policy if exists clientes_delete on crm.clientes;
create policy clientes_delete on crm.clientes
  for delete to authenticated using (crm.e_gestor());

-- ---------------------------------------------------------------------
-- contatos (segue o dono do cliente)
-- ---------------------------------------------------------------------
drop policy if exists contatos_select on crm.contatos;
create policy contatos_select on crm.contatos
  for select to authenticated using (true);

drop policy if exists contatos_write on crm.contatos;
create policy contatos_write on crm.contatos
  for all to authenticated
  using (crm.e_gestor() or exists (
          select 1 from crm.clientes c
          where c.id = contatos.cliente_id
            and (c.responsavel_id = auth.uid() or c.created_by = auth.uid())))
  with check (crm.e_gestor() or exists (
          select 1 from crm.clientes c
          where c.id = contatos.cliente_id
            and (c.responsavel_id = auth.uid() or c.created_by = auth.uid())));

-- ---------------------------------------------------------------------
-- oportunidades
-- ---------------------------------------------------------------------
drop policy if exists oport_select on crm.oportunidades;
create policy oport_select on crm.oportunidades
  for select to authenticated using (true);

drop policy if exists oport_insert on crm.oportunidades;
create policy oport_insert on crm.oportunidades
  for insert to authenticated with check (auth.uid() is not null);

drop policy if exists oport_update on crm.oportunidades;
create policy oport_update on crm.oportunidades
  for update to authenticated
  using (crm.e_gestor() or responsavel_id = auth.uid() or created_by = auth.uid())
  with check (crm.e_gestor() or responsavel_id = auth.uid() or created_by = auth.uid());

drop policy if exists oport_delete on crm.oportunidades;
create policy oport_delete on crm.oportunidades
  for delete to authenticated using (crm.e_gestor());

drop policy if exists oport_itens_select on crm.oportunidade_itens;
create policy oport_itens_select on crm.oportunidade_itens
  for select to authenticated using (true);

drop policy if exists oport_itens_write on crm.oportunidade_itens;
create policy oport_itens_write on crm.oportunidade_itens
  for all to authenticated
  using (crm.e_gestor() or exists (
          select 1 from crm.oportunidades o
          where o.id = oportunidade_itens.oportunidade_id
            and (o.responsavel_id = auth.uid() or o.created_by = auth.uid())))
  with check (crm.e_gestor() or exists (
          select 1 from crm.oportunidades o
          where o.id = oportunidade_itens.oportunidade_id
            and (o.responsavel_id = auth.uid() or o.created_by = auth.uid())));

drop policy if exists oport_hist_select on crm.oportunidade_historico;
create policy oport_hist_select on crm.oportunidade_historico
  for select to authenticated using (true);
-- histórico só é escrito pelo trigger (security definer), ninguém insere direto

-- ---------------------------------------------------------------------
-- atividades / notas / anexos
-- ---------------------------------------------------------------------
drop policy if exists atividades_select on crm.atividades;
create policy atividades_select on crm.atividades
  for select to authenticated using (true);

drop policy if exists atividades_insert on crm.atividades;
create policy atividades_insert on crm.atividades
  for insert to authenticated with check (auth.uid() is not null);

drop policy if exists atividades_update on crm.atividades;
create policy atividades_update on crm.atividades
  for update to authenticated
  using (crm.e_gestor() or responsavel_id = auth.uid() or created_by = auth.uid())
  with check (crm.e_gestor() or responsavel_id = auth.uid() or created_by = auth.uid());

drop policy if exists atividades_delete on crm.atividades;
create policy atividades_delete on crm.atividades
  for delete to authenticated
  using (crm.e_gestor() or created_by = auth.uid());

drop policy if exists notas_select on crm.notas;
create policy notas_select on crm.notas for select to authenticated using (true);

drop policy if exists notas_insert on crm.notas;
create policy notas_insert on crm.notas
  for insert to authenticated with check (autor_id = auth.uid());

drop policy if exists notas_update on crm.notas;
create policy notas_update on crm.notas
  for update to authenticated using (autor_id = auth.uid()) with check (autor_id = auth.uid());

drop policy if exists notas_delete on crm.notas;
create policy notas_delete on crm.notas
  for delete to authenticated using (autor_id = auth.uid() or crm.e_gestor());

drop policy if exists anexos_select on crm.anexos;
create policy anexos_select on crm.anexos for select to authenticated using (true);

drop policy if exists anexos_insert on crm.anexos;
create policy anexos_insert on crm.anexos
  for insert to authenticated with check (autor_id = auth.uid());

drop policy if exists anexos_delete on crm.anexos;
create policy anexos_delete on crm.anexos
  for delete to authenticated using (autor_id = auth.uid() or crm.e_gestor());

-- ---------------------------------------------------------------------
-- chamadas (o "liguin")
-- Escrita normal vem do webhook via service_role (ignora RLS).
-- O atendente pode complementar a ligação dele pelo app.
-- ---------------------------------------------------------------------
drop policy if exists chamadas_select on crm.chamadas;
create policy chamadas_select on crm.chamadas
  for select to authenticated using (true);

drop policy if exists chamadas_insert on crm.chamadas;
create policy chamadas_insert on crm.chamadas
  for insert to authenticated with check (auth.uid() is not null);

drop policy if exists chamadas_update on crm.chamadas;
create policy chamadas_update on crm.chamadas
  for update to authenticated
  using (crm.e_gestor() or atendente_id = auth.uid() or atendente_id is null)
  with check (crm.e_gestor() or atendente_id = auth.uid());

drop policy if exists chamadas_delete on crm.chamadas;
create policy chamadas_delete on crm.chamadas
  for delete to authenticated using (crm.e_admin());

drop policy if exists chamada_eventos_select on crm.chamada_eventos;
create policy chamada_eventos_select on crm.chamada_eventos
  for select to authenticated using (true);

-- ---------------------------------------------------------------------
-- Storage: bucket público da marca e bucket privado de anexos/gravações
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('crm-marca','crm-marca', true)
on conflict (id) do update set public = true;

insert into storage.buckets (id, name, public)
values ('crm-anexos','crm-anexos', false)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('crm-gravacoes','crm-gravacoes', false)
on conflict (id) do nothing;

drop policy if exists crm_marca_leitura_publica on storage.objects;
create policy crm_marca_leitura_publica on storage.objects
  for select to public using (bucket_id = 'crm-marca');

drop policy if exists crm_marca_admin_escreve on storage.objects;
create policy crm_marca_admin_escreve on storage.objects
  for all to authenticated
  using (bucket_id = 'crm-marca' and crm.e_admin())
  with check (bucket_id = 'crm-marca' and crm.e_admin());

drop policy if exists crm_anexos_equipe on storage.objects;
create policy crm_anexos_equipe on storage.objects
  for all to authenticated
  using (bucket_id in ('crm-anexos','crm-gravacoes'))
  with check (bucket_id in ('crm-anexos','crm-gravacoes'));

-- ---------------------------------------------------------------------
-- Grants de papel (o Supabase já faz por padrão; explicito para não faltar)
-- ---------------------------------------------------------------------
grant usage on schema crm to authenticated, service_role;
grant select, insert, update, delete on all tables in schema crm to authenticated;
grant usage, select on all sequences in schema crm to authenticated;
grant all on all tables in schema crm to service_role;
grant all on all sequences in schema crm to service_role;

alter default privileges in schema crm
  grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema crm
  grant usage, select on sequences to authenticated;

-- ---------------------------------------------------------------------
-- Tira qualquer acesso do papel anon
-- ---------------------------------------------------------------------
revoke all on all tables in schema crm from anon;
revoke all on all sequences in schema crm from anon;
revoke all on all functions in schema crm from anon;
