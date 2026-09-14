import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSessao } from '../contexto/SessaoContext'
import { Cartao, Carregando, Titulo, Vazio } from '../componentes/ui'
import type { Configuracoes as Config, Perfil } from '../lib/tipos'

export function Configuracoes() {
  const { config, ehAdmin, recarregarConfig } = useSessao()
  const [form, setForm] = useState<Config | null>(null)
  const [equipe, setEquipe] = useState<Perfil[]>([])
  const [salvando, setSalvando] = useState(false)
  const [aviso, setAviso] = useState<string | null>(null)

  useEffect(() => {
    if (config) setForm(config)
  }, [config])

  useEffect(() => {
    void supabase
      .from('profiles')
      .select('*')
      .order('nome')
      .then(({ data }) => setEquipe((data as Perfil[]) ?? []))
  }, [])

  if (!form) return <Carregando />
  if (!ehAdmin) return <Vazio>Só o administrador pode alterar as configurações.</Vazio>

  function campo<K extends keyof Config>(chave: K, valor: Config[K]) {
    setForm((f) => (f ? { ...f, [chave]: valor } : f))
  }

  async function enviarLogo(arquivo: File, coluna: 'logo_url' | 'logo_escura_url' | 'favicon_url') {
    setAviso(null)
    const caminho = `${coluna}-${Date.now()}-${arquivo.name.replace(/[^\w.-]/g, '_')}`
    const { error } = await supabase.storage.from('crm-marca').upload(caminho, arquivo, { upsert: true })
    if (error) {
      setAviso(`Falha no upload: ${error.message}`)
      return
    }
    const { data } = supabase.storage.from('crm-marca').getPublicUrl(caminho)
    campo(coluna, data.publicUrl)
    setAviso('Imagem enviada. Clique em Salvar para aplicar.')
  }

  async function salvar(e: React.FormEvent) {
    e.preventDefault()
    if (!form) return
    setSalvando(true)
    setAviso(null)
    const { id: _id, ...campos } = form
    const { error } = await supabase.from('configuracoes').update(campos).eq('id', 1)
    setAviso(error ? `Erro ao salvar: ${error.message}` : 'Configurações salvas.')
    if (!error) await recarregarConfig()
    setSalvando(false)
  }

  return (
    <>
      <Titulo>Configurações</Titulo>

      <form onSubmit={(e) => void salvar(e)} className="grid gap-4 lg:grid-cols-2">
        <Cartao>
          <h2 className="mb-3 font-medium">Empresa</h2>
          <div className="space-y-3 text-sm">
            <label className="block">
              <span className="text-slate-500">Nome</span>
              <input
                value={form.nome_empresa}
                onChange={(e) => campo('nome_empresa', e.target.value)}
                className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2"
              />
            </label>
            <label className="block">
              <span className="text-slate-500">CNPJ</span>
              <input
                value={form.cnpj ?? ''}
                onChange={(e) => campo('cnpj', e.target.value)}
                className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2"
              />
            </label>
            <label className="block">
              <span className="text-slate-500">Telefone</span>
              <input
                value={form.telefone ?? ''}
                onChange={(e) => campo('telefone', e.target.value)}
                className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2"
              />
            </label>
          </div>
        </Cartao>

        <Cartao>
          <h2 className="mb-3 font-medium">Identidade visual</h2>
          <div className="space-y-3 text-sm">
            <div className="flex items-center gap-3">
              {form.logo_url && (
                <img src={form.logo_url} alt="Logo" className="h-14 w-14 rounded-lg object-contain" />
              )}
              <label className="cursor-pointer text-slate-500">
                <span className="underline">Trocar logo</span>
                <input
                  type="file" accept="image/*" className="hidden"
                  onChange={(e) => {
                    const f = e.target.files?.[0]
                    if (f) void enviarLogo(f, 'logo_url')
                  }}
                />
              </label>
            </div>

            <div className="flex gap-3">
              <label className="flex-1">
                <span className="text-slate-500">Cor primária</span>
                <input
                  type="color" value={form.cor_primaria}
                  onChange={(e) => campo('cor_primaria', e.target.value)}
                  className="mt-1 h-10 w-full rounded-lg border border-slate-300"
                />
              </label>
              <label className="flex-1">
                <span className="text-slate-500">Cor secundária</span>
                <input
                  type="color" value={form.cor_secundaria}
                  onChange={(e) => campo('cor_secundaria', e.target.value)}
                  className="mt-1 h-10 w-full rounded-lg border border-slate-300"
                />
              </label>
            </div>
          </div>
        </Cartao>

        <div className="lg:col-span-2">
          {aviso && <p className="mb-3 rounded-lg bg-slate-100 px-3 py-2 text-sm text-slate-700">{aviso}</p>}
          <button
            type="submit" disabled={salvando}
            className="rounded-lg px-4 py-2 text-sm font-medium text-white disabled:opacity-60"
            style={{ background: 'var(--cor-primaria)' }}
          >
            {salvando ? 'Salvando…' : 'Salvar'}
          </button>
        </div>
      </form>

      <Cartao className="mt-4">
        <h2 className="mb-3 font-medium">Equipe e ramais</h2>
        <p className="mb-3 text-xs text-slate-400">
          O ramal é o que amarra a ligação de entrada ao atendente. Crie os usuários no Supabase
          (Authentication → Users) e preencha o ramal aqui.
        </p>
        <table className="w-full text-sm">
          <thead className="text-left text-xs uppercase tracking-wide text-slate-500">
            <tr>
              <th className="py-2">Nome</th><th className="py-2">E-mail</th>
              <th className="py-2">Papel</th><th className="py-2">Ramal</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100">
            {equipe.map((p) => (
              <tr key={p.id}>
                <td className="py-2">{p.nome}</td>
                <td className="py-2 text-slate-600">{p.email}</td>
                <td className="py-2 text-slate-600">{p.papel}</td>
                <td className="py-2">
                  <input
                    defaultValue={p.ramal ?? ''}
                    placeholder="—"
                    onBlur={(e) => {
                      const ramal = e.target.value.trim() || null
                      if (ramal !== p.ramal) void supabase.from('profiles').update({ ramal }).eq('id', p.id)
                    }}
                    className="w-24 rounded border border-slate-300 px-2 py-1"
                  />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </Cartao>
    </>
  )
}
