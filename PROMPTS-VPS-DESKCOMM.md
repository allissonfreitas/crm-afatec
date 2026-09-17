# Subir o DeskcommCRM na VPS, com a marca Afatec

Roteiro escrito em 15/09/2026 para o **Claude Code do Allisson**, que alcança a VPS por SSH.
Baseado no DeskcommCRM **v1.28.0** (`melgarafael/DeskcommCRM`, MIT), lido commit a commit,
e no que já está de pé na VPS da Afatec.

> **Revisão de 15/09/2026, depois do Bloco 0.** O diagnóstico rodou e mudou três coisas:
> o Traefik do EasyPanel **não** roda em modo host (é serviço Swarm em bridge, na overlay
> `easypanel`), os entrypoints dele se chamam **`http` e `https`** (não `web`/`websecure`),
> e o acesso é **SSH não-interativo** — então o Bloco 3 foi reescrito para o modo `--yes`,
> com o `.env` preenchido antes. O Bloco 0 virou registro do que foi apurado.

> **Para o Allisson, antes de colar:** cada bloco abaixo é autocontido e tem como conferir
> que deu certo. Cole um de cada vez, na ordem, e só siga para o próximo quando a
> verificação passar. O **Bloco 0 é um diagnóstico** — ele pode dizer que a VPS não
> aguenta, e aí é melhor saber antes de instalar do que depois.

## Decisões já tomadas, e por quê

| Decisão | Por quê |
|---|---|
| **Banco: o Supabase self-hosted que já está na VPS** | Decidido em 16/09/2026, depois que o Allisson liberou o zapmax (não usa mais; vai rodar local). Com o `public` livre, o CRM fica na VPS, de graça, sem conta nova, sem os 500 MB e sem hibernação do plano grátis, e sem o custo de RAM de um segundo Supabase. **Nada do zapmax é apagado** — ver o Bloco 2. |
| **Nome do produto: `AfatecCRM`** | Decidido em 16/09/2026. Uma palavra só, sem espaço. Entra em `APP_NAME` no `.env` (variável de runtime, sobrevive a atualização de imagem) e derruba o logotipo do produto de origem em toda tela — ver o Bloco 4, que lista o que isso cobre e os três resíduos em código. |
| **Domínio `crm.afatec.net`** | O CRM atual continua no ar em `crm-afatec.gddktt.easypanel.host` até você aprovar o novo. Nada é desligado nesta instalação. |
| **Proxy: o Traefik do EasyPanel** | O app é publicado por ele, por label, na overlay `easypanel` (que é `attachable=true`). O Caddy do kit fica num profile desligado. Ninguém encosta no Traefik do EasyPanel. |
| **WAHA com número NOVO** | O WhatsApp só aceita um pareamento por número. O chip do Agente Express está na Evolution API — parear o mesmo número no WAHA **derruba a Evolution**. |
| **IA fica para depois** | O CRM sobe sem chave. Você cadastra pela tela depois (IA › Credenciais), e o OpenRouter tem modelos gratuitos. |
| **Chamada de voz (WaCalls) DESLIGADA** | Vincula um segundo aparelho ao número por caminho não oficial — risco de banimento da conta. Nasce desligada e fica assim. |

---

## Bloco 0 — Diagnóstico ✅ FEITO em 15/09/2026

Rodado por SSH, só leitura. **Veredito: a VPS aguenta, com folga.**

| Item | Situação |
|---|---|
| RAM | 15 Gi total · 7,3 Gi usada · **8,3 Gi disponíveis** |
| Swap | **já existe**: `/swapfile`, 4 GB |
| Disco `/` | 193 G total · **120 G livres** |
| Docker | 29.2.1 · Compose v5.0.2 · 50 contêineres no ar |
| Pico teórico do DeskcommCRM | ~2,8 GB → sobrariam ~5,5 Gi |

O que o diagnóstico achou sobre o proxy, e que muda o Bloco 3:

- O Traefik é um **serviço Swarm** (`easypanel-traefik`, `traefik:3.6.7`), em
  **bridge**, ligado à overlay **`easypanel`** (IP 10.11.0.24). **Não** é modo host.
- As portas 80/443 saem publicadas em `PublishMode: host` — por isso o `ss` mostra
  `docker-proxy` e não o Traefik direto.
- A rede `easypanel` é `Driver=overlay Scope=swarm` **`Attachable=true`**: um contêiner de
  docker-compose comum pode entrar nela. É o que a integração por label precisa.
- Os entrypoints se chamam **`http`** (:80) e **`https`** (:443), **não** `web`/`websecure`.
  O certresolver é `letsencrypt`.
- `TRAEFIK_PROVIDERS_DOCKER=true` com `EXPOSEDBYDEFAULT=false`: labels são lidas, e nada
  dos apps atuais é afetado, porque só sobe quem tiver `traefik.enable=true`.

> **Plano B conhecido**, se a rota por label der atrito com o Swarm: todos os apps standalone
> da VPS (crm-afatec, zapmax, carousel, financeiro) já são roteados pelo **file provider**,
> com um YAML em `/etc/easypanel/traefik/config/` apontando para `http://172.17.0.1:<porta>/`.
> É o caminho validado nesta casa. Ver o **Bloco 3-B** no fim deste arquivo.

---

## Bloco 1 — DNS do `crm.afatec.net` ✅ APROVADO em 15/09/2026

**Resolvido.** O registro A foi corrigido e o AAAA sumiu junto com a nuvem laranja. O que
estava errado, para registro: o `crm.afatec.net` estava com o proxy laranja ligado —
o A responde `104.21.43.197` e `172.67.184.173` (Cloudflare), existe um AAAA do Cloudflare,
e um GET devolve 404 com `server: cloudflare`. Comparação útil: o `n8nafatec.afatec.net`
resolve para `76.13.98.43`, direto na VPS. É esse o padrão que o `crm` precisa seguir.

**O que fazer no painel do Cloudflare** (é ação sua, não do agente):

1. Registro **A** de `crm` → **`76.13.98.43`**, com a **nuvem cinza (DNS only)**. Com a
   laranja, o Let's Encrypt não valida e o HTTPS nunca é emitido.
2. **Cuide do AAAA.** O Let's Encrypt **prefere IPv6 quando existe registro AAAA**. Se o A
   ficar cinza mas sobrar um AAAA apontando para o Cloudflare, o desafio HTTP-01 sai por
   IPv6, não chega no Traefik e o certificado falha — com sintoma confuso, porque pelo
   navegador em IPv4 tudo parece certo. Esse AAAA provavelmente é gerado pelo próprio
   proxy e some com a nuvem cinza, mas **confirme**: depois da mudança o AAAA tem que vir
   **vazio**, ou apontar para **`2a02:4780:4:e059::1`**, que é o IPv6 desta VPS (o Traefik
   já escuta em `[::]:80` e `[::]:443`, então funcionaria).

Depois, no agente:

