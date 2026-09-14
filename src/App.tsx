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

export default function App() {
  const { carregando, sessao } = useSessao()

  if (carregando) {
    return <div className="flex min-h-screen items-center justify-center text-slate-400">Carregando…</div>
  }

  if (!sessao) return <Login />

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
