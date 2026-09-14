# CRM Afatec

CRM da Afatec: funil de vendas, clientes, agenda e **ligação de entrada** (o "liguin"),
rodando em cima do **Supabase self-hosted** da VPS.

## Stack

React 18 + TypeScript + Vite + Tailwind + Supabase JS. Tudo aberto e gratuito.

## Estrutura

```
db/        migrações SQL (rodar na ordem 01 → 02 → 03)
public/    logo e ícones da Afatec
src/
  contexto/    sessão, perfil e identidade visual
  componentes/ layout, pop-up do liguin, UI
  paginas/     login, dashboard, funil, clientes, ligações, agenda, configurações
  hooks/       realtime das ligações
  lib/         cliente Supabase, tipos e formatação
```

## Subir o banco

No SQL Editor do seu Supabase, rodar **nesta ordem**:

1. `db/01_schema.sql` — tabelas, triggers, views e a RPC da telefonia
2. `db/02_rls.sql` — Row Level Security e buckets de storage
3. `db/03_seed.sql` — funil padrão, origens, motivos de perda e a identidade da Afatec

Depois crie o primeiro usuário em Authentication → Users e promova:

```sql
update public.profiles set papel = 'admin' where email = 'seu@email.com';
```

## Rodar o app

```bash
cp .env.example .env    # preencha com a URL e a anon key do seu Supabase
npm install
npm run dev
```

## Ligação de entrada

A central telefônica manda os eventos para a RPC `registrar_chamada`, que é idempotente:

```bash
curl -X POST "$SUPABASE_URL/rest/v1/rpc/registrar_chamada" \
  -H "apikey: $SERVICE_ROLE" -H "Authorization: Bearer $SERVICE_ROLE" \
  -H "Content-Type: application/json" \
  -d '{"p_provedor":"asterisk","p_id_externo":"1726337812.45","p_evento":"ringing",
       "p_numero_origem":"5531988887777","p_numero_destino":"1130000000","p_ramal":"1001"}'
```

Eventos aceitos em `p_evento`: `ringing`, `answered`, `hangup`. O banco identifica o
cliente pelo telefone, o atendente pelo ramal, calcula a duração e registra a ligação
na timeline do cliente sozinho. O app escuta via Supabase Realtime e abre o pop-up.

A `service_role` fica **só no servidor** (n8n ou Edge Function). Nunca no `.env` do app.