```
Confira se o DNS do CRM novo já aponta para esta VPS:

  dig +short A    crm.afatec.net
  dig +short AAAA crm.afatec.net
  curl -4 -s ifconfig.me ; echo

Critério:
  - o A tem que devolver exatamente o mesmo IP do curl -4 (76.13.98.43)
  - o AAAA tem que vir VAZIO, ou 2a02:4780:4:e059::1 (o IPv6 desta VPS)
  - se o A devolver 104.x, 172.67.x ou 188.114.x, o proxy laranja ainda está ligado

⚠️ Use `dig +short A` e `curl -4`, com as duas flags. Esta VPS tem IPv6 (faixa Hostinger)
e o curl prefere IPv6 quando existe: sem o -4 ele devolve 2a02:4780:4:e059::1, que nunca
vai bater com o registro A, e a verificação reprova um DNS que já está certo.

Confirme também que o Traefik responde pelo domínio antes de o CRM existir:

  curl -4 -sS -o /dev/null -D- -m 15 http://crm.afatec.net/ | head -8

Esperado: **301 para https**, e NENHUM header "server: cloudflare" — é o redirect padrão do
Traefik do EasyPanel, o mesmo dos outros apps dele. Em https o domínio vai devolver **404
com um certificado autoassinado `CN=Easypanel`**, e isso também é o certo agora: o tráfego
chega no Traefik, mas ainda não existe router para este Host. O Bloco 3 é que registra o
router, e o Let's Encrypt emite o certificado de verdade.
```

**Como saber que deu certo:** o A devolve `76.13.98.43`, o AAAA vem vazio ou com o IPv6
da VPS, e o `http://crm.afatec.net/` responde 301 sem `server: cloudflare`.

✅ **Aprovado em 15/09/2026**: A em `76.13.98.43`, AAAA vazio, 301 pelo Traefik do EasyPanel.

---

## Bloco 2 — Preparar o Supabase da VPS ✅ CONCLUÍDO em 16/09/2026

O CRM vai usar o Supabase que já está de pé (`supb.afatec.net`, API em
`zapmaxapi.afatec.net`), no schema `public`, que ficou livre com a saída do zapmax.

**Nada do zapmax é apagado neste bloco.** As tabelas dele ficam onde estão, inertes, até
você ter o zapmax rodando no Docker local e decidir o que fazer com elas. A única escrita
destrutiva aqui é **um `drop trigger`**, e ele é salvo antes.

> ⚠️ **Os outros apps continuam vivos.** `ianews`, `carrossel` e `afatecpay` moram nos
> próprios schemas e não são tocados por nada aqui — mas o `auth.users` é **compartilhado**
> com eles. Nada neste bloco pode mexer em `auth`, `storage` ou nos schemas deles.

```
Vamos preparar o Supabase self-hosted da VPS para receber o DeskcommCRM. Regras:

  - NÃO apague nenhuma tabela, de nenhum schema. Nada de drop table, drop schema, truncate.
  - NÃO toque nos schemas ianews, carrossel e afatecpay, nem em auth e storage (o
    auth.users é compartilhado por todos eles).
  - Toda escrita deste bloco é: 1 drop trigger (com a definição salva antes) e
    3 create extension. Mais nada.
  - Rode o psql pelo container do banco:
      docker exec -i supabase-db psql -U postgres -d postgres -v ON_ERROR_STOP=1

PASSO 1 — Prova de colisão (só leitura).

⛔ **ESTE PASSO ESTAVA ERRADO E DEU FALSO NEGATIVO.** A lista de 94 nomes abaixo não veio
do `baseline.sql`; o baseline cria **38 tabelas**, todas com `CREATE TABLE IF NOT EXISTS`,
e **`contacts`, `conversations` e `messages` não estavam na lista** — justamente as três
que colidem com o zapmax. Por isso a prova devolveu 0 linhas e a instalação quebrou no
PASSO 4 do Bloco 3. A forma correta de derivar a lista é do próprio arquivo, e está no
**Bloco 2-C**. A lista abaixo fica só como registro do erro.

Consulta original (não use):

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

  ZERO linhas = caminho livre, siga. Qualquer linha que voltar é uma tabela do zapmax que
  o baseline criaria por cima (o "create table if not exists" NÃO erra — ele pula, e o CRM
  passa a usar a tabela errada em silêncio). Se voltar alguma, PARE e me mostre.

  Mostre também o inventário atual, para ficar registrado:

    select count(*) from information_schema.tables where table_schema='public';
    select tablename from pg_tables where schemaname='public' order by 1;

PASSO 2 — Dump de segurança do zapmax, antes de qualquer escrita. Nada é apagado; isto é
para você poder levar o zapmax para o Docker local depois:

    mkdir -p /opt/backups
    docker exec supabase-db pg_dump -U postgres -d postgres --schema=public \
      > /opt/backups/zapmax-public-$(date +%F).sql
    ls -lh /opt/backups/

  Confirme que o arquivo tem tamanho > 0 antes de seguir.

PASSO 3 — O gatilho do zapmax em auth.users. Ele dispara a cada usuário novo, inclusive os
do CRM, e escreve em public.profiles (tabela do zapmax). Primeiro me MOSTRE o que existe:

    select tgname, pg_get_triggerdef(oid)
      from pg_trigger
     where tgrelid = 'auth.users'::regclass and not tgisinternal;

  Salve a saída inteira em /opt/backups/triggers-auth-users-$(date +%F).sql — é o que
  permite desfazer. Depois remova SÓ o do zapmax:

    drop trigger if exists on_auth_user_created on auth.users;

  ⚠️ NÃO remova on_auth_user_created_crm, ianews_on_auth_user_created,
  on_auth_user_created_carrossel nem qualquer outro. Se o nome do gatilho do zapmax na
  saída acima for diferente do que escrevi, PARE e me pergunte antes.

  Confirme rodando a consulta de novo: os outros gatilhos têm que continuar lá.

PASSO 4 — Extensões que o baseline usa, em public (aditivo, não mexe em nada existente):

    create extension if not exists vector   with schema public;
    create extension if not exists citext   with schema public;
    create extension if not exists pg_trgm  with schema public;
    select extname from pg_extension order by 1;

PASSO 5 — Conectividade. ⚠️ ESTE PASSO TEM DUAS ARMADILHAS, as duas confirmadas na VPS
em 16/09/2026:

  (1) O `supabase-db` NÃO publica porta nenhuma no host, e vive numa rede própria
      (172.19.0.9). Um container do bridge padrão não alcança esse IP — testado.
  (2) Existe um **PostgreSQL 16 NATIVO do host** ouvindo na 5432, que NÃO é o Supabase.
      Ele recusa a autenticação vinda de contêiner (`no pg_hba.conf entry for host`), então
      o estrago não seria dado silencioso — seria uma falha de autenticação confusa,
      apontando para o servidor errado. Armadilha de diagnóstico, não de perda de dados.

  Por que isso importa: o instalador roda o psql assim, SEM --network —

      docker run --rm postgres:17-alpine psql "$SUPABASE_DB_URL"

  — e o mesmo vale para update.sh, backup.sh e restore.sh, que usam a mesma função
  `psql_run` do `_common.sh`. Então a string precisa funcionar a partir do bridge padrão.

  A saída escolhida é uma **ponte TCP dedicada**, e não publicar porta no supabase-db.
  Motivo: publicar porta exige RECRIAR o container do banco, o que derruba por alguns
  segundos o ianews, o carrossel e o afatecpay — e mexe na stack compartilhada do Supabase,
  que o EasyPanel pode gerenciar. A ponte é aditiva, não encosta no banco e sai com um
  `docker rm -f`.

  1. Descubra a rede do supabase-db e confirme que a 5433 está livre:

       docker inspect supabase-db --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}'
       ss -tlnp | grep ':5433 ' ; echo "(vazio = livre)"

  2. Suba a ponte, trocando <REDE> pelo nome que saiu acima:

       docker run -d --name supabase-db-bridge --restart unless-stopped \
         --network <REDE> -p 172.17.0.1:5433:5433 alpine/socat \
         tcp-listen:5433,fork,reuseaddr tcp-connect:supabase-db:5432

     O bind é em 172.17.0.1 de propósito: é a interface docker0, alcançável por qualquer
     container e pelo host, e NÃO exposta à internet. Nunca use 0.0.0.0 aqui.

  3. Pegue a senha do Postgres do próprio ambiente do container (não me mande a senha):

       docker inspect supabase-db --format '{{range .Config.Env}}{{println .}}{{end}}' \
         | grep '^POSTGRES_PASSWORD='

  4. **PROVE que a string cai no banco certo.** Este teste é obrigatório — é ele que
     separa o Supabase do PostgreSQL 16 nativo do host:

       docker run --rm postgres:17-alpine psql \
         "postgresql://postgres:SENHA@172.17.0.1:5433/postgres" -tAc \
         "select current_setting('server_version'), current_database(), (select count(*) from auth.users)"

     Esperado: versão **15.x** (o Supabase), o banco `postgres`, e a contagem de
     `auth.users` respondendo um número. Se vier **16.x**, ou se `auth.users` não existir,
     você está no Postgres nativo do host — PARE, não rode mais nada, e me avise.

     ⚠️ Não mexa no PostgreSQL 16 nativo do host. Ele não é nosso; só não usamos a 5432.

  5. Me diga que a prova passou. Essa string vai em SUPABASE_DB_URL e em
     SUPABASE_DB_ADMIN_URL no Bloco 3 (em Supabase próprio o guia manda preencher as duas).

PASSO 6 — GoTrue: liberar o endereço de retorno do CRM. Num Supabase self-hosted isso é
variável de ambiente do container de auth, não tela do Studio. Me MOSTRE antes de mudar:

    docker inspect supabase-auth --format '{{range .Config.Env}}{{println .}}{{end}}' \
      | grep -E 'SITE_URL|URI_ALLOW_LIST'

  ⚠️ NÃO troque o GOTRUE_SITE_URL: ele é compartilhado com ianews, carrossel e afatecpay, e
  trocá-lo quebraria os e-mails deles. O que precisamos é ACRESCENTAR o endereço do CRM ao
  GOTRUE_URI_ALLOW_LIST, mantendo os que já estão lá:

    https://crm.afatec.net,https://crm.afatec.net/auth/confirm

  Me mostre o valor atual e o novo que você propõe, e espere eu confirmar antes de aplicar
  e reiniciar o container de auth.
```

