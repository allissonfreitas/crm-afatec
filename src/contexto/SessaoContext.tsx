import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'
import type { Configuracoes, Perfil } from '../lib/tipos'

type Sessao = {
  carregando: boolean
  perfilCarregado: boolean
  sessao: Session | null
  perfil: Perfil | null
  config: Configuracoes | null
  ehGestor: boolean
  ehAdmin: boolean
  recarregarConfig: () => Promise<void>
  sair: () => Promise<void>
}

const Ctx = createContext<Sessao | null>(null)

export function SessaoProvider({ children }: { children: ReactNode }) {
  const [carregando, setCarregando] = useState(true)
  const [sessao, setSessao] = useState<Session | null>(null)
  const [perfil, setPerfil] = useState<Perfil | null>(null)
  const [perfilCarregado, setPerfilCarregado] = useState(false)
  const [config, setConfig] = useState<Configuracoes | null>(null)

  async function carregarConfig() {
    const { data } = await supabase.from('configuracoes').select('*').eq('id', 1).maybeSingle()
    if (data) setConfig(data as Configuracoes)
  }

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSessao(data.session)
      setCarregando(false)
    })
    const { data: sub } = supabase.auth.onAuthStateChange((_evento, s) => setSessao(s))
    return () => sub.subscription.unsubscribe()
  }, [])

  useEffect(() => {
    if (!sessao?.user) {
      setPerfil(null)
      setConfig(null)
      setPerfilCarregado(false)
      return
    }
    setPerfilCarregado(false)
    supabase
      .from('profiles')
      .select('*')
      .eq('id', sessao.user.id)
      .maybeSingle()
      .then(({ data }) => {
        // sem linha ativa em crm.profiles o RLS não devolve nada:
        // é um usuário de outro app do mesmo Supabase
        setPerfil((data as Perfil) ?? null)
        setPerfilCarregado(true)
      })
    void carregarConfig()
  }, [sessao?.user?.id])

  // aplica as cores da marca em variáveis CSS
  useEffect(() => {
    if (!config) return
    const raiz = document.documentElement
    raiz.style.setProperty('--cor-primaria', config.cor_primaria)
    raiz.style.setProperty('--cor-secundaria', config.cor_secundaria)
    if (config.favicon_url) {
      const link = document.querySelector<HTMLLinkElement>("link[rel='icon']")
      if (link) link.href = config.favicon_url
    }
    document.title = `CRM ${config.nome_empresa}`
  }, [config])

  const valor = useMemo<Sessao>(
    () => ({
      carregando,
      perfilCarregado,
      sessao,
      perfil,
      config,
      ehGestor: perfil?.papel === 'admin' || perfil?.papel === 'gestor',
      ehAdmin: perfil?.papel === 'admin',
      recarregarConfig: carregarConfig,
      sair: async () => {
        await supabase.auth.signOut()
      },
    }),
    [carregando, perfilCarregado, sessao, perfil, config],
  )

  return <Ctx.Provider value={valor}>{children}</Ctx.Provider>
}

export function useSessao() {
  const ctx = useContext(Ctx)
  if (!ctx) throw new Error('useSessao precisa estar dentro de <SessaoProvider>')
  return ctx
}
