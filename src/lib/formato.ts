export function telefone(n?: string | null) {
  if (!n) return '—'
  const d = n.replace(/\D/g, '').replace(/^55/, '')
  if (d.length === 11) return `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`
  if (d.length === 10) return `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`
  return n
}

export function moeda(v?: number | null) {
  return (v ?? 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })
}

export function dataHora(iso?: string | null) {
  if (!iso) return '—'
  return new Date(iso).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' })
}

export function data(iso?: string | null) {
  if (!iso) return '—'
  return new Date(iso).toLocaleDateString('pt-BR')
}

export function duracao(segundos?: number | null) {
  if (segundos === null || segundos === undefined) return '—'
  const m = Math.floor(segundos / 60)
  const s = segundos % 60
  return `${m}min ${String(s).padStart(2, '0')}s`
}

export function iniciais(nome?: string | null) {
  if (!nome) return '?'
  return nome
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((p) => p[0]?.toUpperCase() ?? '')
    .join('')
}