**Como saber que deu certo:** zero colisões, dump guardado em `/opt/backups/`, só o gatilho
do zapmax removido (os outros intactos), as 3 extensões criadas, uma connection string que
conecta de um container avulso, e o endereço do CRM na allow list do GoTrue.

### ✅ Resultado real, 16/09/2026

| Passo | Resultado |
|---|---|
| 1 — Colisão | **0 linhas — resultado INVÁLIDO**, a lista de nomes estava errada. A colisão real é `contacts`, `conversations`, `messages`. Ver Bloco 2-C |
| 2 — Dump | `/opt/backups/zapmax-public-2026-09-16.sql`, 101 KB, íntegro |
| 3 — Gatilho | Só o `on_auth_user_created` removido; os 3 outros intactos |
| 4 — Extensões | `vector`, `citext`, `pg_trgm` criadas em `public` |
| 5 — Ponte + prova | `supabase-db-bridge` no ar; prova devolveu **`15.8 | postgres | 4`** |
| 6 — GoTrue | **Nada a fazer**: `https://crm.afatec.net/**` já estava na allow list |

Duas observações que vieram da execução e valem guardar:

- A ponte ficou **mais durável** do que publicar a porta teria ficado: o `socat` resolve
  `supabase-db` por DNS **a cada conexão**, então recriar o contêiner do banco com outro IP
  não a quebra. Com `--restart unless-stopped`, ela volta depois de reboot.
- O `supabase-auth` **não foi reiniciado** — reiniciá-lo derrubaria o login do ianews,
  carrossel e afatecpay por alguns segundos, sem ganho nenhum.
- Ponta solta conhecida: o glob `https://crm.afatec.net/**` pode não casar com a URL **sem**
  barra final. O DeskcommCRM usa `/auth/confirm`, que está coberto; se algum fluxo usar a
  raiz exata, aí sim vale acrescentá-la (com reinício do auth).

---

## Bloco 2-C — Limpar o `public` e reinstalar ⚠️ NECESSÁRIO em 16/09/2026

**O que aconteceu.** O `install.sh` morreu no `baseline.sql:1401`, num
`COMMENT ON CONSTRAINT "conversations_status_check"`. Causa: o baseline usa
`CREATE TABLE IF NOT EXISTS` nas 38 tabelas dele; o zapmax já tinha uma
`public.conversations`, então o `CREATE` foi pulado **em silêncio** e o `COMMENT` na linha
seguinte não achou a constraint. O `public` ficou com 43 tabelas — as 26 do zapmax mais 17
do baseline — e nenhum contêiner subiu.

**Por que o Bloco 2 não pegou isso:** a lista de 94 nomes do PASSO 1 não foi extraída do
`baseline.sql`. O baseline cria exatamente **38** tabelas, e `contacts`, `conversations` e
`messages` **não estavam** na lista conferida. A prova devolveu 0 porque perguntou pelos
nomes errados.

**Números corretos, medidos no `supabase/baseline.sql` da v1.28.0:** 38 tabelas (todas
`CREATE TABLE IF NOT EXISTS`), 38 funções (todas `CREATE OR REPLACE`), 1 view
(`OR REPLACE`), 33 triggers, 49 policies, 111 índices, 0 `CREATE TYPE`, 0
`CREATE EXTENSION` (as extensões quem cria é o instalador, dentro do `public`; somadas à
`unaccent` que o CRM antigo já usava, são quatro). Isso importa para o
replanejamento: funções e view são reexecutáveis, **tabelas, triggers e policies não** — um
segundo `install.sh` sobre o estado atual quebraria de novo, agora num `CREATE POLICY`.

### O caminho escolhido: derrubar as TABELAS do `public`, não o schema

`drop schema public cascade` é a opção errada aqui, por duas razões concretas:

1. Levaria junto as **quatro** extensões que moram no `public` — `citext`, `pg_trgm`,
   `vector` e `unaccent` — e o `cascade` não para nelas. A `unaccent` é o caso concreto:
   o CRM antigo tem `crm.f_unaccent`, que chama `public.unaccent`; com a extensão fora,
   a busca sem acento do CRM em produção para de funcionar. (Medido na VPS em
   17/09/2026; a lista de três que eu escrevi antes estava incompleta.)
2. Perderia o dono e os grants que o Supabase espera no `public`
   (`owner pg_database_owner`, os `ALTER DEFAULT PRIVILEGES`), e restaurá-los à mão é outro
   lugar para errar.

Derrubar só as tabelas resolve o mesmo problema sem nenhum dos dois riscos. E como você
liberou o zapmax, derrubamos **as 43**, deixando o `public` sem tabela nenhuma — assim o
baseline roda num terreno limpo e nenhuma colisão de nome pode se repetir numa atualização
futura.

