import type { ReactNode } from 'react'

export function Cartao({ children, className = '' }: { children: ReactNode; className?: string }) {
  return (
    <div className={`rounded-xl border border-slate-200 bg-white p-4 shadow-sm ${className}`}>
      {children}
    </div>
  )
}

export function Indicador({ rotulo, valor, detalhe }: { rotulo: string; valor: ReactNode; detalhe?: string }) {
  return (
    <Cartao>
      <p className="text-xs uppercase tracking-wide text-slate-500">{rotulo}</p>
      <p className="mt-1 text-2xl font-semibold">{valor}</p>
      {detalhe && <p className="mt-1 text-xs text-slate-400">{detalhe}</p>}
    </Cartao>
  )
}

export function Titulo({ children, acao }: { children: ReactNode; acao?: ReactNode }) {
  return (
    <div className="mb-4 flex flex-wrap items-center gap-3">
      <h1 className="text-xl font-semibold">{children}</h1>
      {acao && <div className="ml-auto">{acao}</div>}
    </div>
  )
}

export function Vazio({ children }: { children: ReactNode }) {
  return <p className="py-8 text-center text-sm text-slate-400">{children}</p>
}

export function Carregando() {
  return <p className="py-8 text-center text-sm text-slate-400">Carregando…</p>
}

const coresStatus: Record<string, string> = {
  lead: 'bg-sky-100 text-sky-700',
  prospect: 'bg-indigo-100 text-indigo-700',
  ativo: 'bg-emerald-100 text-emerald-700',
  inativo: 'bg-slate-100 text-slate-600',
  perdido: 'bg-rose-100 text-rose-700',
  atendida: 'bg-emerald-100 text-emerald-700',
  perdida: 'bg-rose-100 text-rose-700',
  tocando: 'bg-amber-100 text-amber-700',
  em_atendimento: 'bg-sky-100 text-sky-700',
}

export function Etiqueta({ valor }: { valor: string }) {
  return (
    <span className={`inline-block rounded-full px-2 py-0.5 text-xs ${coresStatus[valor] ?? 'bg-slate-100 text-slate-600'}`}>
      {valor.replace('_', ' ')}
    </span>
  )
}
