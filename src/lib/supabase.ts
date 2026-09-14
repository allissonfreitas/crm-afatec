import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const anon = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined

if (!url || !anon) {
  throw new Error(
    'Faltam VITE_SUPABASE_URL e VITE_SUPABASE_ANON_KEY. Copie o .env.example para .env e preencha com os dados do Supabase da VPS.',
  )
}

// O CRM vive no schema `crm`, nao no `public` — que neste Supabase
// pertence a outra aplicacao. Para a API REST responder, o schema `crm`
// precisa estar em PGRST_DB_SCHEMAS no stack do Supabase.
export const supabase = createClient(url, anon, {
  db: { schema: 'crm' },
  auth: { persistSession: true, autoRefreshToken: true },
  realtime: { params: { eventsPerSecond: 10 } },
})