```
O install.sh quebrou no baseline e o public ficou num estado misto. Vamos limpar e
reinstalar. As regras de sempre continuam valendo (não encostar no Traefik do EasyPanel,
no n8n, na Evolution API, nem no CRM antigo em /opt/crm-afatec).

PASSO 1 — Dump NOVO do estado atual, por cima do que já existe em /opt/backups:

  docker exec supabase-db pg_dump -U postgres -d postgres --schema=public \
    > /opt/backups/public-pos-baseline-parcial-$(date +%Y%m%d-%H%M).sql
  ls -lh /opt/backups/ | tail -5

  Confira que o arquivo novo tem tamanho maior que zero antes de seguir.

PASSO 2 — Levantar as dependências de OUTROS schemas sobre o public. Só leitura, e é
o passo que decide se dá para limpar. Rode as quatro consultas e me mostre a saída inteira:

  docker exec -i supabase-db psql -U postgres -d postgres <<'SQL'
  -- a) chaves estrangeiras de outros schemas apontando para tabelas do public
  select connamespace::regnamespace as schema_origem, conrelid::regclass as tabela,
         conname, confrelid::regclass as aponta_para
    from pg_constraint
   where contype = 'f'
     and connamespace::regnamespace::text not in ('public','pg_catalog')
     and confrelid::regclass::text like 'public.%';

  -- b) colunas em outros schemas usando tipos que moram no public (citext, vector)
  select n.nspname as schema, c.relname as tabela, a.attname as coluna,
         format_type(a.atttypid, a.atttypmod) as tipo
    from pg_attribute a
    join pg_class c on c.oid = a.attrelid
    join pg_namespace n on n.oid = c.relnamespace
    join pg_type t on t.oid = a.atttypid
   where a.attnum > 0 and not a.attisdropped and c.relkind = 'r'
     and n.nspname not in ('public','pg_catalog','information_schema')
     and t.typnamespace::regnamespace::text = 'public';

  -- c) funções e procedures de outros schemas que citam public.
  -- O filtro prokind é OBRIGATÓRIO: pg_get_functiondef lança erro em agregado
  -- ('"array_agg" is an aggregate function') e o planner o avalia antes do filtro
  -- de schema, então sem ele a consulta INTEIRA falha — e um erro não é "vazio".
  select n.nspname as schema, p.proname as funcao, p.prokind
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('ianews','carrossel','afatecpay','crm')
     and p.prokind in ('f','p')
     and pg_get_functiondef(p.oid) like '%public.%';

  -- c2) views e matviews de outros schemas sobre tabelas do public
  select distinct dn.nspname as schema, dc.relname as objeto, dc.relkind
    from pg_depend d
    join pg_rewrite rw on rw.oid = d.objid
    join pg_class dc on dc.oid = rw.ev_class
    join pg_namespace dn on dn.oid = dc.relnamespace
    join pg_class sc on sc.oid = d.refobjid
    join pg_namespace sn on sn.oid = sc.relnamespace
   where sn.nspname = 'public' and dn.nspname <> 'public'
     and dc.relkind in ('v','m');

  -- d) as extensões e onde elas moram
  select extname, extnamespace::regnamespace as schema from pg_extension order by 1;
SQL

  LEITURA DO RESULTADO:
    - ERRO em qualquer consulta NÃO é "vazio". Se alguma falhar, conserte e rode de novo
      antes de concluir qualquer coisa.
    - (a), (b), (c) e (c2) VAZIOS -> pode seguir para o PASSO 2-D.
    - (b) com QUALQUER linha -> PARE e me avise. Significa que outro app usa um tipo do
      public, e a limpeza precisa ser repensada.
    - (a), (c) ou (c2) com linhas -> me mostre antes de seguir. Função que depende só de
      EXTENSÃO do public (o caso de `crm.f_unaccent`, que chama `public.unaccent`) é
      benigna: o PASSO 3 não toca em extensão. Dependência de TABELA do public é que
      exige conversa.
    - (d) é registro: **quatro** extensões vivem no public — `citext`, `pg_trgm`,
      `unaccent` e `vector` — e as quatro vão FICAR lá.

PASSO 2-D — Última olhada no que vai embora. Nenhuma tabela com linha deve sumir sem você
ter visto o número antes.

⚠️ **Contagem EXATA, nunca `n_live_tup`.** `pg_stat_user_tables.n_live_tup` é estimativa do
coletor de estatísticas: tabela nunca analisada aparece com 0 mesmo cheia de dados. Uma
guarda contra perda de dados baseada em estimativa dá luz verde falsa — foi o que aconteceu
em 17/09/2026, quando a estimativa disse "tudo zerado" e a contagem real achou 110 linhas
em 10 tabelas do zapmax. Use esta, que conta de verdade:

  docker exec -i supabase-db psql -U postgres -d postgres <<'SQL'
  select t.table_name as tabela,
         (xpath('/row/cnt/text()',
                query_to_xml(format('select count(*) as cnt from public.%I', t.table_name),
                             false, true, '')))[1]::text::bigint as linhas
    from information_schema.tables t
   where t.table_schema = 'public' and t.table_type = 'BASE TABLE'
   order by 2 desc, 1;
SQL

  Me mostre a saída inteira. **Qualquer tabela com linha > 0 é parada obrigatória** até eu
  confirmar que aquele dado pode ir embora. Não conclua nada de tabela vazia sem ter rodado
  esta consulta.

  Nota sobre a contagem de objetos: `information_schema.tables` conta views,
  `pg_tables` não. Se um número der 43 e o outro 42, a diferença é a view
  `ai_provider_credentials_safe`, resíduo do baseline parcial — ela cai pelo cascade junto
  com `ai_provider_credentials`. O laço do PASSO 3 reporta o número de `pg_tables`.

PASSO 2-E — Antes de remover qualquer tabela do zapmax, provar que nenhum outro app
depende dela. `public.profiles` e `public.user_roles` têm cara de compartilhado, e o
`auth.users` é um só para todos os apps:

  docker exec -i supabase-db psql -U postgres -d postgres <<'SQL'
  -- 1) gatilhos que RESTAM em auth.users e as funções que eles chamam
  select t.tgname, n.nspname as schema_da_funcao, p.proname
    from pg_trigger t
    join pg_proc p on p.oid = t.tgfoid
    join pg_namespace n on n.oid = p.pronamespace
   where t.tgrelid = 'auth.users'::regclass and not t.tgisinternal;

  -- 2) o corpo dessas funções: alguma escreve em public.profiles / public.user_roles?
  select n.nspname, p.proname, pg_get_functiondef(p.oid) as corpo
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where p.prokind in ('f','p')
     and p.oid in (select tgfoid from pg_trigger
                    where tgrelid = 'auth.users'::regclass and not tgisinternal);

  -- 3) os outros apps têm tabela própria de perfil/usuário, ou dependem da do public?
  select table_schema, table_name
    from information_schema.tables
   where table_schema in ('ianews','carrossel','afatecpay','crm')
     and table_name ~ 'profile|perfil|usuario|user|role'
   order by 1, 2;
SQL

  LEITURA: se algum gatilho de ianews, carrossel ou afatecpay escrever em `public.profiles`
  ou `public.user_roles`, essas duas tabelas **não podem** ir embora sem conversa — pare e
  me mostre. Se cada app tiver a sua própria, o `public` é só do zapmax e o caminho está
  livre.

PASSO 2-F — Dump separado das tabelas com dado, nomeado de forma óbvia, para você levar ao
zapmax local sem garimpar dentro do dump grande. Ajuste a lista `-t` para as tabelas que o
PASSO 2-D mostrou com linhas:

  ARQ=/opt/backups/zapmax-tabelas-com-dado-$(date +%Y%m%d-%H%M).sql
  docker exec supabase-db pg_dump -U postgres -d postgres \
    -t public.tenants -t public.tenant_members -t public.subscriptions \
    -t public.roadmap_items -t public.profiles -t public.whatsapp_instances \
    -t public.plans -t public.system_settings -t public.user_roles \
    -t public.floating_button_settings \
    > "$ARQ"
  ls -l "$ARQ"
  grep -c '^COPY public\.' "$ARQ"

  A contagem de blocos COPY tem que dar 10, o número de tabelas passadas no -t. Se der
  menos, alguma tabela não entrou no dump — pare antes do PASSO 3.

PASSO 3 — Esvaziar o public de tabelas, preservando schema, dono, grants e extensões.
O comando é gerado a partir do catálogo, não de lista digitada:

  docker exec -i supabase-db psql -U postgres -d postgres <<'SQL'
  do $$
  declare r record; n int := 0;
  begin
    for r in select tablename from pg_tables where schemaname = 'public' loop
      execute format('drop table if exists public.%I cascade', r.tablename);
      n := n + 1;
    end loop;
    raise notice 'tabelas removidas: %', n;
  end $$;
  select count(*) as tabelas_restantes_no_public from pg_tables where schemaname='public';
  select extname from pg_extension where extnamespace::regnamespace::text='public' order by 1;
  select nspname, nspowner::regrole as dono from pg_namespace where nspname='public';
SQL

  Esperado: "tabelas removidas: 42" (`pg_tables` não conta a view), o
  tabelas_restantes_no_public = 0, as **quatro**
  extensões ainda listadas (citext, pg_trgm, unaccent, vector) e o public com o dono
  intacto. Se vierem só três, algo saiu errado — pare e me avise.

PASSO 3-B — Ver o que o baseline parcial deixou de funções órfãs:

  docker exec -i supabase-db psql -U postgres -d postgres <<'SQL'
  select count(*) as funcoes_no_public
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public';
SQL

  Só me RELATE o número. Não mexa nelas: o baseline recria todas com CREATE OR REPLACE,
  então função sobrando não impede a reinstalação.

PASSO 4 — Trocar a senha do primeiro admin. A anterior foi colada no chat, então não serve
mais. Gere outra e escreva direto no .env:

  cd /opt/deskcommcrm
  NOVA=$(openssl rand -base64 18)
  sed -i "s|^OWNER_PASSWORD=.*|OWNER_PASSWORD=${NOVA}|" .env
  echo "nova senha: ${NOVA}"
  grep -c '^OWNER_PASSWORD=.\{20,\}' .env

  A última linha tem que devolver 1.

PASSO 5 — Conferir que o resto do .env sobreviveu (o comando do Bloco 3 tinha um bug de
regex: ^(...|TRAEFIK_)= exigia literalmente TRAEFIK_=; este está corrigido):

  cd /opt/deskcommcrm
  grep -E '^(DOMAIN=|ACME_EMAIL=|REVERSE_PROXY=|TRAEFIK_|APP_NAME=|APP_LOCALE=|APP_ACCENT_HEX=|APP_LOGO_URL=|COMPOSE_PROFILES=|OWNER_EMAIL=)' .env
  grep -cE '^(NEXT_PUBLIC_SUPABASE_URL|NEXT_PUBLIC_SUPABASE_ANON_KEY|SUPABASE_SERVICE_ROLE_KEY|SUPABASE_DB_URL|OWNER_PASSWORD)=.+' .env

  A segunda linha tem que devolver 5, e APP_NAME tem que ser exatamente AfatecCRM.

PASSO 6 — Reinstalar:

  cd /opt/deskcommcrm
  bash hostgator-setup-kit/install.sh --yes 2>&1 | tail -80

  Os segredos que o instalador gerou na primeira tentativa já estão no .env e serão
  reaproveitados. Se ele parar de novo, PARE e me mostre a mensagem inteira, com as 20
  linhas anteriores ao erro — não tente contornar.

  O QUE OBSERVAR NA SAÍDA: o instalador decide entre "banco novo" e "banco existente"
  olhando se public.organizations existe (install.sh:1804). Com o public limpo, ele tem
  que entrar no modo novo, que é o estrito (ON_ERROR_STOP) — a linha esperada é
  "✓ schema aplicado". Se aparecer "schema já existe — re-aplicando em modo update", o
  PASSO 3 não limpou de verdade: PARE, porque nesse modo os erros são engolidos como
  "esperados" e o schema sairia pela metade sem ninguém avisar.

PASSO 7 — Conferir o banco depois que o baseline passar:

  docker exec -i supabase-db psql -U postgres -d postgres <<'SQL'
  select count(*) as tabelas from pg_tables where schemaname='public';
  select count(*) as policies from pg_policies where schemaname='public';
  select count(*) as usuarios from auth.users;
SQL

  Esperado: 38 tabelas ou mais, policies acima de zero (se vier 0, o RLS não foi aplicado
  e o schema está incompleto de novo), e auth.users com os 4 de antes mais o novo admin.

Depois disso siga do PASSO 5 do Bloco 3 em diante (conferência dos contêineres, domínio,
marca AfatecCRM e o check de que nada mais na VPS foi afetado).
```

