# Subir o DeskcommCRM na VPS, com a marca Afatec

Roteiro escrito em 15/09/2026 para colar no **Claude Code que roda dentro da VPS**.
Baseado no DeskcommCRM **v1.27.2** (`melgarafael/DeskcommCRM`, MIT), lido commit a commit,
e no que já está de pé na VPS da Afatec.

> **Para o Allisson, antes de colar:** cada bloco abaixo é autocontido e tem como conferir
> que deu certo. Cole um de cada vez, na ordem, e só siga para o próximo quando a
> verificação passar. O **Bloco 0 é um diagnóstico** — ele pode dizer que a VPS não
> aguenta, e aí é melhor saber antes de instalar do que depois.

## Decisões já tomadas, e por quê

| Decisão | Por quê |
|---|---|
| **Banco no Supabase Cloud (plano grátis)** | O `public` do Supabase da VPS é do **zapmax em produção**, e as 242 migrations do DeskcommCRM são escritas para `public`. Um segundo Supabase self-hosted comeria mais ~1 GB de RAM e o próprio guia do projeto diz que self-hosted "funciona, mas não é coberto". O plano grátis é free, com backup gerenciado. Limites a saber: **500 MB de banco** e o projeto **hiberna após 7 dias sem tráfego** (com WhatsApp ligado, não hiberna). |
| **Domínio `crm.afatec.net`** | O CRM atual continua no ar em `crm-afatec.gddktt.easypanel.host` até você aprovar o novo. Nada é desligado nesta instalação. |
| **Proxy: o Traefik do EasyPanel** | O kit detecta sozinho e publica o app por ele, sem subir o Caddy dele. Ninguém encosta no Traefik do EasyPanel. |
| **WAHA com número NOVO** | O WhatsApp só aceita um pareamento por número. O chip do Agente Express está na Evolution API — parear o mesmo número no WAHA **derruba a Evolution**. |
| **IA fica para depois** | O CRM sobe sem chave. Você cadastra pela tela depois (IA › Credenciais), e o OpenRouter tem modelos gratuitos. |
| **Chamada de voz (WaCalls) DESLIGADA** | Vincula um segundo aparelho ao número por caminho não oficial — risco de banimento da conta. Nasce desligada e fica assim. |

---

## Bloco 0 — Diagnóstico: a VPS aguenta?

```
Você está no Claude Code da VPS da Afatec. NÃO instale nada ainda. Este passo é só
diagnóstico, e a resposta dele decide se seguimos.

Quero subir o DeskcommCRM nesta VPS. Ele são 7 contêineres e, segundo o próprio
projeto, os picos MEDIDOS são: app 335 MiB (teto 768m), worker 230 MiB (teto 512m),
WAHA 893 MiB (teto 1280m), mais redis, srh, scheduler e o proxy. Na prática preciso
de ~2,5 GB de RAM livre e ~10 GB de disco livre.

Faça o levantamento e me responda em texto, sem mudar nada:

1. RAM total, usada e disponível:            free -h
2. Swap configurado:                         swapon --show
3. Disco livre em / e em /var/lib/docker:    df -h / /var/lib/docker
4. Consumo atual por contêiner:              docker stats --no-stream --format \
                                             "table {{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}"
5. Quem ocupa as portas 80 e 443:            ss -tlnp | grep -E ':80 |:443 '
6. O Traefik do EasyPanel: nome do contêiner, se roda em --network host ou em bridge
   própria, e o nome dessa rede:             docker ps --format '{{.Names}}\t{{.Image}}' | grep -i traefik
                                             docker inspect <nome> --format '{{json .NetworkSettings.Networks}}'
7. Versão do docker e se o compose v2 existe: docker --version && docker compose version

Depois me diga, com os números na mão:
- Sobra RAM para mais ~2,5 GB? Se não sobra, quanto falta e o que está comendo.
- Há swap? Se não houver e a RAM estiver apertada, proponha (sem executar) criar
  um swapfile de 4 GB.
- O Traefik do EasyPanel está em modo host ou em bridge própria? (isso muda a rede
  que o instalador vai usar)

NÃO instale, NÃO pare contêiner nenhum, NÃO mexa no Supabase, no n8n, na Evolution
API nem no CRM que já está no ar em /opt/crm-afatec. Só relate.
```

**Como saber que deu certo:** você tem um relatório com os números, e uma resposta clara
sobre sobrar ou não ~2,5 GB de RAM. Se não sobrar, pare aqui e me mande o relatório.

---

## Bloco 1 — DNS do `crm.afatec.net`

Este passo é **seu**, no painel do Cloudflare, não do agente:

1. No DNS do `afatec.net`, crie (ou edite) um registro **A** para `crm` apontando para o
   **IP da VPS**.
2. **Desligue o proxy do Cloudflare nesse registro** — a nuvem tem que ficar **cinza**, não
   laranja. Com a nuvem laranja o Let's Encrypt não consegue validar o domínio pelo
   Traefik e o HTTPS nunca é emitido.

Depois, no agente da VPS:

```
Confira se o DNS do CRM novo já está apontando para esta VPS:

  dig +short crm.afatec.net
  curl -s ifconfig.me ; echo

Os dois têm que devolver o MESMO IP. Se o dig devolver um IP da Cloudflare
(faixas 104.x, 172.67.x, 188.114.x) é porque o proxy laranja está ligado — me avise
que eu desligo lá. Não siga enquanto os dois IPs não baterem.
```

**Como saber que deu certo:** `dig +short crm.afatec.net` devolve exatamente o IP da VPS.

---

## Bloco 2 — Criar o projeto no Supabase Cloud

Este também é **seu**, e leva 3 minutos:

