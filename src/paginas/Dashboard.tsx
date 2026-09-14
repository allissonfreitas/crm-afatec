import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { Cartao, Carregando, Indicador, Titulo, Vazio } from '../componentes/ui'
import { duracao, moeda, telefone } from '../lib/formato'
import type { Atividade, Chamada } from '../lib/tipos'

type LinhaFunil = { etapa_id: string; etapa: string; ordem: number; qtd: number; valor_total: number }

export function Dashboard() {
  const [carregando, setCarregando] = useState(true)
  const [funil, setFunil] = useState<LinhaFunil[]>([])
  const [chamadas, setChamadas] = useState<Chamada[]>([])
  const [tarefas, setTarefas] = useState<Atividade[]>([])

  useEffect(() => {
    const inicioDoDia = new Date()
    inicioDoDia.setHours(0, 0, 0, 0)

    async function carregar() {
      const [f, c, t] = await Promise.all([
        supabase.from('vw_funil_resumo').select('*').order('ordem'),
        supabase
          .from('chamadas')
          .select('*, clientes(id, nome)')
          .gte('iniciada_em', inicioDoDia.toISOString())
          .order('iniciada_em', { ascending: false }),
        supabase
          .from('atividades')
          .select('*, clientes(nome)')
          .eq('concluida', false)
          .order('inicio', { ascending: true })
          .limit(8),
      ])
      setFunil((f.data as LinhaFunil[]) ?? [])
      setChamadas((c.data as Chamada[]) ?? [])
      setTarefas((t.data as Atividade[]) ?? [])
      setCarregando(false)
    }
    void carregar()
  }, [])

  if (carregando) return <Carregando />

  const recebidas = chamadas.filter((c) => c.direcao === 'entrada')
  const perdidas = recebidas.filter((c) => c.status === 'perdida' || c.status === 'nao_atendida')
  const esperas = recebidas.map((c) => c.espera_segundos).filter((v): v is number => v !== null)
  const esperaMedia = esperas.length ? Math.round(esperas.reduce((a, b) => a + b, 0) / esperas.length) : null
  const valorEmAberto = funil.reduce((a, l) => a + Number(l.valor_total), 0)
  const maiorEtapa = Math.max(1, ...funil.map((l) => Number(l.valor_total)))

  return (
    <>
      <Titulo>Dashboard</Titulo>

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Indicador rotulo="Ligações hoje" valor={recebidas.length} detalhe="recebidas" />
        <Indicador
          rotulo="Perdidas"
          valor={perdidas.length}
          detalhe={recebidas.length ? `${Math.round((perdidas.length / recebidas.length) * 100)}% do total` : 'nenhuma ligação ainda'}
        />
        <Indicador rotulo="Espera média" valor={duracao(esperaMedia)} detalhe="até o atendimento" />
        <Indicador rotulo="Em negociação" valor={moeda(valorEmAberto)} detalhe="oportunidades abertas" />
      </div>

      <div className="mt-6 grid gap-4 lg:grid-cols-2">
        <Cartao>
          <h2 className="mb-3 font-medium">Funil por etapa</h2>
          {funil.length === 0 ? (
            <Vazio>Nenhuma etapa configurada ainda.</Vazio>
          ) : (
            <ul className="space-y-2">
              {funil.map((l) => (
                <li key={l.etapa_id}>
                  <div className="flex justify-between text-sm">
                    <span>{l.etapa} <span className="text-slate-400">({l.qtd})</span></span>
                    <span className="tabular-nums text-slate-600">{moeda(Number(l.valor_total))}</span>
                  </div>
                  <div className="mt-1 h-2 rounded-full bg-slate-100">
                    <div
                      className="h-2 rounded-full"
                      style={{
                        width: `${Math.max(2, (Number(l.valor_total) / maiorEtapa) * 100)}%`,
                        background: 'var(--cor-primaria)',
                      }}
                    />
                  </div>
                </li>
              ))}
            </ul>
          )}
        </Cartao>

        <Cartao>
          <h2 className="mb-3 font-medium">Últimas ligações de hoje</h2>
          {recebidas.length === 0 ? (
            <Vazio>Nenhuma ligação registrada hoje.</Vazio>
          ) : (
            <ul className="divide-y divide-slate-100">
              {recebidas.slice(0, 6).map((c) => (
                <li key={c.id} className="flex items-center gap-3 py-2 text-sm">
                  <span className={`h-2 w-2 shrink-0 rounded-full ${c.status === 'perdida' ? 'bg-rose-500' : 'bg-emerald-500'}`} />
                  <div className="min-w-0 flex-1">
                    {c.clientes ? (
                      <Link to={`/clientes/${c.clientes.id}`} className="truncate font-medium hover:underline">
                        {c.clientes.nome}
                      </Link>
                    ) : (
                      <span className="text-slate-500">Não cadastrado</span>
                    )}
                    <p className="text-xs text-slate-400">{telefone(c.numero_origem)}</p>
                  </div>
                  <span className="shrink-0 text-xs text-slate-500">{duracao(c.duracao_segundos)}</span>
                </li>
              ))}
            </ul>
          )}
          <Link to="/ligacoes" className="mt-3 inline-block text-sm text-slate-500 hover:underline">
            Ver todas as ligações
          </Link>
        </Cartao>
      </div>

      <Cartao className="mt-4">
        <h2 className="mb-3 font-medium">Tarefas em aberto</h2>
        {tarefas.length === 0 ? (
          <Vazio>Nada pendente. Bom trabalho.</Vazio>
        ) : (
          <ul className="divide-y divide-slate-100">
            {tarefas.map((t) => (
              <li key={t.id} className="flex items-center gap-3 py-2 text-sm">
                <span className="rounded bg-slate-100 px-2 py-0.5 text-xs text-slate-500">{t.tipo}</span>
                <span className="min-w-0 flex-1 truncate">{t.titulo}</span>
                <span className="shrink-0 text-xs text-slate-400">{t.clientes?.nome ?? ''}</span>
              </li>
            ))}
          </ul>
        )}
      </Cartao>
    </>
  )
}