**Como saber que deu certo:** `install.sh` termina sem erro, `public` com as 38 tabelas do
CRM e nenhuma do zapmax, policies acima de zero, e os contêineres de pé.

---

## Bloco 3 — Instalar o DeskcommCRM (modo não-interativo) ✅ NO AR em 17/09/2026

> Instalado na segunda tentativa, depois do Bloco 2-C. `https://crm.afatec.net` responde com
> certificado válido, login validado de ponta a ponta pelo Kong, 6 contêineres somando
> ~800 MB e a VPS com os mesmos 8,3 Gi disponíveis de antes. Blocos 4 e 5 ficaram cobertos
> pela própria verificação da instalação. **Bloco 6 adiado** até haver um chip diferente do
> Agente Express.

O instalador tem um modo interativo que faz perguntas, e um modo `--yes` que lê tudo de um
`.env` preenchido antes. **Por SSH usamos o `--yes`** — não há terminal para responder as
perguntas, e um `read -r -p` num SSH não-interativo trava ou consome lixo do stdin.

Preencher o `.env` na mão também resolve outro risco: os valores de Traefik que o
diagnóstico já apurou entram declarados, em vez de dependerem da detecção automática.

```
Vamos instalar o DeskcommCRM na VPS, por SSH, em modo NÃO-INTERATIVO. Regras que valem
o tempo todo:

  - NÃO pare nem reconfigure o Traefik do EasyPanel (serviço Swarm easypanel-traefik).
  - NÃO toque no Supabase self-hosted da VPS (o schema public é do zapmax em produção),
    nem no n8n, nem na Evolution API.
  - NÃO desligue o CRM antigo em /opt/crm-afatec — ele fica no ar em paralelo.
  - O banco deste CRM novo é o Supabase SELF-HOSTED da VPS, alcançado pela ponte socat
    que subimos no Bloco 2 (172.17.0.1:5433). NÃO é Supabase Cloud, e NÃO é a 5432 do
    host, que é de um PostgreSQL 16 nativo — outro banco.
  - Não rode "docker compose up -d caddy" NUNCA: nomear o serviço liga o profile dele e
    ele vai disputar as portas 80/443 com o EasyPanel.

PASSO 1 — Clonar, fora dos caminhos existentes:

  cd /opt
  git clone --depth 1 https://github.com/melgarafael/DeskcommCRM.git deskcommcrm
  cd /opt/deskcommcrm
  cp .env.hostgator.example .env
  chmod 600 .env

PASSO 2 — Colher as credenciais NA PRÓPRIA VPS. Nada de chave vinda pelo chat.

  a) anon key e service_role: leia do ambiente dos contêineres do Supabase que já rodam
     aí. Está autorizado a ler; NÃO imprima o valor inteiro na saída, só os 8 primeiros
     caracteres para conferência:

       docker inspect supabase-kong --format '{{range .Config.Env}}{{println .}}{{end}}' \
         | grep -E '^(ANON_KEY|SERVICE_ROLE_KEY)=' | cut -c1-30

     Se o supabase-kong não trouxer, procure no .env da stack do Supabase (o diretório que
     tem o docker-compose dela) pelas chaves ANON_KEY e SERVICE_ROLE_KEY.

  b) senha do primeiro admin: GERE na VPS, não peça pelo chat. Imprima UMA vez para eu
     guardar no gerenciador de senhas, e troque depois do primeiro login:

       openssl rand -base64 18

PASSO 2-B — Preencher o .env. Use um heredoc com ASPAS SIMPLES no delimitador (<<'EOF'),
para o shell não interpolar nada.

Edite/acrescente EXATAMENTE estas chaves no /opt/deskcommcrm/.env:

  DOMAIN=crm.afatec.net
  ACME_EMAIL=<e-mail do Allisson>
  # as duas abaixo o instalador REESCREVE a partir do DOMAIN — deixe assim mesmo,
  # é só para o arquivo ficar coerente se alguém ler antes de rodar
  NEXT_PUBLIC_APP_URL=https://crm.afatec.net
  NEXT_PUBLIC_ADMIN_URL=https://crm.afatec.net

  # Traefik do EasyPanel — valores APURADOS no Bloco 0. Declarados de propósito:
  # preenchidos aqui, o instalador NÃO tenta adivinhar.
  REVERSE_PROXY=traefik
  TRAEFIK_NETWORK=easypanel
  TRAEFIK_ENTRYPOINT=https
  TRAEFIK_ENTRYPOINT_HTTP=http
  TRAEFIK_CERTRESOLVER=letsencrypt

  # Supabase self-hosted da VPS (o gateway Kong, não o Studio)
  NEXT_PUBLIC_SUPABASE_URL=https://zapmaxapi.afatec.net
  NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon key>
  SUPABASE_SERVICE_ROLE_KEY=<service_role key>
  SUPABASE_DB_URL=<a string que funcionou no PASSO 5 do Bloco 2>
  # em Supabase PRÓPRIO o guia manda preencher as duas; é esta que aplica o schema
  SUPABASE_DB_ADMIN_URL=<a mesma string, se ela for do dono do banco>

  # Primeiro admin
  OWNER_EMAIL=<e-mail do Allisson>
  OWNER_PASSWORD=<a senha gerada no PASSO 2-b>

  # Marca da Afatec — AfatecCRM sem espaço, exatamente assim
  APP_NAME=AfatecCRM
  APP_LOCALE=pt-BR
  APP_ACCENT_HEX=#0090FE
  APP_LOGO_URL=https://crm-afatec.gddktt.easypanel.host/logo-afatec.png

  # IA fica para depois (cadastro pela tela, em IA › Credenciais)
  ANTHROPIC_API_KEY=
  # Chamada de voz desligada — não mexer
  COMPOSE_PROFILES=

⚠️ APP_LOCALE **não vem** no .env.hostgator.example, e em modo --yes o instalador aborta
com "Falta APP_LOCALE" se ela não existir. É por isso que ela está na lista acima.

> **Os nomes destas chaves foram conferidos contra a v1.28.0**, uma a uma, no
> `.env.hostgator.example`, no `install.sh` e nos dois composes: todas existem e são lidas.
> A única ausente do template é a `APP_LOCALE` — por isso o aviso acima.

⚠️ A connection string **não pode usar o nome `supabase-db`**, nem a porta **5432 do host**
(que é de um PostgreSQL 16 nativo, outro banco). Use exatamente a que passou na prova do
PASSO 5 do Bloco 2.

PASSO 3 — Conferir o .env antes de rodar (mascare os segredos na saída):

  cd /opt/deskcommcrm
  grep -E '^(DOMAIN=|ACME_EMAIL=|NEXT_PUBLIC_APP_URL=|REVERSE_PROXY=|TRAEFIK_|APP_NAME=|APP_LOCALE=|APP_ACCENT_HEX=|APP_LOGO_URL=|COMPOSE_PROFILES=|OWNER_EMAIL=)' .env
  grep -cE '^(NEXT_PUBLIC_SUPABASE_URL|NEXT_PUBLIC_SUPABASE_ANON_KEY|SUPABASE_SERVICE_ROLE_KEY|SUPABASE_DB_URL|OWNER_PASSWORD)=.+' .env

  A segunda linha tem que devolver 5. Se devolver menos, alguma credencial ficou vazia.

PASSO 4 — Instalar:

  cd /opt/deskcommcrm
  bash hostgator-setup-kit/install.sh --yes 2>&1 | tail -60

  O instalador gera sozinho os segredos que faltam (INTERNAL_SECRET, CPF_ENCRYPTION_KEY,
  AI_CRED_AES_KEY, WAHA_API_KEY + hash, WAHA_HMAC_SECRET, SRH_TOKEN e os demais), aplica
  o supabase/baseline.sql no banco, cria o primeiro admin e instala o cron do
  event-log-drain. Não invente nenhum desses valores à mão.

  Se ele parar dizendo que não identificou o dono das portas 80/443, NÃO force nada:
  o REVERSE_PROXY=traefik já está declarado no .env, então me mostre a mensagem inteira
  antes de qualquer outra coisa.

PASSO 5 — Conferir o resultado:

  cd /opt/deskcommcrm
  grep -E '^(REVERSE_PROXY=|TRAEFIK_|APP_IMAGE=|WORKER_IMAGE=|SCHEDULER_IMAGE=|COMPOSE_PROFILES=)' .env
  docker compose -f docker-compose.prod.yml -f docker-compose.traefik.yml ps
  docker inspect deskcommcrm-app-1 --format '{{json .NetworkSettings.Networks}}' | tr ',' '\n' | grep -o '"[a-z_-]*":' | head

Espero ver:
  - REVERSE_PROXY=traefik, TRAEFIK_NETWORK=easypanel, TRAEFIK_ENTRYPOINT=https
  - COMPOSE_PROFILES vazio (chamada de voz desligada)
  - app, worker, waha, redis, srh e scheduler de pé — e NENHUM caddy
  - o contêiner do app conectado nas DUAS redes: a internal do projeto e a easypanel

PASSO 6 — Provar que o domínio responde pelo Traefik, e não pela página de erro do painel:

  curl -sS -o /dev/null -w '%{http_code} %{ssl_verify_result}\n' https://crm.afatec.net/
  curl -sS -I https://crm.afatec.net/ | head -5

  200 (ou 307 para /login) é o que queremos, com certificado do Let's Encrypt.

  ⚠️ NÃO confunda o antes com o depois. ANTES da instalação, este mesmo domínio já devolvia
  404 com certificado autoassinado CN=Easypanel — é o comportamento normal de um Host sem
  router, e foi o estado aprovado no Bloco 1. O que caracteriza problema é esse 404
  CONTINUAR depois de os contêineres estarem de pé: aí sim o label caiu num entrypoint que
  não existe, ou o Traefik não está enxergando o contêiner. Confira TRAEFIK_ENTRYPOINT=https
  no .env e que o app está na rede easypanel (PASSO 5), suba de novo com os DOIS arquivos de
  compose, e se persistir vamos para o Bloco 3-B.

E confirme que nada mais na VPS foi afetado:

  docker ps --format '{{.Names}}\t{{.Status}}' | grep -Ei 'supabase|evolution|n8n|crm-afatec|traefik'
```

