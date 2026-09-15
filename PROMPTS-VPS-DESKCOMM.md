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
| **Banco no Supabase Cloud (plano grátis)** | O `public` do Supabase da VPS é do **zapmax em produção**, e as 242 migrations do DeskcommCRM são escritas para `public`. Um segundo Supabase self-hosted comeria mais ~1 GB de RAM e o próprio guia do projeto diz que self-hosted "funciona, mas não é coberto". O plano grátis é free, com backup gerenciado. Limites a saber: **500 MB de banco** e o projeto **hiberna após 7 dias sem tráfego** (com WhatsApp ligado, não hiberna). |
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

## Bloco 1 — DNS do `crm.afatec.net` ⏳ AGUARDA O CLOUDFLARE

**Estado em 15/09/2026: reprovado.** O `crm.afatec.net` está com o proxy laranja ligado —
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

  curl -sS -o /dev/null -w '%{http_code}\n' http://crm.afatec.net/

Um 404 do Traefik (sem o header "server: cloudflare") é o esperado aqui: significa que a
requisição chegou na VPS e ainda não há router para esse Host. É exatamente o que o
Bloco 3 vai preencher.
```

**Como saber que deu certo:** o A devolve `76.13.98.43`, o AAAA vem vazio ou com o IPv6
da VPS, e o GET em `http://crm.afatec.net/` não traz mais `server: cloudflare`.

---

## Bloco 2 — Criar o projeto no Supabase Cloud

Este também é **seu**, e leva 3 minutos:

1. Entre em [supabase.com](https://supabase.com) e crie um projeto novo na região
   **South America (São Paulo) — sa-east-1**. Guarde a senha do banco que ele pedir.
2. **Não precisa gerar token de conta.** O instalador usaria esse token só para configurar
   os links dos e-mails de acesso, e isso são dois campos que você preenche no painel no
   Bloco 4. Como ele é chave mestra da conta inteira (cria e apaga projetos), deixar ele
   fora da VPS é de graça — e nada aqui pede que você o cole em chat nenhum.

3. Em **Settings → API**, copie: *Project URL*, *anon key*, *service_role key*.
4. Em **Settings → Database → Connection string**, copie a do **Session pooler, modo URI**.
   > A *Direct connection* é IPv6-only e **não conecta de um VPS IPv4** — é o erro mais
   > comum dessa instalação.

**Como saber que deu certo:** você tem as 4 credenciais e o projeto no painel do Supabase
está verde (`ACTIVE_HEALTHY`). Projeto recém-criado leva alguns minutos para chegar lá.

> As 4 credenciais vão do seu computador direto para o `.env` na VPS, por SSH. Não precisam
> passar pelo chat do projeto — e a `service_role` em especial não deve.

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

  # Supabase Cloud
  NEXT_PUBLIC_SUPABASE_URL=<Project URL>
  NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon key>
  SUPABASE_SERVICE_ROLE_KEY=<service_role key>
  SUPABASE_DB_URL=<connection string do SESSION POOLER, modo URI>

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

⚠️ A connection string tem que ser a do **Session pooler, modo URI**. A "Direct connection"
é IPv6-only e não conecta de um VPS IPv4 — é o erro mais comum desta instalação.

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

  200 (ou 307 para /login) é o que queremos. Se vier a página de erro do EasyPanel, o
  label caiu num entrypoint que não existe — confira TRAEFIK_ENTRYPOINT=https no .env,
  suba de novo com os DOIS arquivos de compose, e se persistir vamos para o Bloco 3-B.

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

4. **Site URL e Redirect URLs — faça no painel do Supabase, à mão.** É o passo que decide
   se o "esqueci minha senha", a confirmação de conta e o aceite de convite chegam com link
   que funciona. Ele nasce como `http://localhost:3000`. Em
   **Authentication → URL Configuration** do seu projeto:

   - **Site URL:** `https://crm.afatec.net`
   - **Redirect URLs:** `https://crm.afatec.net/auth/confirm`

   > Existe um script que faz isso sozinho e ainda deixa os e-mails com a marca da Afatec —
   > `hostgator-setup-kit/marca-emails.sh` —, mas ele **exige o token de conta do Supabase**,
   > que é chave mestra. Dois campos no painel resolvem a parte que importa sem o token
   > sair do lugar. Se você quiser os e-mails com a marca depois, rode numa linha só, do
   > seu terminal, sem gravar nada:
   > `ssh root@VPS "cd /opt/deskcommcrm && SUPABASE_ACCESS_TOKEN=sbp_... bash hostgator-setup-kit/marca-emails.sh"`

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
