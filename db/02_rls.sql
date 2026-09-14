-- =====================================================================
-- CRM AFATEC - Row Level Security
-- Rodar DEPOIS de 01_schema.sql
-- Regra geral: equipe autenticada LÊ tudo; ESCREVE quem é dono ou gestor.
-- anon (chave pública sem login) não enxerga nada.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Helpers (security definer para não recair em RLS da própria profiles)
-- ---------------------------------------------------------------------
create or replace function public.meu_papel()
returns papel_usuario language sql stable security definer set search_path = public as $$
  select papel from public.profiles where id = auth.uid() and ativo
$$;

create or replace function public.e_gestor()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select papel in ('admin','gestor') from public.profiles
                   where id = auth.uid() and ativo), false)
$$;

create or replace function public.e_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select papel = 'admin' from public.profiles
                   where id = auth.uid() and ativo), false)
$$;

grant execute on function public.meu_papel(), public.e_gestor(), public.e_admin() to authenticated;

-- ---------------------------------------------------------------------
-- Liga RLS em tudo
-- ---------------------------------------------------------------------
alter table public.profiles               enable row level security;
alter table public.configuracoes          enable row level security;
alter table public.origens                enable row level security;
alter table public.motivos_perda          enable row level security;
alter table public.produtos               enable row level security;
alter table public.clientes               enable row level security;
alter table public.contatos               enable row level security;
alter table public.funis                  enable row level security;
alter table public.etapas                 enable row level security;
alter table public.oportunidades          enable row level security;
alter table public.oportunidade_itens     enable row level security;
alter table public.oportunidade_historico enable row level security;
alter table public.atividades             enable row level security;
alter table public.notas                  enable row level security;
alter table public.anexos                 enable row level security;
alter table public.chamadas               enable row level security;
alter table public.chamada_eventos        enable row level security;

-- ---------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated using (true);

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid() or public.e_admin())
  with check (id = auth.uid() or public.e_admin());

drop policy if exists profiles_admin_all on public.profiles;
create policy profiles_admin_all on public.profiles
  for all to authenticated using (public.e_admin()) with check (public.e_admin());

-- Só admin muda papel de alguém (trava escalada de privilégio)
create or replace function public.tg_protege_papel()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- auth.uid() nulo = SQL Editor / service_role / seed: deixa passar,
  -- senão não daria para promover o primeiro admin.
  if auth.uid() is null then
    return new;
  end if;
  if new.papel is distinct from old.papel and not public.e_admin() then
    raise exception 'Somente administrador pode alterar o papel do usuário';
  end if;
  if new.ativo is distinct from old.ativo and not public.e_admin() then
    raise exception 'Somente administrador pode ativar/desativar usuário';
  end if;
  return new;
end $$;
drop trigger if exists protege_papel on public.profiles;
create trigger protege_papel before update on public.profiles
  for each row execute function public.tg_protege_papel();

-- ---------------------------------------------------------------------
-- configuracoes (logo, cores) - todos leem, admin escreve
-- ---------------------------------------------------------------------
drop policy if exists config_select on public.configuracoes;
create policy config_select on public.configuracoes
  for select to authenticated using (true);

drop policy if exists config_write on public.configuracoes;
create policy config_write on public.configuracoes
  for all to authenticated using (public.e_admin()) with check (public.e_admin());

