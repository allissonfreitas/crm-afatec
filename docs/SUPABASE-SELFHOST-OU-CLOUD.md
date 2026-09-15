# O CRM novo pode usar o Supabase da VPS?

Apurado em 15/09/2026, lendo o `supabase/baseline.sql` do DeskcommCRM v1.27.2 (25.043 linhas)
e o código do app.

## Resposta curta

**Tecnicamente dá, e eu fui rápido demais ao descartar.** Duas coisas que escrevi no roteiro
estavam erradas, e é justo corrigir:

| O que eu disse | O que o código mostra |
|---|---|
| "Exige PostgreSQL 17" | **Falso.** Não há exigência de versão. O CI do próprio projeto roda contra **Postgres 15**. O seu `supabase-db` (15.8) serve. |
| "As migrations quebram o `public` do zapmax" | **Exagerado.** O baseline **não emite nenhum `revoke` em `public`** — os únicos revokes são no schema `private`, que é dele. Os grants em `public` são aditivos (`grant usage ... to anon/authenticated`), os mesmos que qualquer projeto Supabase já tem. Nada do zapmax é rebaixado. |

O que continua **verdade**:

- O app **não tem como mudar de schema**. O cliente Supabase é criado sem a opção
  `db: { schema }`, e o baseline traz **3.517 referências literais a `public.`** e funções
  `security definer set search_path = public`. Não é um sed — seria um fork de 25 mil linhas,
  refeito a cada atualização.
- Então usar o Supabase da VPS significa: **94 tabelas novas, 183 policies, um schema
  `private` e a extensão `vector` entrando no mesmo `public` onde o zapmax roda em produção.**
- E o kit instala um **cron que roda `update.sh` sozinho**, aplicando migrations novas nesse
  banco sem ninguém olhando. É o ponto que mais me preocupa: hoje não há colisão, mas quem
  garante a migration do mês que vem?

## O teste que decide (5 segundos)

Nenhum dos nomes óbvios colide (`profiles`, `users`, `messages`, `contacts`, `settings`,
`clientes`, `logs`, `sessions`) e os nomes do DeskcommCRM são bem prefixados (`ai_`, `crm_`,
`calendar_`, `channel_`, `automation_`, `ad_`). Mas dá para **provar** em vez de supor. No
Supabase da VPS:

```sql
select table_name
  from information_schema.tables
 where table_schema = 'public'
   and table_name in (
  'ad_conversion_dispatches',
  'ad_insights_connections',
  'ad_platform_connections',
  'agent_case_events',
  'agent_cases',
  'agent_inbox_items',
  'ai_purpose_bindings',
  'ai_reply_drafts',
  'ai_router_decisions',
  'ai_router_members',
  'ai_routers',
  'appointment_recovery_receipts',
  'attendant_availability',
  'automation_rule_runs',
  'automation_rules',
  'before_send_traces',
  'calendar_appointments',
  'calendar_availability_exceptions',
  'calendar_connection_calendars',
  'calendar_connections',
  'calendar_event_types',
  'calendar_external_events',
  'calendar_oauth_nonces',
  'catalog_products',
  'channel_connection_requests',
  'channel_knobs',
  'channel_routing_policies',
  'channel_routing_responsibles',
  'channel_session_health',
  'contact_field_proposals',
  'conversation_assignment_events',
  'conversation_notes',
  'crm_lead_reactivations',
  'crm_lead_risk_states',
  'crm_lead_scores',
  'crm_tasks',
  'cron_jobs',
  'demanda_conversas',
  'demandas',
  'disclosure_template_pointers',
  'disclosure_template_versions',
  'event_service_origins',
  'flywheel_distiller_proposals',
  'flywheel_judge_verdicts',
  'followup_enrollment_events',
  'followup_enrollments',
  'followup_flow_pointers',
  'followup_flow_versions',
  'if',
  'job_queue',
  'judge_alignment_pool',
  'knowledge_searches',
  'lead_checkpoints',
  'lead_notes',
  'lead_state',
  'lead_state_transitions',
  'llm_calls',
  'message_templates',
  'meta_templates',
  'metrics',
  'org_guardrail_layers',
  'org_memory_entries',
  'org_memory_pointers',
  'org_memory_versions',
  'org_voice_calls',
  'outbound_copies',
  'pacing_ledger',
  'platform_branding',
  'platform_google_oauth',
  'platform_meta_app',
  'platform_settings',
  'platform_support_sessions',
  'playbook_pointers',
  'playbook_versions',
  'private',
  'promise_table_pointers',
  'promise_table_versions',
  'public',
  'push_subscriptions',
  'reentry_knob_pointers',
  'reentry_knob_versions',
  'reentry_template_pointers',
  'reentry_template_versions',
  'send_ledger',
  'skill_activations',
  'skill_pointers',
  'skill_versions',
  'system_update_runs',
  'system_version',
  'team_invites',
  'voice_calls',
  'watchdog_cursors',
  'webhook_lead_captures',
  'webhook_sources'
 );
```

