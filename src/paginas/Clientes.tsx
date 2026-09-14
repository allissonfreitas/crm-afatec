import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { Cartao, Carregando, Etiqueta, Titulo, Vazio } from '../componentes/ui'
import { telefone } from '../lib/formato'
import type { Cliente, StatusCliente } from '../lib/tipos'

const STATUS: StatusCliente[] = ['lead', 'prospect', 'ativo', 'inativo', 'perdido']

export function Clientes() {
  const [carregando, setCarregando] = useState(true)
  const [clientes, setClientes] = useState<Cliente[]>([])
  const [busca, setBusca] = useState('')
  const [status, setStatus] = useState<StatusCliente | ''>('')

  useEffect(() => {
    void supabase
      .from('clientes')
      .select('*')
      .order('created_at', { ascending: false })
      .limit(300)
      .then(({ data }) => {
        setClientes((data as Cliente[]) ?? [])
        setCarregando(false)
      })
  }, [])

  const filtrados = useMemo(() => {
    const t = busca.trim().toLowerCase()
    return clientes.filter((c) => {
      if (status && c.status !== status) return false
      if (!t) return true
      return [c.nome, c.nome_fantasia, c.email, c.telefone, c.documento]
        .filter(Boolean)
        .some((v) => String(v).toLowerCase().includes(t))
    })
  }, [clientes, busca, status])

  if (carregando) return <Carregando />

  return (
    <>
      <Titulo>Clientes</Titulo>

      <div className="mb-4 flex flex-wrap gap-2">
        <input
          value={busca}
          onChange={(e) => setBusca(e.target.value)}
          placeholder="Buscar por nome, e-mail, telefone ou documento"
          className="min-w-0 flex-1 rounded-lg border border-slate-300 px-3 py-2 text-sm outline-none focus:border-slate-500"
        />
        <select
          value={status}
          onChange={(e) => setStatus(e.target.value as StatusCliente | '')}
          className="rounded-lg border border-slate-300 px-3 py-2 text-sm"
        >
          <option value="">Todos os status</option>
          {STATUS.map((s) => (
            <option key={s} value={s}>{s}</option>
          ))}
        </select>
      </div>

      <Cartao className="overflow-x-auto p-0">
        {filtrados.length === 0 ? (
          <Vazio>Nenhum cliente encontrado.</Vazio>
        ) : (
          <table className="w-full text-sm">
            <thead className="border-b border-slate-200 text-left text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th className="px-4 py-3">Nome</th>
                <th className="px-4 py-3">Telefone</th>
                <th className="px-4 py-3">Cidade</th>
                <th className="px-4 py-3">Status</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {filtrados.map((c) => (
                <tr key={c.id} className="hover:bg-slate-50">
                  <td className="px-4 py-3">
                    <Link to={`/clientes/${c.id}`} className="font-medium hover:underline">{c.nome}</Link>
                    {c.nome_fantasia && <p className="text-xs text-slate-400">{c.nome_fantasia}</p>}
                  </td>
                  <td className="px-4 py-3 text-slate-600">{telefone(c.telefone)}</td>
                  <td className="px-4 py-3 text-slate-600">
                    {c.cidade ? `${c.cidade}${c.uf ? '/' + c.uf : ''}` : '—'}
                  </td>
                  <td className="px-4 py-3"><Etiqueta valor={c.status} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </Cartao>
      <p className="mt-2 text-xs text-slate-400">{filtrados.length} de {clientes.length} clientes</p>
    </>
  )
}