-- ---------------------------------------------------------------------
-- Tabelas de apoio: leitura para todos, escrita para gestor+
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['origens','motivos_perda','produtos','funis','etapas'] loop
    execute format('drop policy if exists %1$s_select on public.%1$s', t);
    execute format('create policy %1$s_select on public.%1$s for select to authenticated using (true)', t);
    execute format('drop policy if exists %1$s_write on public.%1$s', t);
    execute format('create policy %1$s_write on public.%1$s for all to authenticated
                    using (public.e_gestor()) with check (public.e_gestor())', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- clientes
-- ---------------------------------------------------------------------
drop policy if exists clientes_select on public.clientes;
create policy clientes_select on public.clientes
  for select to authenticated using (true);

drop policy if exists clientes_insert on public.clientes;
create policy clientes_insert on public.clientes
  for insert to authenticated with check (auth.uid() is not null);

drop policy if exists clientes_update on public.clientes;
create policy clientes_update on public.clientes
  for update to authenticated
  using (public.e_gestor() or responsavel_id = auth.uid() or created_by = auth.uid())
  with check (public.e_gestor() or responsavel_id = auth.uid() or created_by = auth.uid());

drop policy if exists clientes_delete on public.clientes;
create policy clientes_delete on public.clientes
  for delete to authenticated using (public.e_gestor());

-- ---------------------------------------------------------------------
-- contatos (segue o dono do cliente)
-- ---------------------------------------------------------------------
drop policy if exists contatos_select on public.contatos;
create policy contatos_select on public.contatos
  for select to authenticated using (true);

drop policy if exists contatos_write on public.contatos;
create policy contatos_write on public.contatos
  for all to authenticated
  using (public.e_gestor() or exists (
          select 1 from public.clientes c
          where c.id = contatos.cliente_id
            and (c.responsavel_id = auth.uid() or c.created_by = auth.uid())))
  with check (public.e_gestor() or exists (
          select 1 from public.clientes c
          where c.id = contatos.cliente_id
            and (c.responsavel_id = auth.uid() or c.created_by = auth.uid())));

-- ---------------------------------------------------------------------
-- oportunidades
-- ---------------------------------------------------------------------
drop policy if exists oport_select on public.oportunidades;
create policy oport_select on public.oportunidades
  for select to authenticated using (true);

drop policy if exists oport_insert on public.oportunidades;
create policy oport_insert on public.oportunidades
  for insert to authenticated with check (auth.uid() is not null);

drop policy if exists oport_update on public.oportunidades;
create policy oport_update on public.oportunidades
  for update to authenticated
  using (public.e_gestor() or responsavel_id = auth.uid() or created_by = auth.uid())
  with check (public.e_gestor() or responsavel_id = auth.uid() or created_by = auth.uid());

drop policy if exists oport_delete on public.oportunidades;
create policy oport_delete on public.oportunidades
  for delete to authenticated using (public.e_gestor());

drop policy if exists oport_itens_select on public.oportunidade_itens;
create policy oport_itens_select on public.oportunidade_itens
  for select to authenticated using (true);

drop policy if exists oport_itens_write on public.oportunidade_itens;
create policy oport_itens_write on public.oportunidade_itens
  for all to authenticated
  using (public.e_gestor() or exists (
          select 1 from public.oportunidades o
          where o.id = oportunidade_itens.oportunidade_id
            and (o.responsavel_id = auth.uid() or o.created_by = auth.uid())))
  with check (public.e_gestor() or exists (
          select 1 from public.oportunidades o
          where o.id = oportunidade_itens.oportunidade_id
            and (o.responsavel_id = auth.uid() or o.created_by = auth.uid())));

drop policy if exists oport_hist_select on public.oportunidade_historico;
create policy oport_hist_select on public.oportunidade_historico
  for select to authenticated using (true);
-- histórico só é escrito pelo trigger (security definer), ninguém insere direto

-- ---------------------------------------------------------------------
-- atividades / notas / anexos
-- ---------------------------------------------------------------------
drop policy if exists atividades_select on public.atividades;
create policy atividades_select on public.atividades
  for select to authenticated using (true);

drop policy if exists atividades_insert on public.atividades;
create policy atividades_insert on public.atividades
  for insert to authenticated with check (auth.uid() is not null);

drop policy if exists atividades_update on public.atividades;
create policy atividades_update on public.atividades
  for update to authenticated
  using (public.e_gestor() or responsavel_id = auth.uid() or created_by = auth.uid())
  with check (public.e_gestor() or responsavel_id = auth.uid() or created_by = auth.uid());

drop policy if exists atividades_delete on public.atividades;
create policy atividades_delete on public.atividades
  for delete to authenticated
  using (public.e_gestor() or created_by = auth.uid());

drop policy if exists notas_select on public.notas;
create policy notas_select on public.notas for select to authenticated using (true);

drop policy if exists notas_insert on public.notas;
create policy notas_insert on public.notas
  for insert to authenticated with check (autor_id = auth.uid());

drop policy if exists notas_update on public.notas;
create policy notas_update on public.notas
  for update to authenticated using (autor_id = auth.uid()) with check (autor_id = auth.uid());

drop policy if exists notas_delete on public.notas;
create policy notas_delete on public.notas
  for delete to authenticated using (autor_id = auth.uid() or public.e_gestor());

drop policy if exists anexos_select on public.anexos;
create policy anexos_select on public.anexos for select to authenticated using (true);

drop policy if exists anexos_insert on public.anexos;
create policy anexos_insert on public.anexos
  for insert to authenticated with check (autor_id = auth.uid());

drop policy if exists anexos_delete on public.anexos;
create policy anexos_delete on public.anexos
  for delete to authenticated using (autor_id = auth.uid() or public.e_gestor());

-- ---------------------------------------------------------------------
-- chamadas (o "liguin")
-- Escrita normal vem do webhook via service_role (ignora RLS).
-- O atendente pode complementar a ligação dele pelo app.
-- ---------------------------------------------------------------------
drop policy if exists chamadas_select on public.chamadas;
create policy chamadas_select on public.chamadas
  for select to authenticated using (true);

drop policy if exists chamadas_insert on public.chamadas;
create policy chamadas_insert on public.chamadas
  for insert to authenticated with check (auth.uid() is not null);

drop policy if exists chamadas_update on public.chamadas;
create policy chamadas_update on public.chamadas
  for update to authenticated
  using (public.e_gestor() or atendente_id = auth.uid() or atendente_id is null)
  with check (public.e_gestor() or atendente_id = auth.uid());

drop policy if exists chamadas_delete on public.chamadas;
create policy chamadas_delete on public.chamadas
  for delete to authenticated using (public.e_admin());

drop policy if exists chamada_eventos_select on public.chamada_eventos;
create policy chamada_eventos_select on public.chamada_eventos
  for select to authenticated using (true);

-- ---------------------------------------------------------------------
-- Storage: bucket público da marca e bucket privado de anexos/gravações
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('marca','marca', true)
on conflict (id) do update set public = true;

insert into storage.buckets (id, name, public)
values ('anexos','anexos', false)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('gravacoes','gravacoes', false)
on conflict (id) do nothing;

drop policy if exists marca_leitura_publica on storage.objects;
create policy marca_leitura_publica on storage.objects
  for select to public using (bucket_id = 'marca');

drop policy if exists marca_admin_escreve on storage.objects;
create policy marca_admin_escreve on storage.objects
  for all to authenticated
  using (bucket_id = 'marca' and public.e_admin())
  with check (bucket_id = 'marca' and public.e_admin());

drop policy if exists anexos_equipe on storage.objects;
create policy anexos_equipe on storage.objects
  for all to authenticated
  using (bucket_id in ('anexos','gravacoes'))
  with check (bucket_id in ('anexos','gravacoes'));

-- ---------------------------------------------------------------------
-- Grants de papel (o Supabase já faz por padrão; explicito para não faltar)
-- ---------------------------------------------------------------------
grant usage on schema public to authenticated, service_role;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;

alter default privileges in schema public
  grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public
  grant usage, select on sequences to authenticated;

-- ---------------------------------------------------------------------
-- Tira qualquer acesso do papel anon
-- ---------------------------------------------------------------------
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke all on all functions in schema public from anon;
