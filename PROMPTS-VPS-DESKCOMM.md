# Subir o DeskcommCRM na VPS, com a marca Afatec

Roteiro escrito em 15/09/2026 para o **Claude Code do Allisson**, que alcança a VPS por SSH.
Baseado no DeskcommCRM **v1.27.2** (`melgarafael/DeskcommCRM`, MIT), lido commit a commit,
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

## Bloco 2 — Preparar o Supabase da VPS

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

PASSO 1 — Prova de colisão (só leitura). O baseline do DeskcommCRM cria 94 tabelas em
public. Descubra se alguma já existe:

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

PASSO 5 — Conectividade, e este passo decide o formato da connection string. O instalador
roda o psql assim:

    docker run --rm postgres:17-alpine psql "$SUPABASE_DB_URL"

  Sem --network. Ou seja, ele NÃO resolve o nome "supabase-db": a string tem que apontar
  para um endereço alcançável do bridge padrão. Descubra:

    docker port supabase-db
    ss -tlnp | grep ':5432'
    docker run --rm postgres:17-alpine psql \
      "postgresql://postgres:SENHA@172.17.0.1:5432/postgres" -tAc 'select version()'

  Se a 5432 não estiver publicada no host, me avise ANTES de publicar — publicar Postgres
  no host é decisão de segurança, e há alternativa (fixar o IP do container).

  Me diga qual string funcionou. Ela vai em SUPABASE_DB_URL e em SUPABASE_DB_ADMIN_URL no
  Bloco 3 (em Supabase próprio o guia manda preencher as duas).

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

---

## Bloco 3 — Instalar o DeskcommCRM (modo não-interativo)

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
  - O banco deste CRM novo é um projeto no Supabase CLOUD, não o da VPS.
  - Não rode "docker compose up -d caddy" NUNCA: nomear o serviço liga o profile dele e
    ele vai disputar as portas 80/443 com o EasyPanel.

PASSO 1 — Clonar, fora dos caminhos existentes:

  cd /opt
  git clone --depth 1 https://github.com/melgarafael/DeskcommCRM.git deskcommcrm
  cd /opt/deskcommcrm
  cp .env.hostgator.example .env
  chmod 600 .env

PASSO 2 — Preencher o .env. Use um heredoc com ASPAS SIMPLES no delimitador (<<'EOF'),
para o shell não interpolar nada, e escreva as chaves do Supabase a partir dos valores que
eu vou te passar por um caminho seguro (nunca colados no chat do projeto).

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
  OWNER_PASSWORD=<senha forte, no mínimo 8 caracteres>

  # Marca da Afatec
  APP_NAME=Afatec CRM
  APP_LOCALE=pt-BR
  APP_ACCENT_HEX=#0090FE
  APP_LOGO_URL=https://crm-afatec.gddktt.easypanel.host/logo-afatec.png

  # IA fica para depois (cadastro pela tela, em IA › Credenciais)
  ANTHROPIC_API_KEY=
  # Chamada de voz desligada — não mexer
  COMPOSE_PROFILES=

⚠️ APP_LOCALE **não vem** no .env.hostgator.example, e em modo --yes o instalador aborta
com "Falta APP_LOCALE" se ela não existir. É por isso que ela está na lista acima.

> **Os nomes destas chaves foram conferidos contra a v1.27.2**, uma a uma, no
> `.env.hostgator.example`, no `install.sh` e nos dois composes: todas existem e são lidas.
> A única ausente do template é a `APP_LOCALE` — por isso o aviso acima.

⚠️ A connection string **não pode usar o nome `supabase-db`**: o instalador roda o psql num
container avulso, sem `--network`, e ele não resolve esse nome. Use a que passou no PASSO 5
do Bloco 2.

PASSO 3 — Conferir o .env antes de rodar (mascare os segredos na saída):

  cd /opt/deskcommcrm
  grep -E '^(DOMAIN|ACME_EMAIL|NEXT_PUBLIC_APP_URL|REVERSE_PROXY|TRAEFIK_|APP_NAME|APP_LOCALE|APP_ACCENT_HEX|APP_LOGO_URL|COMPOSE_PROFILES|OWNER_EMAIL)=' .env
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
  grep -E '^(REVERSE_PROXY|TRAEFIK_NETWORK|TRAEFIK_ENTRYPOINT|TRAEFIK_CERTRESOLVER|APP_IMAGE|WORKER_IMAGE|SCHEDULER_IMAGE|COMPOSE_PROFILES)=' .env
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

## Bloco 4 — Marca da Afatec

```
Agora a identidade visual. A logo da Afatec já está publicada pelo CRM antigo, então
dá para apontar direto para ela — é uma URL pública e gratuita:

  https://crm-afatec.gddktt.easypanel.host/logo-afatec.png

1. Confirme que a URL responde uma imagem:

     curl -sI https://crm-afatec.gddktt.easypanel.host/logo-afatec.png | head -3

2. No /opt/deskcommcrm/.env, garanta estas três linhas (o instalador já deve ter
   escrito APP_NAME e APP_ACCENT_HEX; acrescente a logo):

     APP_NAME=Afatec CRM
     APP_ACCENT_HEX=#0090FE
     APP_LOGO_URL=https://crm-afatec.gddktt.easypanel.host/logo-afatec.png

   A cor tem que ser cerquilha + 6 dígitos. "#0090FE" funciona; "#09F" ou "0090FE"
   pintam a tela mas quebram o e-mail de acesso.

3. Aplique:

     cd /opt/deskcommcrm
     docker compose -f docker-compose.prod.yml -f docker-compose.traefik.yml up -d
```

4. **Site URL e Redirect URLs** já foram tratados no **PASSO 6 do Bloco 2** — num Supabase
   self-hosted eles são variáveis do container de auth (`GOTRUE_SITE_URL`,
   `GOTRUE_URI_ALLOW_LIST`), não tela do Studio, e o `SITE_URL` é compartilhado com os
   outros apps. Só confira que o endereço do CRM continua na allow list depois da instalação.

   > O `hostgator-setup-kit/marca-emails.sh`, que deixaria os e-mails de acesso com a marca
   > da Afatec, **não serve aqui**: ele fala com a Management API do Supabase Cloud
   > (`api.supabase.com`) usando um token de conta, que não existe em self-hosted. Os
   > e-mails de acesso ficam no modelo padrão do GoTrue. Personalizá-los é mexer nos
   > templates do container de auth — e eles são compartilhados com ianews, carrossel e
   > afatecpay, então é mudança para depois, com cuidado, não agora.

**Como saber que deu certo:** a tela de login mostra a logo da Afatec, o azul da marca
aparece nos botões, e o `marca-emails.sh` terminou sem erro.

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

## Bloco 6 — Entrar e conectar o WhatsApp

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
