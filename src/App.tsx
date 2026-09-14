import { Navigate, Route, Routes } from 'react-router-dom'
import { useSessao } from './contexto/SessaoContext'
import { Layout } from './componentes/Layout'
import { Login } from './paginas/Login'
import { Dashboard } from './paginas/Dashboard'
import { Funil } from './paginas/Funil'
import { Clientes } from './paginas/Clientes'
import { ClienteDetalhe } from './paginas/ClienteDetalhe'
import { Ligacoes } from './paginas/Ligacoes'
import { Agenda } from './paginas/Agenda'
import { Configuracoes } from './paginas/Configuracoes'

function SemAcesso() {
  const { sessao, sair } = useSessao()
  return (
    <div className="flex min-h-screen items-center justify-center bg-slate-100 px-4">
      <div className="w-full max-w-sm space-y-4 rounded-2xl bg-white p-8 text-center shadow-lg">
        <img src="/logo-afatec.png" alt="Afatec" className="mx-auto h-20 w-20 object-contain" />
        <h1 className="text-lg font-semibold">Você ainda não tem acesso ao CRM</h1>
        <p className="text-sm text-slate-500">
          Sua conta existe, mas não faz parte da equipe do CRM da Afatec. Peça ao
          administrador para liberar o seu acesso.
        </p>
        <p className="text-xs text-slate-400">{sessao?.user?.email}</p>
        <button
          onClick={() => void sair()}
          className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm hover:bg-slate-50"
        >
          Sair
        </button>
      </div>
    </div>
  )
}

export default function App() {
  const { carregando, perfilCarregado, sessao, perfil } = useSessao()

  if (carregando) {
    return <div className="flex min-h-screen items-center justify-center text-slate-400">Carregando…</div>
  }

  if (!sessao) return <Login />

  if (!perfilCarregado) {
    return <div className="flex min-h-screen items-center justify-center text-slate-400">Carregando…</div>
  }

  // logado no Supabase, mas sem linha ativa em crm.profiles
  if (!perfil || !perfil.ativo) return <SemAcesso />

  return (
    <Routes>
      <Route element={<Layout />}>
        <Route index element={<Dashboard />} />
        <Route path="funil" element={<Funil />} />
        <Route path="clientes" element={<Clientes />} />
        <Route path="clientes/:id" element={<ClienteDetalhe />} />
        <Route path="ligacoes" element={<Ligacoes />} />
        <Route path="agenda" element={<Agenda />} />
        <Route path="configuracoes" element={<Configuracoes />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  )
}