**Como saber que deu certo:** os 6 contêineres de pé, nenhum `caddy`, o app nas duas redes,
e `https://crm.afatec.net` devolvendo a tela de login com cadeado válido.

---

## Bloco 4 — Marca: o nome é **AfatecCRM**

O produto foi feito para marca própria: o nome e a logo vêm de variáveis de RUNTIME
(`APP_NAME`, `APP_LOGO_URL`, `APP_ACCENT_HEX`), lidas a cada requisição, não no build.
Isso quer dizer que a troca sobrevive a toda atualização de imagem — não é um patch que
o `update.sh` desfaz.

E há uma regra no código que trabalha a nosso favor: `marcaEhADoProduto()`
(`lib/branding.ts:95`) só devolve verdadeiro quando **não há logo configurada E o nome é
o padrão**. Assim que `APP_NAME` for outra coisa, o logotipo desenhado do produto — que
soletra o nome antigo letra por letra em `lib/branding/desenho.ts` — para de ser
desenhado em qualquer tela. Não é escondido: deixa de existir na saída.

```
1. Confirme que a logo da Afatec responde (é a URL pública que o CRM antigo já serve):

     curl -sI https://crm-afatec.gddktt.easypanel.host/logo-afatec.png | head -3

2. No /opt/deskcommcrm/.env, garanta estas três linhas exatamente assim:

     APP_NAME=AfatecCRM
     APP_ACCENT_HEX=#0090FE
     APP_LOGO_URL=https://crm-afatec.gddktt.easypanel.host/logo-afatec.png

   AfatecCRM é uma palavra só, sem espaço. A cor tem que ser cerquilha + 6 dígitos:
   "#0090FE" funciona; "#09F" ou "0090FE" pintam a tela mas quebram o e-mail de acesso.

3. Aplique:

     cd /opt/deskcommcrm
     docker compose -f docker-compose.prod.yml -f docker-compose.traefik.yml up -d

4. Prova de que o nome antigo sumiu das telas — as quatro de uma vez:

     # título da aba e nome da aplicação
     curl -s https://crm.afatec.net/login | grep -o '<title>[^<]*</title>'
     # manifesto do PWA (nome do atalho na tela inicial do celular)
     curl -s https://crm.afatec.net/manifest.webmanifest
     # favicon gerado em runtime — tem que responder image/png
     curl -sI https://crm.afatec.net/icon | grep -i content-type
     # varredura: o nome antigo não pode aparecer no HTML de nenhuma das públicas
     for u in / /login /manifest.webmanifest; do
       printf '%s -> ' "$u"
       curl -s "https://crm.afatec.net$u" | grep -c Deskcomm
     done

   Esperado: o `<title>` começa com "AfatecCRM", o /icon devolve PNG, e a varredura
   devolve `0` em `/` e `/login`. O **manifesto é a exceção conhecida**: vem com o nome
   antigo porque está congelado no build (ver a correção logo abaixo da tabela).
```

