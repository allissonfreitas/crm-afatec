# CRM Afatec

CRM da Afatec: funil de vendas, clientes, agenda e **ligação de entrada** (o "liguin"),
rodando em cima do **Supabase self-hosted** da VPS.

> Este Supabase é compartilhado com outras aplicações, então o CRM vive inteiro no schema
> **`crm`** — tabelas, enums, funções, views e RLS. O `public` não é tocado. O `auth.users`
> é compartilhado (é um GoTrue só), e o CRM usa o gatilho `on_auth_user_created_crm`, de
> nome próprio, que convive com os gatilhos dos outros apps. Quem entra de fato no CRM é
> controlado por `crm.profiles` + RLS.

## Stack

React 18 + TypeScript + Vite + Tailwind + Supabase JS. Tudo aberto e gratuito.

## Estrutura

```
db/        migrações SQL (rodar na ordem 01 → 02 → 03 → 04)
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
4. `db/04_telefone_chave.sql` — chave de telefone tolerante ao nono dígito e as funções
   que a integração com o WhatsApp usa

Depois crie o primeiro usuário em Authentication → Users e promova:

```sql
update crm.profiles set papel = 'admin' where email = 'seu@email.com';
```

E exponha o schema na API REST: acrescente `crm` a `PGRST_DB_SCHEMAS` no stack do
Supabase e reinicie o serviço REST. Sem isso o app recebe 404 em tudo.

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
  -H "Content-Profile: crm" \
  -H "Content-Type: application/json" \
  -d '{"p_provedor":"asterisk","p_id_externo":"1726337812.45","p_evento":"ringing",
       "p_numero_origem":"5531988887777","p_numero_destino":"1130000000","p_ramal":"1001"}'
```

O header `Content-Profile: crm` é obrigatório: é ele que diz ao PostgREST em qual schema
procurar a função.

Eventos aceitos em `p_evento`: `ringing`, `answered`, `hangup`. O banco identifica o
cliente pelo telefone, o atendente pelo ramal, calcula a duração e registra a ligação
na timeline do cliente sozinho. O app escuta via Supabase Realtime e abre o pop-up.

Os buckets de storage são `crm-marca` (público, logo e favicon), `crm-anexos` e
`crm-gravacoes` (privados).

A `service_role` fica **só no servidor** (n8n ou Edge Function). Nunca no `.env` do app.