**Zero linhas = nenhuma colisão de nome.** Qualquer linha que voltar é uma tabela do zapmax
que o baseline do CRM tentaria criar por cima.

> Ele também **não cria gatilho em `auth.users`** — diferente do que o CRM antigo precisou.
> Um usuário do zapmax que logasse no CRM cairia sem organização e sem acesso (o modelo dele
> é org + membership, e só 2 das 183 policies são `using (true)`).

## O que o app exige do Supabase

Não serve um Postgres pelado: ele usa **Auth (inclusive MFA), Storage** (bucket
`whatsapp-media`), **Realtime** (12 arquivos com `postgres_changes`) e **RLS**. O próprio
projeto avisa que, contra um Postgres comum, "auth/storage viram stubs e o login não funciona".

## Os três caminhos, com o custo real

### A — Supabase Cloud, plano grátis *(o que está no roteiro hoje)*
- **A favor:** é o caminho suportado pelo kit, backup gerenciado, zero RAM na VPS, zero risco
  para o zapmax.
- **Contra:** conta nova, **500 MB de banco**, o projeto **hiberna após 7 dias sem tráfego**,
  e os dados do CRM saem da sua infraestrutura.

### B — O Supabase da VPS, junto com o zapmax
- **A favor:** nada novo para subir, zero RAM extra, sem limite de tamanho, é hoje.
- **Contra:** dois apps dividindo o `public`, e um cron aplicando migrations de terceiros,
  sozinho, no banco que atende produção. Se um dia colidir, colide com o zapmax no ar.
- **Só faz sentido se** a consulta acima devolver zero linhas — e mesmo assim eu desligaria o
  cron de auto-update e passaria a atualizar na mão.

### C — Um segundo Supabase self-hosted na VPS *(recomendo)*
Um compose próprio para o CRM: Postgres + GoTrue + PostgREST + Storage + Realtime + Kong, em
outro subdomínio, isolado do zapmax.
- **A favor:** tudo continua na sua VPS, de graça, **sem conta nova**, sem limite de 500 MB,
  sem hibernação, e o `public` do CRM é dele — o zapmax não é tocado nem por engano. O
  `auth.users` também deixa de ser compartilhado.
- **Contra:** é o único que exige montar alguma coisa. Custo de RAM estimado em **~1 a 1,5 GB**
  (o seu `supabase-auth` roda com 20 MB; o peso está no Kong e no Realtime). Com 8,3 Gi
  livres e ~2,8 GB do DeskcommCRM, sobra folga. Também não é coberto pelo kit: a instalação
  passa a ser o caminho manual do `docs/deploy-selfhost/README.md`, com as credenciais do
  Supabase novo em vez das do Cloud.

## Recomendação

**C**, porque é o único que entrega o que você quer — tudo na VPS, de graça, sem conta nova —
sem pendurar um app de terceiros no banco que atende o zapmax em produção. **B** é aceitável
se a consulta de colisão vier vazia e você aceitar atualizar o CRM na mão. **A** continua
sendo o caminho mais curto se a pressa falar mais alto.
