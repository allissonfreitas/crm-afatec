# CRM Afatec × DeskcommCRM — comparação

Levantado em 15/09/2026, comparando o repositório `allissonfreitas/crm-afatec`
(branch `main`, commit `5967ccb`) com o `melgarafael/DeskcommCRM` público
(`main`, clone raso de 15/09/2026).

## Resumo

**O CRM da Afatec não herdou nada do DeskcommCRM.** Foi escrito do zero em
14/09/2026. O próprio `PLANO.md`, na primeira linha, registra isso: *"O que está
nesta pasta já roda no seu Supabase da VPS, antes mesmo de eu ver o código do
DeskcommCRM"* — e lista o código do DeskcommCRM como a pendência nº 1, porque a
sessão roda num container na nuvem e nunca enxergou a pasta do OneDrive.

## Escala

| | CRM Afatec | DeskcommCRM |
|---|---|---|
| Linhas de TypeScript/TSX | **1.514** | **541.705** |
| Arquivos .ts/.tsx | 17 | 1.824 |
| Telas / rotas | 8 | ~110 |
| Migrações de banco | 8 arquivos SQL | 242 migrations |
| Licença | privado (repo público, sem licença) | MIT |

O CRM da Afatec tem **0,3%** do tamanho do DeskcommCRM.

## Stack

| | CRM Afatec | DeskcommCRM |
|---|---|---|
| Framework | React 18 + Vite (SPA estática) | Next.js 16 + React 19 (App Router, servidor) |
| UI | Tailwind puro | Tailwind + shadcn/ui |
| Backend | nenhum — o navegador fala direto com o PostgREST | Route Handlers do Next.js (REST + MCP) |
| Banco | Supabase self-hosted, schema `crm`, PG 15.8 | Supabase, **PG 17 + pgvector** |
| Multi-tenant | não (uma empresa só) | sim, isolado por RLS |
| Cache / fila | nenhum | Upstash Redis + `event_log` com workers em cron |
| Deploy | `nginx:alpine` servindo `dist/` | Docker (app + worker + scheduler) ou Vercel |
| IA | nenhuma | Vercel AI SDK (Anthropic, OpenAI, Google, OpenRouter) |
| WhatsApp | nenhum | WAHA (QR code) ou Meta Cloud API |

## Módulos

### O que os dois têm

Login, dashboard, funil kanban, contatos/clientes, ficha do cliente,
agenda/atividades, configurações de marca (logo e cores), equipe.

### Só no DeskcommCRM

- **Inbox de WhatsApp em tempo real** de 3 painéis, com a IA e o humano lado a lado
- **Agentes de IA**: agents, routers, skills, cases, base de conhecimento com RAG, memória, propostas, runs, usage
- **Follow-ups**: máquinas de estado que reengajam lead parado, com enrollments
- **Radar**: quem esfriou e ainda está aberto
- **Automações QUANDO/SE/ENTÃO** e fontes de captação por webhook público
- **Produtos, templates, tarefas, métricas, análise**
- **LGPD**: exportação e anonimização, com fluxo de requisição
- **Segurança**: MFA, tokens de API, audit log append-only, incidentes
- **Onboarding guiado** (conectar WhatsApp, montar funil, convidar equipe)
- **Super-admin**: gestão de tenants, impersonate, billing, usage
- **Integrações**: Nuvemshop, Meta Ads, Google
- **Kit de instalação self-hosted** (`hostgator-setup-kit/install.sh`): sobe app,
  WhatsApp e banco numa VPS com um comando, mais backup, restore, healthcheck,
  diagnóstico e update

### Só no CRM da Afatec

- **Telefonia / liguin**: pop-up de ligação de entrada por Realtime, casamento do
  número com o cliente, casamento do ramal com o atendente, timeline automática,
  gravação com player, RPC `registrar_chamada()`. O DeskcommCRM **não tem nada de
  telefonia** — é WhatsApp de ponta a ponta.

### Planejado no CRM da Afatec e nunca feito

- Tela de **Relatórios** (conversão por etapa, motivo de perda, ligações por hora, ranking)
- Busca de clientes **full-text em português no banco** — hoje é filtro em memória
  sobre as 300 últimas linhas, com filtro só por status (sem responsável nem tag)
- Configurações de **funil e produtos**

## Atrito para adotar o DeskcommCRM na VPS

1. **Não usa Evolution API.** É decisão explícita do projeto
   (`docs/handoffs/HANDOFF-canais-oficial.md`, D1): adapter Meta nativo ou WAHA.
   Adotar significa mais um container de WhatsApp na VPS, em paralelo ao que já roda.
2. **Quer PostgreSQL 17 com pgvector.** O `supabase-db` da VPS é
   `supabase/postgres:15.8.1.085`. O install kit sobe um `pgvector/pgvector:pg17`
   próprio no compose — ou seja, um segundo banco, não o Supabase que já existe.
3. **Precisa de runtime Node**, não dá para servir como estático no nginx.
4. **Upstash Redis** para rate limit (tem plano gratuito).
5. As 242 migrations assumem o schema **`public`** do projeto dele — e o `public`
   da sua VPS é do zapmax em produção. Por isso o banco próprio do compose é o
   caminho, não o Supabase compartilhado.

## Caminhos

**A — Adotar o DeskcommCRM e aposentar o CRM atual.** Roda o `install.sh` na VPS,
troca a marca para Afatec, e o CRM atual vira referência. Ganha inbox de WhatsApp,
IA, automações e LGPD prontos. Perde o liguin (que hoje, aliás, não tem central
telefônica ligada nele). Custo: banco novo no compose, WAHA em vez de Evolution.

**B — Manter o CRM atual e portar ideias.** Fecha as três lacunas do plano
(Relatórios, busca, configurações de funil) e traz de lá só o que interessa.
Mantém Evolution e o Supabase que já está de pé. Mas continua sendo 0,3% do outro,
e cada módulo novo é trabalho do zero.

**C — Os dois.** DeskcommCRM como CRM de verdade, e o liguin como módulo à parte
que escreve na base dele quando a central telefônica existir.
