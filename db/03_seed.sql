-- =====================================================================
-- CRM AFATEC - Dados iniciais
-- Rodar DEPOIS de 02_rls.sql
-- =====================================================================

-- Identidade da empresa (ajuste os dados e a URL da logo depois do upload)
insert into public.configuracoes (id, nome_empresa, cor_primaria, cor_secundaria)
values (1, 'Afatec', '#0090FE', '#001026')
on conflict (id) do nothing;

-- Origens de lead
insert into public.origens (nome) values
  ('Ligação recebida'), ('WhatsApp'), ('Site'), ('Instagram'),
  ('Indicação'), ('Google'), ('Visita'), ('Outro')
on conflict (nome) do nothing;

-- Motivos de perda
insert into public.motivos_perda (nome) values
  ('Preço'), ('Prazo'), ('Concorrente'), ('Sem verba'),
  ('Sem resposta'), ('Fora do perfil'), ('Desistiu')
on conflict (nome) do nothing;

-- Funil padrão + etapas
do $$
declare v_funil uuid;
begin
  select id into v_funil from public.funis where padrao limit 1;
  if v_funil is null then
    insert into public.funis (nome, ordem, padrao, ativo)
    values ('Comercial Afatec', 0, true, true)
    returning id into v_funil;
  end if;

  insert into public.etapas (funil_id, nome, ordem, probabilidade, cor, tipo) values
    (v_funil, 'Novo lead',        0, 10,  '#94A3B8', 'aberta'),
    (v_funil, 'Contato feito',    1, 25,  '#38BDF8', 'aberta'),
    (v_funil, 'Qualificado',      2, 40,  '#818CF8', 'aberta'),
    (v_funil, 'Proposta enviada', 3, 60,  '#FBBF24', 'aberta'),
    (v_funil, 'Negociação',       4, 80,  '#FB923C', 'aberta'),
    (v_funil, 'Ganho',            5, 100, '#22C55E', 'ganho'),
    (v_funil, 'Perdido',          6, 0,   '#EF4444', 'perdido')
  on conflict (funil_id, nome) do nothing;
end $$;

-- Depois de criar o primeiro usuário no Auth, promova a admin:
--   update public.profiles set papel = 'admin' where email = 'seu@email.com';
