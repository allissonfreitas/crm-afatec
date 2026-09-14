import { NavLink, Outlet } from 'react-router-dom'
import { useSessao } from '../contexto/SessaoContext'
import { LiguinEntrada } from './LiguinEntrada'
import { iniciais } from '../lib/formato'

const LOGO_PADRAO = '/logo-afatec-256.png'

const menu = [
  { para: '/', rotulo: 'Dashboard', fim: true },
  { para: '/funil', rotulo: 'Funil' },
  { para: '/clientes', rotulo: 'Clientes' },
  { para: '/ligacoes', rotulo: 'Ligações' },
  { para: '/agenda', rotulo: 'Agenda' },
  { para: '/configuracoes', rotulo: 'Configurações' },
]

export function Layout() {
  const { perfil, config, sair } = useSessao()

  return (
    <div className="flex min-h-screen">
      <aside className="hidden w-60 shrink-0 flex-col text-white md:flex" style={{ background: 'var(--cor-secundaria)' }}>
        <div className="flex h-16 items-center gap-2 px-5">
          <img
            src={config?.logo_escura_url ?? config?.logo_url ?? LOGO_PADRAO}
            alt={config?.nome_empresa ?? 'Afatec'}
            className="h-10 w-10 shrink-0 object-contain"
          />
          <span className="truncate font-semibold">{config?.nome_empresa ?? 'Afatec'}</span>
        </div>

        <nav className="flex-1 space-y-1 px-3 py-4">
          {menu.map((m) => (
            <NavLink
              key={m.para}
              to={m.para}
              end={m.fim}
              className={({ isActive }) =>
                `block rounded-lg px-3 py-2 text-sm transition ${
                  isActive ? 'bg-white/15 font-medium' : 'text-white/70 hover:bg-white/10'
                }`
              }
            >
              {m.rotulo}
            </NavLink>
          ))}
        </nav>

        <div className="border-t border-white/10 px-5 py-4">
          <div className="flex items-center gap-3">
            <div className="flex h-9 w-9 items-center justify-center rounded-full bg-white/15 text-sm font-semibold">
              {iniciais(perfil?.nome)}
            </div>
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm">{perfil?.nome}</p>
              <p className="text-xs text-white/60">{perfil?.papel}</p>
            </div>
          </div>
          <button onClick={() => void sair()} className="mt-3 text-xs text-white/60 hover:text-white">
            Sair
          </button>
        </div>
      </aside>

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex h-14 items-center gap-3 border-b border-slate-200 bg-white px-4 md:hidden">
          <img src={config?.logo_url ?? LOGO_PADRAO} alt="" className="h-8 w-8 object-contain" />
          <span className="font-semibold">{config?.nome_empresa ?? 'CRM'}</span>
          <button onClick={() => void sair()} className="ml-auto text-sm text-slate-500">
            Sair
          </button>
        </header>

        <nav className="flex gap-1 overflow-x-auto border-b border-slate-200 bg-white px-2 py-2 md:hidden">
          {menu.map((m) => (
            <NavLink
              key={m.para}
              to={m.para}
              end={m.fim}
              className={({ isActive }) =>
                `whitespace-nowrap rounded-lg px-3 py-1.5 text-sm ${
                  isActive ? 'bg-slate-100 font-medium' : 'text-slate-500'
                }`
              }
            >
              {m.rotulo}
            </NavLink>
          ))}
        </nav>

        <main className="flex-1 overflow-x-hidden p-4 md:p-6">
          <Outlet />
        </main>
      </div>

      <LiguinEntrada />
    </div>
  )
}
