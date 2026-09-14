import { useCallback, useEffect, useState } from 'react'
import { useParams } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { Cartao, Carregando, Etiqueta, Titulo, Vazio } from '../componentes/ui'
import { dataHora, duracao, moeda, telefone } from '../lib/formato'
import type { Atividade, Chamada, Cliente, Contato, Nota, Oportunidade } from '../lib/tipos'

type ItemLinha =
  | { tipo: 'atividade'; quando: string; dado: Atividade }
  | { tipo: 'nota'; quando: string; dado: Nota }
  | { tipo: 'chamada'; quando: string; dado: Chamada }

export function ClienteDetalhe() {
  const { id } = useParams<{ id: string }>()
  const [carregando, setCarregando] = useState(true)
  const [cliente, setCliente] = useState<Cliente | null>(null)
  const [contatos, setContatos] = useState<Contato[]>([])
  const [oportunidades, setOportunidades] = useState<Oportunidade[]>([])
  const [linha, setLinha] = useState<ItemLinha[]>([])
  const [novaNota, setNovaNota] = useState('')

  const carregar = useCallback(async () => {
    if (!id) return
    const [cl, ct, op, at, nt, ch] = await Promise.all([
      supabase.from('clientes').select('*').eq('id', id).maybeSingle(),
      supabase.from('contatos').select('*').eq('cliente_id', id).order('principal', { ascending: false }),
      supabase.from('oportunidades').select('*').eq('cliente_id', id).order('created_at', { ascending: false }),
      supabase.from('atividades').select('*').eq('cliente_id', id).order('created_at', { ascending: false }).limit(50),
      supabase.from('notas').select('*').eq('cliente_id', id).order('created_at', { ascending: false }).limit(50),
      supabase.from('chamadas').select('*').eq('cliente_id', id).order('iniciada_em', { ascending: false }).limit(50),
    ])

    setCliente((cl.data as Cliente) ?? null)
    setContatos((ct.data as Contato[]) ?? [])
    setOportunidades((op.data as Oportunidade[]) ?? [])

    const itens: ItemLinha[] = [
      ...((at.data as Atividade[]) ?? []).map((a) => ({
        tipo: 'atividade' as const, quando: a.fim ?? a.inicio ?? '', dado: a,
      })),
      ...((nt.data as Nota[]) ?? []).map((n) => ({ tipo: 'nota' as const, quando: n.created_at, dado: n })),
      ...((ch.data as Chamada[]) ?? []).map((c) => ({ tipo: 'chamada' as const, quando: c.iniciada_em, dado: c })),
    ].sort((a, b) => (a.quando < b.quando ? 1 : -1))

    setLinha(itens)
    setCarregando(false)
  }, [id])

  useEffect(() => {
    void carregar()
  }, [carregar])

  async function salvarNota(e: React.FormEvent) {
    e.preventDefault()
    if (!novaNota.trim() || !id) return
    const { data: u } = await supabase.auth.getUser()
    await supabase.from('notas').insert({ cliente_id: id, texto: novaNota.trim(), autor_id: u.user?.id })
    setNovaNota('')
    void carregar()
  }

  if (carregando) return <Carregando />
  if (!cliente) return <Vazio>Cliente não encontrado.</Vazio>

  return (
    <>
      <Titulo acao={<Etiqueta valor={cliente.status} />}>{cliente.nome}</Titulo>

      <div className="grid gap-4 lg:grid-cols-3">
        <div className="space-y-4">
          <Cartao>
            <h2 className="mb-3 font-medium">Dados</h2>
            <dl className="space-y-2 text-sm">
              <div><dt className="text-slate-400">Telefone</dt><dd>{telefone(cliente.telefone)}</dd></div>
              <div><dt className="text-slate-400">WhatsApp</dt><dd>{telefone(cliente.whatsapp)}</dd></div>
              <div><dt className="text-slate-400">E-mail</dt><dd>{cliente.email ?? '—'}</dd></div>
              <div><dt className="text-slate-400">Documento</dt><dd>{cliente.documento ?? '—'}</dd></div>
              <div>
                <dt className="text-slate-400">Cidade</dt>
                <dd>{cliente.cidade ? `${cliente.cidade}${cliente.uf ? '/' + cliente.uf : ''}` : '—'}</dd>
              </div>
            </dl>
          </Cartao>

          <Cartao>
            <h2 className="mb-3 font-medium">Contatos</h2>
            {contatos.length === 0 ? (
              <Vazio>Nenhum contato cadastrado.</Vazio>
            ) : (
              <ul className="space-y-3 text-sm">
                {contatos.map((c) => (
                  <li key={c.id}>
                    <p className="font-medium">
                      {c.nome} {c.principal && <span className="text-xs text-emerald-600">principal</span>}
                    </p>
                    <p className="text-xs text-slate-500">{c.cargo ?? '—'} · {telefone(c.telefone)}</p>
                  </li>
                ))}
              </ul>
            )}
          </Cartao>

          <Cartao>
            <h2 className="mb-3 font-medium">Oportunidades</h2>
            {oportunidades.length === 0 ? (
              <Vazio>Nenhuma oportunidade.</Vazio>
            ) : (
              <ul className="space-y-2 text-sm">
                {oportunidades.map((o) => (
                  <li key={o.id} className="flex items-center justify-between gap-2">
                    <span className="min-w-0 truncate">{o.titulo}</span>
                    <span className="shrink-0 tabular-nums text-slate-600">{moeda(Number(o.valor))}</span>
                  </li>
                ))}
              </ul>
            )}
          </Cartao>
        </div>

        <div className="lg:col-span-2">
          <Cartao>
            <h2 className="mb-3 font-medium">Histórico</h2>

            <form onSubmit={(e) => void salvarNota(e)} className="mb-4 flex gap-2">
              <input
                value={novaNota}
                onChange={(e) => setNovaNota(e.target.value)}
                placeholder="Escrever uma nota…"
                className="min-w-0 flex-1 rounded-lg border border-slate-300 px-3 py-2 text-sm outline-none focus:border-slate-500"
              />
              <button
                type="submit"
                className="rounded-lg px-4 py-2 text-sm font-medium text-white"
                style={{ background: 'var(--cor-primaria)' }}
              >
                Salvar
              </button>
            </form>

            {linha.length === 0 ? (
              <Vazio>Sem histórico ainda.</Vazio>
            ) : (
              <ol className="space-y-4 border-l border-slate-200 pl-4">
                {linha.map((item) => (
                  <li key={`${item.tipo}-${item.dado.id}`} className="relative">
                    <span className="absolute -left-[21px] top-1.5 h-2 w-2 rounded-full bg-slate-300" />
                    <p className="text-xs text-slate-400">{dataHora(item.quando)}</p>

                    {item.tipo === 'chamada' && (
                      <div className="text-sm">
                        <p className="font-medium">
                          {item.dado.direcao === 'entrada' ? 'Ligação recebida' : 'Ligação realizada'} ·{' '}
                          <Etiqueta valor={item.dado.status} />
                        </p>
                        <p className="text-slate-500">
                          {telefone(item.dado.numero_origem)} · {duracao(item.dado.duracao_segundos)}
                        </p>
                        {item.dado.resumo && <p className="mt-1 text-slate-600">{item.dado.resumo}</p>}
                        {item.dado.gravacao_url && (
                          <audio controls src={item.dado.gravacao_url} className="mt-2 h-8 w-full max-w-sm" />
                        )}
                      </div>
                    )}

                    {item.tipo === 'atividade' && (
                      <div className="text-sm">
                        <p className="font-medium">{item.dado.titulo}</p>
                        {item.dado.descricao && <p className="text-slate-600">{item.dado.descricao}</p>}
                      </div>
                    )}

                    {item.tipo === 'nota' && <p className="text-sm text-slate-700">{item.dado.texto}</p>}
                  </li>
                ))}
              </ol>
            )}
          </Cartao>
        </div>
      </div>
    </>
  )
}
