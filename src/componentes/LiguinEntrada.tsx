import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useLiguin } from '../hooks/useLiguin'
import { useSessao } from '../contexto/SessaoContext'
import { telefone } from '../lib/formato'
import type { Chamada, Cliente } from '../lib/tipos'

/**
 * Pop-up de ligação de entrada. Fica montado no layout, então aparece
 * em qualquer tela do CRM assim que a central avisa que o telefone tocou.
 */
export function LiguinEntrada() {
  const { perfil } = useSessao()
  const chamadas = useLiguin(perfil?.ramal)
  const chamada = chamadas[0]
  const [cliente, setCliente] = useState<Cliente | null>(null)
  const [ocupado, setOcupado] = useState(false)
  const audioRef = useRef<HTMLAudioElement | null>(null)
  const navigate = useNavigate()

  useEffect(() => {
    if (!chamada || chamada.status !== 'tocando') return
    const audio = new Audio('/ring.mp3')
    audio.loop = true
    // o navegador bloqueia som antes de qualquer clique do usuário: silencioso de propósito
    void audio.play().catch(() => undefined)
    audioRef.current = audio
    return () => {
      audio.pause()
      audioRef.current = null
    }
  }, [chamada?.id, chamada?.status])

  useEffect(() => {
    if (!chamada?.cliente_id) {
      setCliente(null)
      return
    }
    void supabase
      .from('clientes')
      .select('*')
      .eq('id', chamada.cliente_id)
      .maybeSingle()
      .then(({ data }) => setCliente((data as Cliente) ?? null))
  }, [chamada?.cliente_id])

  if (!chamada) return null

  async function atender(c: Chamada) {
    setOcupado(true)
    const { data: u } = await supabase.auth.getUser()
    await supabase
      .from('chamadas')
      .update({
        status: 'em_atendimento',
        atendente_id: u.user?.id,
        atendida_em: new Date().toISOString(),
      })
      .eq('id', c.id)
    audioRef.current?.pause()
    setOcupado(false)
  }

  async function criarLead(c: Chamada) {
    setOcupado(true)
    const { data: u } = await supabase.auth.getUser()
    const { data: origem } = await supabase
      .from('origens')
      .select('id')
      .eq('nome', 'Ligação recebida')
      .maybeSingle()

    const { data: novo } = await supabase
      .from('clientes')
      .insert({
        tipo: 'pf',
        nome: `Lead ${telefone(c.numero_origem)}`,
        telefone: c.numero_origem,
        status: 'lead',
        origem_id: origem?.id ?? null,
        responsavel_id: u.user?.id,
        created_by: u.user?.id,
      })
      .select('id')
      .single()

    if (novo) {
      await supabase.from('chamadas').update({ cliente_id: novo.id }).eq('id', c.id)
      navigate(`/clientes/${novo.id}`)
    }
    setOcupado(false)
  }

  const tocando = chamada.status === 'tocando'

  return (
    <div className="fixed bottom-4 right-4 z-50 w-80 overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-2xl">
      <div className="flex items-center gap-2 px-4 py-2 text-white" style={{ background: 'var(--cor-primaria)' }}>
        <span className="relative flex h-2 w-2">
          {tocando && (
            <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-white opacity-75" />
          )}
          <span className="relative inline-flex h-2 w-2 rounded-full bg-white" />
        </span>
        <strong className="text-sm">{tocando ? 'Ligação chegando' : 'Em atendimento'}</strong>
        {chamada.ramal && <span className="ml-auto text-xs opacity-80">ramal {chamada.ramal}</span>}
      </div>

      <div className="space-y-1 px-4 py-3">
        <p className="text-lg font-semibold leading-tight">
          {cliente ? cliente.nome : 'Número não cadastrado'}
        </p>
        <p className="text-sm text-slate-500">{telefone(chamada.numero_origem)}</p>
        {cliente && (
          <span className="inline-block rounded-full bg-slate-100 px-2 py-0.5 text-xs uppercase tracking-wide text-slate-500">
            {cliente.status}
          </span>
        )}
      </div>

      <div className="flex gap-2 px-4 pb-4">
        {tocando && (
          <button
            onClick={() => void atender(chamada)}
            disabled={ocupado}
            className="flex-1 rounded-lg bg-emerald-600 px-3 py-2 text-sm font-medium text-white hover:bg-emerald-700 disabled:opacity-60"
          >
            Atender
          </button>
        )}
        {cliente ? (
          <button
            onClick={() => navigate(`/clientes/${cliente.id}`)}
            className="flex-1 rounded-lg border border-slate-300 px-3 py-2 text-sm hover:bg-slate-50"
          >
            Abrir ficha
          </button>
        ) : (
          <button
            onClick={() => void criarLead(chamada)}
            disabled={ocupado}
            className="flex-1 rounded-lg border border-slate-300 px-3 py-2 text-sm hover:bg-slate-50 disabled:opacity-60"
          >
            Criar lead
          </button>
        )}
      </div>
    </div>
  )
}
