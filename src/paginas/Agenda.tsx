import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { Cartao, Carregando, Titulo, Vazio } from '../componentes/ui'
import { dataHora } from '../lib/formato'
import type { Atividade } from '../lib/tipos'

export function Agenda() {
  const [carregando, setCarregando] = useState(true)
  const [atividades, setAtividades] = useState<Atividade[]>([])
  const [mostrarConcluidas, setMostrarConcluidas] = useState(false)

  const carregar = useCallback(async () => {
    let q = supabase
      .from('atividades')
      .select('*, clientes(nome)')
      .order('inicio', { ascending: true, nullsFirst: false })
      .limit(200)
    if (!mostrarConcluidas) q = q.eq('concluida', false)
    const { data } = await q
    setAtividades((data as Atividade[]) ?? [])
    setCarregando(false)
  }, [mostrarConcluidas])

  useEffect(() => {
    void carregar()
  }, [carregar])

  async function concluir(a: Atividade) {
    setAtividades((atual) => atual.map((x) => (x.id === a.id ? { ...x, concluida: true } : x)))
    await supabase
      .from('atividades')
      .update({ concluida: true, concluida_em: new Date().toISOString() })
      .eq('id', a.id)
    void carregar()
  }

  const porDia = atividades.reduce<Record<string, Atividade[]>>((acc, a) => {
    const chave = a.inicio ? new Date(a.inicio).toLocaleDateString('pt-BR') : 'Sem data'
    ;(acc[chave] ??= []).push(a)
    return acc
  }, {})

  if (carregando) return <Carregando />

  return (
    <>
      <Titulo
        acao={
          <label className="flex items-center gap-2 text-sm text-slate-600">
            <input
              type="checkbox"
              checked={mostrarConcluidas}
              onChange={(e) => setMostrarConcluidas(e.target.checked)}
            />
            mostrar concluídas
          </label>
        }
      >
        Agenda
      </Titulo>

      {atividades.length === 0 ? (
        <Vazio>Nenhuma atividade.</Vazio>
      ) : (
        <div className="space-y-4">
          {Object.entries(porDia).map(([dia, itens]) => (
            <Cartao key={dia}>
              <h2 className="mb-2 text-sm font-medium text-slate-500">{dia}</h2>
              <ul className="divide-y divide-slate-100">
                {itens.map((a) => (
                  <li key={a.id} className="flex flex-wrap items-center gap-3 py-2 text-sm">
                    <span className="rounded bg-slate-100 px-2 py-0.5 text-xs text-slate-500">{a.tipo}</span>
                    <span className={`min-w-0 flex-1 ${a.concluida ? 'text-slate-400 line-through' : ''}`}>
                      {a.titulo}
                    </span>
                    {a.cliente_id && (
                      <Link to={`/clientes/${a.cliente_id}`} className="text-xs text-slate-500 hover:underline">
                        {a.clientes?.nome ?? 'cliente'}
                      </Link>
                    )}
                    <span className="text-xs text-slate-400">{dataHora(a.inicio)}</span>
                    {!a.concluida && (
                      <button
                        onClick={() => void concluir(a)}
                        className="rounded-lg border border-slate-300 px-2 py-1 text-xs hover:bg-slate-50"
                      >
                        Concluir
                      </button>
                    )}
                  </li>
                ))}
              </ul>
            </Cartao>
          ))}
        </div>
      )}
    </>
  )
}