1. Entre em [supabase.com](https://supabase.com) e crie um projeto novo na região
   **South America (São Paulo) — sa-east-1**. Guarde a senha do banco que ele pedir.
2. Gere um token de conta em
   [supabase.com/dashboard/account/tokens](https://supabase.com/dashboard/account/tokens).
   Com ele o instalador configura sozinho os links dos e-mails de acesso (sem isso, o
   "esqueci minha senha" chega apontando para `localhost:3000` e ninguém consegue entrar).

> ⚠️ Esse token é chave mestra da sua conta Supabase. O instalador **não grava** ele em
> disco — usa uma vez e some com o processo. Não cole esse token em chat nenhum, inclusive
> aqui comigo: ele vai direto na VPS.

3. Em **Settings → API**, copie: *Project URL*, *anon key*, *service_role key*.
4. Em **Settings → Database → Connection string**, copie a do **Session pooler, modo URI**.
   > A *Direct connection* é IPv6-only e **não conecta de um VPS IPv4** — é o erro mais
   > comum dessa instalação.

**Como saber que deu certo:** você tem as 4 credenciais e o token, e o projeto no painel do
Supabase está com o status verde (`ACTIVE_HEALTHY`). Projeto recém-criado leva uns minutos.

---

## Bloco 3 — Instalar o DeskcommCRM

```
Vamos instalar o DeskcommCRM nesta VPS. Regras que valem o tempo todo:

  - NÃO pare nem reconfigure o Traefik do EasyPanel.
  - NÃO toque no Supabase self-hosted desta VPS (o schema public é do zapmax em
    produção), nem no n8n, nem na Evolution API.
  - NÃO desligue o CRM antigo em /opt/crm-afatec — ele fica no ar em paralelo.
  - O banco deste CRM novo é um projeto no Supabase CLOUD, não o daqui.

Passos:

1. Clone o projeto fora dos caminhos existentes:

     cd /opt
     git clone --depth 1 https://github.com/melgarafael/DeskcommCRM.git deskcommcrm
     cd /opt/deskcommcrm

2. Rode o instalador em modo interativo. Ele detecta sozinho que esta VPS já tem um
   Traefik e grava REVERSE_PROXY=traefik:

     bash hostgator-setup-kit/install.sh

   Se ele PERGUNTAR se é o Traefik que atende o domínio (ele pergunta quando o proxy
   roda em --network host, que é o caso da Hostinger), responda que SIM e me mostre o
   que ele encontrou antes de confirmar.

3. Responda as perguntas assim:

     Domínio do CRM .................... crm.afatec.net
     Seu e-mail (avisos de SSL) ........ <o e-mail do Allisson>
     Imagem Docker do app .............. Enter (aceita a última versão publicada)
     Supabase Project URL .............. <Project URL do Supabase Cloud>
     Supabase anon key ................. <anon key>
     Supabase service_role key ......... <service_role key>
     Supabase connection string ........ <a do SESSION POOLER, modo URI>
     Token de acesso do Supabase ....... <o token de conta> (não fica salvo)
     Chave de IA ....................... Enter (pula — cadastramos depois pela tela)
     E-mail do primeiro admin .......... <e-mail do Allisson>
     Senha do primeiro admin ........... <senha forte, no mínimo 8 caracteres>
     Nome na interface ................. Afatec CRM
     Idioma ............................ 1 (Português)
     Cor da marca em hex ............... #0090FE
     E-mail de suporte ................. Enter (pula)
     Chave da Resend ................... Enter (pula)
     Remetente dos e-mails ............. Enter (pula)

   Na tela de conferência, confira item por item ANTES de dar Enter — principalmente
   o domínio e a connection string.

4. Quando terminar, me mostre:

     cd /opt/deskcommcrm
     grep -E '^(DOMAIN|REVERSE_PROXY|TRAEFIK_NETWORK|TRAEFIK_ENTRYPOINT|TRAEFIK_CERTRESOLVER|APP_IMAGE|APP_NAME|APP_ACCENT_HEX|COMPOSE_PROFILES)=' .env
     docker compose -f docker-compose.prod.yml -f docker-compose.traefik.yml ps

   Espero ver REVERSE_PROXY=traefik, TRAEFIK_NETWORK com o nome da rede do Traefik do
   EasyPanel, COMPOSE_PROFILES vazio (chamada de voz desligada) e os contêineres app,
   worker, waha, redis, srh e scheduler de pé — sem nenhum caddy.

Se o TRAEFIK_ENTRYPOINT/TRAEFIK_CERTRESOLVER do EasyPanel não forem
"websecure"/"letsencrypt", corrija no .env e suba de novo com os DOIS arquivos de
compose. Não rode "docker compose up -d caddy" nunca: nomear o serviço liga o profile
dele e ele vai brigar pelas portas 80/443 com o EasyPanel.
```

**Como saber que deu certo:** os 6 contêineres de pé, nenhum `caddy`, e
`https://crm.afatec.net` abrindo a tela de login com cadeado válido.

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

3. Aplique e suba a marca dos e-mails de acesso (assunto, corpo, cor do botão, Site URL
   e Redirect URLs do GoTrue):

     cd /opt/deskcommcrm
     docker compose -f docker-compose.prod.yml -f docker-compose.traefik.yml up -d
     bash hostgator-setup-kit/marca-emails.sh

4. Me mostre o resultado do marca-emails.sh e confirme que ele configurou o Site URL
   como https://crm.afatec.net e o Redirect como https://crm.afatec.net/auth/confirm.
```

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
5. **Swap de 4 GB**, se o Bloco 0 mostrar RAM apertada. Sem swap, o OOM killer escolhe a
   vítima por quem cresceu mais rápido — pode ser o zapmax em produção, não o CRM novo.