### O que o `APP_NAME` já cobre sozinho

Conferido linha a linha na v1.28.0 que vamos instalar:

| Onde o usuário vê | Arquivo | Vira AfatecCRM? |
|---|---|---|
| Título de toda aba (`AfatecCRM — …` e `Inbox · AfatecCRM`) | `app/layout.tsx:80` | sim |
| Favicon da aba (ladrilho com a inicial na cor da marca) | `app/icon.tsx` | sim |
| Nome do PWA / atalho no celular | `app/manifest.ts` | **NÃO** — ver abaixo |
| Barra lateral, aberta e recolhida | `components/shell/Sidebar.tsx` | sim |
| Barra lateral do admin da plataforma | `components/admin/AdminSidebar.tsx` | sim |
| Tela de login e fachada pública | `app/(public)/layout.tsx` | sim |
| Onboarding do primeiro acesso | `app/onboarding/layout.tsx` | sim |
| Logotipo desenhado do produto | `lib/branding/desenho.ts` | some da tela |
| E-mails de convite, MFA e LGPD | `lib/branding/saida.ts` | sim |
| PDF de resposta LGPD | `lib/lgpd/pdf-renderer.tsx` | sim |

**Correção medida na VPS em 17/09/2026:** o `manifest.webmanifest` continua com o nome
antigo mesmo com `APP_NAME=AfatecCRM`. Eu tinha escrito que ele lia a marca em runtime, e o
código até lê (`marcaDaSaida(null)`) — mas `app/manifest.ts` **não declara
`export const dynamic = "force-dynamic"`**, então o Next o congela no `next build`, com a
marca de quem buildou a imagem. É exatamente a armadilha que o cabeçalho de `app/icon.tsx`
descreve e da qual o próprio ícone se protege; o manifesto ficou de fora. Efeito prático:
só o nome do atalho ao instalar como PWA no celular. Conserto definitivo e grátis: uma
linha no projeto de origem — vale abrir uma issue/PR em `melgarafael/DeskcommCRM`, que
corrige para todo mundo e chega aqui na próxima atualização de imagem.

Além disso o produto tem **duas telas** para trocar isso depois sem mexer em arquivo:
**Admin da plataforma › Marca da instalação** e **Configurações › Marca**. O que é
gravado no banco por essas telas tem prioridade sobre o `.env` — é a camada de cima
da pilha (`app/layout.tsx:59`). Então dá para ajustar nome, cor e logo pelo navegador,
com a instalação no ar.

### O que sobra, e o que fazer com isso

Três lugares ainda têm o nome antigo cravado em código. Nenhum aparece na navegação
normal, mas você pediu "em lugar nenhum", então ficam declarados:

1. **`/design`** — uma vitrine do design system (`app/design/`), não linkada de lugar
   nenhum e marcada `noindex`, mas servida se alguém digitar o endereço.
2. **`/llms.txt`** — arquivo público em `public/llms.txt` com o nome e os links do
   projeto de origem.
3. **Assunto de um e-mail só** — o alarme de orçamento de IA
   (`lib/email/templates/ai-budget-alarm.tsx:35`) tem o nome antigo no assunto. Só
   dispara se você cadastrar chave de IA e o gasto bater o teto configurado; até lá
   não existe.

Dois caminhos, e eu recomendo o primeiro agora:

- **Bloquear as duas URLs no Traefik** (grátis, 5 minutos, nada de build). O compose
  já traz o padrão pronto para isso: o roteador `deskcomm-waha-block` bloqueia um
  caminho com `ipallowlist` de faixa impossível. Copiar esse bloco para `/design` e
  `/llms.txt` resolve. **Atenção:** fica em `docker-compose.traefik.yml`, que é
  versionado — o `update.sh` faz checkout da tag e desfaz. Tem que reaplicar depois de
  cada atualização, ou guardar o trecho num arquivo à parte para colar de volta.
- **Build próprio** (o certo definitivo, também grátis). Fork do repositório, três
  edições de texto, e o GitHub Actions monta a imagem e publica no GHCR sem custo para
  repositório público. Aí `APP_IMAGE` no `.env` aponta para a sua imagem e o nome antigo
  deixa de existir no disco. Custo: passamos a ser responsáveis por acompanhar as
  releases de origem. Vale a pena depois que o CRM estiver rodando e provado, não antes.

### E-mails de acesso (confirmar conta, redefinir senha)

Correção do que eu tinha escrito antes: o app **serve** os moldes com a marca em
`https://crm.afatec.net/email-templates/confirmation` e `/recovery`, e o GoTrue sabe
carregar molde por URL (`GOTRUE_MAILER_TEMPLATES_CONFIRMATION`). Não é impossível, como
eu disse.

