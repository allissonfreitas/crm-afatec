# Roteiro para o agente da VPS

Seis etapas, **nesta ordem**. Cada bloco é um prompt inteiro: copie do começo ao fim e
cole no seu agente da VPS. Só passe para a etapa seguinte quando a anterior terminar.

As etapas 1, 2, 3, 5 e 6 rodam na VPS. A **etapa 4 é sua**, aqui no chat.

Nenhum prompt contém senha ou chave: o agente lê tudo das variáveis de ambiente da VPS.

---

## Etapa 1 — Aplicar o banco no Supabase

```
Você está na minha VPS, onde roda meu Supabase self-hosted. Preciso aplicar as migrações
do meu CRM no banco dele.

1. Baixe os arquivos SQL do repositório https://github.com/allissonfreitas/crm-afatec
   (pasta db/). Se o repositório for privado e você não tiver credencial do GitHub, pare
   e me avise para eu te passar os arquivos de outro jeito.

2. Descubra como acessar o Postgres do Supabase nesta VPS. Procure o container do banco
   (algo como supabase-db ou supabase_db_*) com `docker ps`, e a senha do Postgres na
   variável de ambiente POSTGRES_PASSWORD do próprio container ou no .env do stack do
   Supabase. NÃO me peça a senha e NÃO escreva ela em nenhum arquivo: leia do ambiente.

3. Antes de mexer em qualquer coisa, faça um dump de segurança do banco atual em
   /root/backups/supabase-antes-do-crm-$(date +%F-%H%M).sql e me diga o tamanho do arquivo.

4. Rode os três arquivos NESTA ORDEM, cada um com ON_ERROR_STOP ligado, parando no
   primeiro erro:
      db/01_schema.sql
      db/02_rls.sql
      db/03_seed.sql

5. Se algum der erro, PARE, não tente contornar, e me mostre a mensagem exata com o
   número da linha.

6. No fim, confirme rodando estas conferências e me mostre o resultado:
   - `select count(*) from public.etapas;`            (esperado: 7)
   - `select count(*) from public.origens;`           (esperado: 8)
   - `select nome_empresa, cor_primaria from public.configuracoes;`
   - `select tablename from pg_tables where schemaname='public' order by 1;`
   - `select tablename, rowsecurity from pg_tables where schemaname='public' and not rowsecurity;`
     (esperado: nenhuma linha, ou só as views)

Me responda com o resultado dessas conferências.
```

---

## Etapa 2 — Criar o meu usuário admin

```
No meu Supabase self-hosted nesta VPS, crie o meu usuário do CRM e me deixe como
administrador.

1. Crie o usuário pelo painel do Supabase Studio (Authentication → Users → Add user)
   ou pela API de admin do GoTrue, usando a SERVICE_ROLE_KEY que já está nas variáveis
   de ambiente da VPS. Não escreva a chave em arquivo nenhum e não me peça ela.
   E-mail: o meu e-mail principal. Marque o e-mail como confirmado.
   Se você não souber qual é o meu e-mail, me pergunte antes de criar.

2. Escolha uma senha forte e aleatória, e me mostre ela UMA vez na sua resposta para eu
   trocar depois. Não salve em arquivo.

3. Depois de criado, rode no Postgres:
      update public.profiles set papel = 'admin', ramal = '1001'
      where email = '<o e-mail que você criou>';

4. Confirme e me mostre: `select nome, email, papel, ramal from public.profiles;`

Se a tabela profiles estiver vazia depois de criar o usuário, o gatilho
on_auth_user_created não rodou: me avise em vez de inserir a linha na mão.
```

---

## Etapa 3 — Subir a logo da Afatec

```
Preciso publicar a logo da Afatec no storage do meu Supabase self-hosted nesta VPS.

1. O arquivo da logo está no repositório https://github.com/allissonfreitas/crm-afatec
   em public/logo-afatec.png (512x512, PNG com fundo transparente). Baixe de lá.
   Se não conseguir acessar o repositório, me avise que eu te mando o arquivo.

2. Envie para o bucket público `marca`, no caminho `marca/logo.png`, usando a API de
   storage do Supabase com a SERVICE_ROLE_KEY que já está nas variáveis de ambiente
   da VPS. O bucket já foi criado pela migração; se não existir, crie como público.

3. Envie também public/favicon.png como `marca/favicon.png`.

4. Grave as URLs públicas na tabela de configuração:
      update public.configuracoes
      set logo_url = '<url publica de marca/logo.png>',
          favicon_url = '<url publica de marca/favicon.png>'
      where id = 1;

5. Confirme que as URLs abrem no navegador sem login (o bucket é público) e me mande
   as duas URLs.
```

---

## Etapa 4 — Me mandar os dados de conexão (essa etapa é sua, aqui no chat)

Depois da etapa 3, me mande **aqui na thread**:

