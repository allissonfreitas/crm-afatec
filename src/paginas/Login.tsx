import { useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSessao } from '../contexto/SessaoContext'

export function Login() {
  const { config } = useSessao()
  const [email, setEmail] = useState('')
  const [senha, setSenha] = useState('')
  const [erro, setErro] = useState<string | null>(null)
  const [enviando, setEnviando] = useState(false)

  async function entrar(e: React.FormEvent) {
    e.preventDefault()
    setErro(null)
    setEnviando(true)
    const { error } = await supabase.auth.signInWithPassword({ email, password: senha })
    if (error) setErro('E-mail ou senha incorretos.')
    setEnviando(false)
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-slate-100 px-4">
      <form onSubmit={(e) => void entrar(e)} className="w-full max-w-sm space-y-4 rounded-2xl bg-white p-8 shadow-lg">
        <div className="mb-2 flex flex-col items-center gap-2">
          <img
            src={config?.logo_url ?? '/logo-afatec.png'}
            alt={config?.nome_empresa ?? 'Afatec'}
            className="h-24 w-24 object-contain"
          />
          <span className="text-sm text-slate-500">CRM {config?.nome_empresa ?? 'Afatec'}</span>
        </div>

        <div>
          <label className="mb-1 block text-sm text-slate-600" htmlFor="email">E-mail</label>
          <input
            id="email" type="email" required autoComplete="email"
            value={email} onChange={(e) => setEmail(e.target.value)}
            className="w-full rounded-lg border border-slate-300 px-3 py-2 outline-none focus:border-slate-500"
          />
        </div>

        <div>
          <label className="mb-1 block text-sm text-slate-600" htmlFor="senha">Senha</label>
          <input
            id="senha" type="password" required autoComplete="current-password"
            value={senha} onChange={(e) => setSenha(e.target.value)}
            className="w-full rounded-lg border border-slate-300 px-3 py-2 outline-none focus:border-slate-500"
          />
        </div>

        {erro && <p className="rounded-lg bg-rose-50 px-3 py-2 text-sm text-rose-700">{erro}</p>}

        <button
          type="submit" disabled={enviando}
          className="w-full rounded-lg px-3 py-2 font-medium text-white disabled:opacity-60"
          style={{ background: 'var(--cor-primaria)' }}
        >
          {enviando ? 'Entrando…' : 'Entrar'}
        </button>
      </form>
    </div>
  )
}