O problema é outro, e é decisivo: **o GoTrue da VPS é um só**, compartilhado com ianews,
carrossel, afatecpay e zapmax. Apontar essas variáveis para o CRM colocaria a marca
AfatecCRM nos e-mails de acesso **de todos os apps**. Por isso ficam como estão: no
modelo padrão do GoTrue, que não cita marca nenhuma — nem a antiga. Ou seja, não há
vazamento de nome aqui; há só uma oportunidade de marca que não dá para pegar sem
afetar os vizinhos.

O `hostgator-setup-kit/marca-emails.sh` continua inútil aqui: ele fala com a Management
API do Supabase Cloud (`api.supabase.com`) com um token de conta, que não existe em
self-hosted.

**Site URL e Redirect URLs** já foram tratados no **PASSO 6 do Bloco 2**. Só confira que
o endereço do CRM continua na allow list depois da instalação.

**Como saber que deu certo:** a tela de login mostra a logo da Afatec, o azul #0090FE
aparece nos botões, o `<title>` da aba começa com "AfatecCRM" e a varredura do passo 4
devolve `0` nas três URLs.

---

## Bloco 5 — Verificação de saúde

```
Rode o diagnóstico do próprio kit e me mostre a saída inteira:

  cd /opt/deskcommcrm
  bash hostgator-setup-kit/healthcheck.sh

Depois confirme que a fila de eventos está sendo drenada — é ela que faz as automações
dispararem de verdade. Sem esse cron, elas ficam paradas para sempre:

  crontab -l | grep -i event-log-drain
  cd /opt/deskcommcrm && source .env && \
    curl -s -H "Authorization: Bearer ${INTERNAL_SECRET}" \
      "${NEXT_PUBLIC_APP_URL}/api/v1/cron/event-log-drain"

Resposta esperada: um JSON no formato {"data":{"scanned":N,...}}. N pode ser 0 — o que
não pode é erro de autenticação ou de conexão.

E confirme que nada foi afetado na VPS:

  docker ps --format '{{.Names}}\t{{.Status}}' | grep -Ei 'supabase|evolution|n8n|crm-afatec'

Todos têm que continuar Up.
```

**Como saber que deu certo:** healthcheck verde, o drain devolvendo JSON, e Supabase,
Evolution, n8n e o CRM antigo todos `Up`.

---

## Bloco 6 — Entrar e conectar o WhatsApp ⏸ ADIADO em 17/09/2026 (falta um chip)

> O onboarding tem o botão **"Pular por enquanto"** na tela do WhatsApp
> (`app/onboarding/connect-whatsapp/_client.tsx:193`), então dá para entrar, montar funil,
> campos e equipe, e conectar o número depois em Conexões, sem reinstalar nada.

1. Abra `https://crm.afatec.net` e entre com o e-mail e a senha de admin do Bloco 3.
2. O onboarding vai pedir para conectar o WhatsApp por QR code.

> ⚠️ **Use um chip diferente do Agente Express.** O número que está pareado na Evolution
> API só aceita um pareamento: ler o QR do WAHA com ele **desconecta a Evolution** e o
> Agente Express para de responder. Se a ideia for migrar o número, isso é uma decisão
> à parte — me fala antes.

```
Se o QR não aparecer, ou a sessão não sair de STARTING, me mostre:

  cd /opt/deskcommcrm
  docker compose -f docker-compose.prod.yml -f docker-compose.traefik.yml logs --tail=80 waha
  docker compose -f docker-compose.prod.yml -f docker-compose.traefik.yml logs --tail=80 app
```

**Como saber que deu certo:** você está dentro do CRM, o número aparece conectado e uma
mensagem enviada para ele cai no Inbox.

---

## Depois que estiver no ar

- **Backup:** `bash hostgator-setup-kit/backup.sh` — banco + sessões do WhatsApp. Vale
  agendar no cron logo no primeiro dia.
- **Atualizar:** `bash hostgator-setup-kit/update.sh`.
- **Senha perdida:** `bash hostgator-setup-kit/reset-password.sh`.
- **MFA travado:** `bash hostgator-setup-kit/reset-mfa.sh`.
- **IA:** cadastre a chave em IA › Credenciais. O OpenRouter tem modelos gratuitos, mas
  escolha um com *tool calling* — sem isso o agente responde texto bonito e nunca cria o
  lead nem move o card.
- **Desligar o CRM antigo:** só depois de você aprovar o novo. Ele está em
  `/opt/crm-afatec`, num `nginx:alpine` na porta 8098.

## Sugestões de melhoria

1. **Aponte o n8n para o CRM novo.** O DeskcommCRM expõe fontes de captação por webhook
   público (`/api/v1/webhooks/in/<token>`), que aceitam POST em JSON. Os seus workflows do
   n8n passam a criar lead direto no funil, sem integração customizada. Custo zero.
2. **Decida o destino do Agente Express.** O DeskcommCRM tem agente de IA, roteador e
   follow-up nativos — ou seja, ele cobre o que o `afatec-agent-core` faz hoje. Manter os
   dois no mesmo WhatsApp não é possível; escolher um evita trabalho duplicado.
3. **Backup para fora da VPS.** O `backup.sh` grava local. Um workflow n8n empurrando o
   arquivo para um storage externo fecha o buraco — VPS que morre leva o backup junto.
4. **Gire a `service_role` do Supabase self-hosted.** Ela está em texto puro nos arquivos
   deste projeto. Nada a ver com o DeskcommCRM, mas continua pendente.
5. **Tetos de memória já vêm no compose** (app 768m, worker 512m, WAHA 1280m) e a VPS tem
   swap de 4 GB — nada a fazer aqui. Vale só lembrar que os seus outros contêineres rodam
   **sem teto**: o elasticsearch do Postae (709 MB) e o n8n (670 MB) podem crescer sem
   limite, e o OOM killer escolhe a vítima por quem cresceu mais rápido, não por
   importância. Pôr `mem_limit` neles é um seguro barato para o zapmax em produção.

---

## Bloco 3-B — Plano B: rotear pelo file provider (só se o label não pegar)

Se o app subir saudável por dentro mas `https://crm.afatec.net` devolver a página de erro
do EasyPanel, é a rota por label que não pegou. O caminho já validado nesta VPS é o file
provider, o mesmo que hoje atende crm-afatec, zapmax, carousel e financeiro.

```
A rota por label não pegou. Vamos pelo file provider, como os outros apps standalone
desta VPS. NÃO mexa nos YAMLs que já existem em /etc/easypanel/traefik/config/.

1. Publique a porta do app no host, só no loopback do docker0. Crie
   /opt/deskcommcrm/docker-compose.easypanel.yml com:

     services:
       app:
         ports:
           - "127.0.0.1:8099:3000"

   Antes disso, confirme que a 8099 está livre:  ss -tlnp | grep ':8099 '
   (a 8098 é do CRM antigo — não use).

2. Suba com os TRÊS arquivos:

     cd /opt/deskcommcrm
     docker compose -f docker-compose.prod.yml -f docker-compose.traefik.yml \
       -f docker-compose.easypanel.yml up -d

3. Crie /etc/easypanel/traefik/config/crm-afatec-deskcomm.yaml no mesmo formato dos
   YAMLs que já estão lá (copie a estrutura de um existente, não invente), com router em
   Host(`crm.afatec.net`), entrypoint https, certresolver letsencrypt, e serviço
   apontando para http://172.17.0.1:8099/.

4. O Traefik recarrega o diretório sozinho. Confirme:

     curl -sS -o /dev/null -w '%{http_code}\n' https://crm.afatec.net/

5. Me mostre o YAML que você escreveu ANTES de salvar, e a saída do curl depois.
```
