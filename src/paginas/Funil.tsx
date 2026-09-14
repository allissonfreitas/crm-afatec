import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { Carregando, Titulo, Vazio } from '../componentes/ui'
import { moeda } from '../lib/formato'
import type { Etapa, Oportunidade } from '../lib/tipos'

export function Funil() {
  const [carregando, setCarregando] = useState(true)
  const [etapas, setEtapas] = useState<Etapa[]>([])
  const [oportunidades, setOportunidades] = useState<Oportunidade[]>([])
  const [arrastando, setArrastando] = useState<string | null>(null)

  const carregar = useCallback(async () => {
    const { data: funil } = await supabase.from('funis').select('id').eq('padrao', true).maybeSingle()
    if (!funil) {
      setCarregando(false)
      return
    }
    const [e, o] = await Promise.all([
      supabase.from('etapas').select('*').eq('funil_id', funil.id).order('ordem'),
      supabase
        .from('oportunidades')
        .select('*, clientes(nome)')
        .eq('funil_id', funil.id)
        .eq('status', 'aberta')
        .order('ordem'),
    ])
    setEtapas((e.data as Etapa[]) ?? [])
    setOportunidades((o.data as Oportunidade[]) ?? [])
    setCarregando(false)
  }, [])

  useEffect(() => {
    void carregar()
  }, [carregar])

  async function mover(oportunidadeId: string, etapa: Etapa) {
    const status = etapa.tipo === 'ganho' ? 'ganha' : etapa.tipo === 'perdido' ? 'perdida' : 'aberta'

    // atualiza na tela antes da resposta do servidor
    setOportunidades((atual) =>
      status === 'aberta'
        ? atual.map((o) => (o.id === oportunidadeId ? { ...o, etapa_id: etapa.id } : o))
        : atual.filter((o) => o.id !== oportunidadeId),
    )

    const { error } = await supabase
      .from('oportunidades')
      .update({ etapa_id: etapa.id, status, probabilidade: etapa.probabilidade })
      .eq('id', oportunidadeId)

    if (error) void carregar() // deu errado: volta pro estado real
  }

  if (carregando) return <Carregando />
  if (etapas.length === 0) return <Vazio>Rode o `03_seed.sql` para criar o funil padrão.</Vazio>

  const abertas = etapas.filter((e) => e.tipo === 'aberta')

  return (
    <>
      <Titulo>Funil de vendas</Titulo>
      <div className="flex gap-3 overflow-x-auto pb-4">
        {abertas.map((etapa) => {
          const daEtapa = oportunidades.filter((o) => o.etapa_id === etapa.id)
          const total = daEtapa.reduce((a, o) => a + Number(o.valor), 0)
          return (
            <div
              key={etapa.id}
              onDragOver={(e) => e.preventDefault()}
              onDrop={() => {
                if (arrastando) void mover(arrastando, etapa)
                setArrastando(null)
              }}
              className="w-64 shrink-0 rounded-xl bg-slate-100 p-2"
            >
              <div className="flex items-center gap-2 px-2 py-1">
                <span className="h-2 w-2 rounded-full" style={{ background: etapa.cor ?? '#94a3b8' }} />
                <span className="text-sm font-medium">{etapa.nome}</span>
                <span className="ml-auto text-xs text-slate-500">{daEtapa.length}</span>
              </div>
              <p className="px-2 pb-2 text-xs tabular-nums text-slate-500">{moeda(total)}</p>

              <div className="space-y-2">
                {daEtapa.map((o) => (
                  <article
                    key={o.id}
                    draggable
                    onDragStart={() => setArrastando(o.id)}
                    onDragEnd={() => setArrastando(null)}
                    className="cursor-grab rounded-lg border border-slate-200 bg-white p-3 shadow-sm active:cursor-grabbing"
                  >
                    <p className="text-sm font-medium leading-snug">{o.titulo}</p>
                    <Link to={`/clientes/${o.cliente_id}`} className="text-xs text-slate-500 hover:underline">
                      {o.clientes?.nome}
                    </Link>
                    <p className="mt-1 text-sm tabular-nums" style={{ color: 'var(--cor-primaria)' }}>
                      {moeda(Number(o.valor))}
                    </p>
                  </article>
                ))}
              </div>
            </div>
          )
        })}

        <div className="flex w-40 shrink-0 flex-col gap-2">
          {etapas
            .filter((e) => e.tipo !== 'aberta')
            .map((etapa) => (
              <div
                key={etapa.id}
                onDragOver={(e) => e.preventDefault()}
                onDrop={() => {
                  if (arrastando) void mover(arrastando, etapa)
                  setArrastando(null)
                }}
                className="flex h-24 items-center justify-center rounded-xl border-2 border-dashed text-sm font-medium"
                style={{ borderColor: etapa.cor ?? '#cbd5e1', color: etapa.cor ?? '#64748b' }}
              >
                {etapa.nome}
              </div>
            ))}
        </div>
      </div>
      <p className="text-xs text-slate-400">Arraste o card para mudar de etapa, ou solte em Ganho/Perdido para fechar.</p>
    </>
  )
}
