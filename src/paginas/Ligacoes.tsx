import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { Cartao, Carregando, Etiqueta, Indicador, Titulo, Vazio } from '../componentes/ui'
import { dataHora, duracao, telefone } from '../lib/formato'
import type { Chamada } from '../lib/tipos'

const PERIODOS = [
  { rotulo: 'Hoje', dias: 0 },
  { rotulo: '7 dias', dias: 7 },
  { rotulo: '30 dias', dias: 30 },
]

export function Ligacoes() {
  const [carregando, setCarregando] = useState(true)
  const [chamadas, setChamadas] = useState<Chamada[]>([])
  const [dias, setDias] = useState(7)
  const [somentePerdidas, setSomentePerdidas] = useState(false)

  useEffect(() => {
    setCarregando(true)
    const desde = new Date()
    if (dias === 0) desde.setHours(0, 0, 0, 0)
    else desde.setDate(desde.getDate() - dias)

    void supabase
      .from('chamadas')
      .select('*, clientes(id, nome), profiles(nome)')
      .gte('iniciada_em', desde.toISOString())
      .order('iniciada_em', { ascending: false })
      .limit(500)
      .then(({ data }) => {
        setChamadas((data as Chamada[]) ?? [])
        setCarregando(false)
      })
  }, [dias])

  const lista = useMemo(
    () => (somentePerdidas ? chamadas.filter((c) => c.status === 'perdida' || c.status === 'nao_atendida') : chamadas),
    [chamadas, somentePerdidas],
  )

  const perdidas = chamadas.filter((c) => c.status === 'perdida' || c.status === 'nao_atendida').length
  const atendidas = chamadas.filter((c) => c.status === 'atendida').length
  const duracoes = chamadas.map((c) => c.duracao_segundos).filter((v): v is number => v !== null)
  const media = duracoes.length ? Math.round(duracoes.reduce((a, b) => a + b, 0) / duracoes.length) : null

  return (
    <>
      <Titulo>Ligações</Titulo>

      <div className="mb-4 flex flex-wrap items-center gap-2">
        {PERIODOS.map((p) => (
          <button
            key={p.rotulo}
            onClick={() => setDias(p.dias)}
            className={`rounded-lg px-3 py-1.5 text-sm ${dias === p.dias ? 'bg-slate-900 text-white' : 'bg-white border border-slate-300'}`}
          >
            {p.rotulo}
          </button>
        ))}
        <label className="ml-2 flex items-center gap-2 text-sm text-slate-600">
          <input type="checkbox" checked={somentePerdidas} onChange={(e) => setSomentePerdidas(e.target.checked)} />
          só perdidas
        </label>
      </div>

      <div className="mb-4 grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Indicador rotulo="Total" valor={chamadas.length} />
        <Indicador rotulo="Atendidas" valor={atendidas} />
        <Indicador rotulo="Perdidas" valor={perdidas} />
        <Indicador rotulo="Duração média" valor={duracao(media)} />
      </div>

      {carregando ? (
        <Carregando />
      ) : (
        <Cartao className="overflow-x-auto p-0">
          {lista.length === 0 ? (
            <Vazio>Nenhuma ligação no período.</Vazio>
          ) : (
            <table className="w-full text-sm">
              <thead className="border-b border-slate-200 text-left text-xs uppercase tracking-wide text-slate-500">
                <tr>
                  <th className="px-4 py-3">Quando</th>
                  <th className="px-4 py-3">Número</th>
                  <th className="px-4 py-3">Cliente</th>
                  <th className="px-4 py-3">Atendente</th>
                  <th className="px-4 py-3">Status</th>
                  <th className="px-4 py-3">Duração</th>
                  <th className="px-4 py-3">Gravação</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {lista.map((c) => (
                  <tr key={c.id} className="hover:bg-slate-50">
                    <td className="whitespace-nowrap px-4 py-3 text-slate-600">{dataHora(c.iniciada_em)}</td>
                    <td className="whitespace-nowrap px-4 py-3">{telefone(c.numero_origem)}</td>
                    <td className="px-4 py-3">
                      {c.clientes ? (
                        <Link to={`/clientes/${c.clientes.id}`} className="hover:underline">{c.clientes.nome}</Link>
                      ) : (
                        <span className="text-slate-400">não cadastrado</span>
                      )}
                    </td>
                    <td className="px-4 py-3 text-slate-600">{c.profiles?.nome ?? '—'}</td>
                    <td className="px-4 py-3"><Etiqueta valor={c.status} /></td>
                    <td className="whitespace-nowrap px-4 py-3 text-slate-600">{duracao(c.duracao_segundos)}</td>
                    <td className="px-4 py-3">
                      {c.gravacao_url ? <audio controls src={c.gravacao_url} className="h-8 w-44" /> : '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </Cartao>
      )}
    </>
  )
}