- a **URL** do seu Supabase (ex.: `https://supabase.seudominio.com.br`)
- a **anon key** (a chave pública, aquela que vai no navegador)

A `service_role` **não** me mande: ela nunca sai da VPS.

Com isso eu fecho a configuração do app e te devolvo pronto para publicar.

---

## Etapa 5 — Publicar o app na VPS

```
Preciso publicar meu CRM nesta VPS.

1. Clone https://github.com/allissonfreitas/crm-afatec em /opt/crm-afatec
   (se já existir, dê git pull).

2. Crie o arquivo .env na raiz do projeto com:
      VITE_SUPABASE_URL=<a URL do meu Supabase self-hosted desta VPS>
      VITE_SUPABASE_ANON_KEY=<a anon key do meu Supabase, a chave PÚBLICA>
   Pegue os dois valores das variáveis de ambiente do stack do Supabase nesta VPS.
   NUNCA coloque a service_role neste arquivo: ele vira JavaScript no navegador.

3. Rode `npm ci` (ou `npm install`) e `npm run build`. Se o build falhar, PARE e me
   mostre o erro completo.

4. Publique o conteúdo da pasta dist/ como site estático, no mesmo padrão que os meus
   outros serviços já usam nesta VPS (Easypanel/Nginx/Traefik, o que estiver em uso),
   em um subdomínio tipo crm.meudominio.com.br, com HTTPS.

5. IMPORTANTE: é uma SPA com rotas no cliente. Configure o fallback de 404 para
   /index.html, senão recarregar em /clientes/algum-id vai dar erro.

6. Me mande a URL final e confirme que a tela de login abre com a logo da Afatec.
```

---

## Etapa 6 — Ligar a central telefônica (só depois que o CRM estiver no ar)

```
Quero que as ligações que chegam na minha central apareçam em tempo real no meu CRM,
que já está rodando em cima do Supabase self-hosted desta VPS.

O banco já tem o ponto de entrada pronto: a função registrar_chamada, chamada via
PostgREST em POST /rest/v1/rpc/registrar_chamada. Ela é idempotente: pode receber os
três eventos do mesmo id_externo na ordem que vier.

Corpo da requisição:
  p_provedor       texto, ex "asterisk"
  p_id_externo     id único da chamada no provedor (uniqueid / callsid)
  p_evento         "ringing", "answered" ou "hangup"
  p_direcao        "entrada" ou "saida"
  p_numero_origem  quem está ligando
  p_numero_destino número chamado
  p_ramal          ramal que tocou (é o que amarra a ligação ao atendente)
  p_gravacao_url   URL da gravação, quando existir (manda no hangup)

Autenticação: header `apikey` e `Authorization: Bearer` com a SERVICE_ROLE_KEY que já
está nas variáveis de ambiente desta VPS. Não escreva a chave em arquivo de workflow
em texto puro: use credencial/variável de ambiente.

1. Primeiro me diga qual central de telefonia está rodando ou acessível nesta VPS
   (Asterisk, FreePBX, Issabel, algum SIP externo) e como ela notifica eventos hoje.
   Se não houver nenhuma, me diga isso e pare aqui.

2. Com base no que existir, crie no meu n8n um workflow chamado "CRM - Ligação de
   entrada" com: um nó Webhook recebendo o evento da central, um nó Code que traduz o
   payload dela para os campos acima, e um nó HTTP Request chamando a RPC.

3. Trate os três momentos: ringing, answered e hangup. No hangup, se a central
   disponibilizar a gravação, mande a URL em p_gravacao_url.

4. Teste com uma ligação real e me confirme: a linha apareceu em public.chamadas, com
   cliente_id preenchido quando o número já é cadastrado, atendente_id preenchido pelo
   ramal, e duracao_segundos calculada.

5. Me mande o resumo do que você montou e o que ficou faltando.
```

---

## O que fica para depois (sugestões)

Nenhuma destas é necessária para o CRM funcionar, mas todas valem a pena e são gratuitas:

1. **Transcrição e resumo da ligação** — reaproveitar o Whisper que já roda no AgendaAI:
   gravação → transcrição → resumo pelo Gemini → gravar em `chamadas.transcricao` e
   `chamadas.resumo`. O vendedor lê três linhas em vez de ouvir oito minutos.
2. **WhatsApp na mesma timeline** — workflow no n8n gravando as conversas da Evolution
   em `atividades` com tipo `whatsapp`, para a ficha do cliente ter o histórico inteiro.
3. **Ligação perdida vira tarefa** — `status = 'perdida'` gera uma atividade de retorno
   para o responsável e um aviso no WhatsApp.
4. **Backup diário do Postgres** — `pg_dump` para fora da VPS. O Supabase self-hosted
   não faz isso sozinho, e o CRM vai virar o cadastro de clientes da empresa.
