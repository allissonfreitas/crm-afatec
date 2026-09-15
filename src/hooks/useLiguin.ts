import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { Chamada } from '../lib/tipos'

/**
 * Escuta em tempo real as ligações de entrada que ainda estão em curso.
 * Com `meuRamal`, só entrega as chamadas daquele ramal ou as que ainda
 * não foram distribuídas para ninguém.
 */
export function useLiguin(meuRamal?: string | null) {
  const [chamadas, setChamadas] = useState<Chamada[]>([])

  useEffect(() => {
    let vivo = true

    const relevante = (c: Chamada) =>
      c.direcao === 'entrada' &&
      (c.status === 'tocando' || c.status === 'em_atendimento') &&
      (!meuRamal || !c.ramal || c.ramal === meuRamal)

    // o que já estava tocando quando a tela abriu
    void supabase
      .from('chamadas')
      .select('*')
      .eq('direcao', 'entrada')
      .in('status', ['tocando', 'em_atendimento'])
      .order('iniciada_em', { ascending: false })
      .then(({ data }) => {
        if (vivo && data) setChamadas((data as Chamada[]).filter(relevante))
      })

    const canal = supabase
      .channel('liguin-entrada')
      .on(
        'postgres_changes',
        { event: '*', schema: 'crm', table: 'chamadas' },
        (payload) => {
          const nova = payload.new as Chamada | undefined
          const velha = payload.old as Partial<Chamada> | undefined
          const id = nova?.id ?? velha?.id
          if (!id) return
          setChamadas((atual) => {
            const semEla = atual.filter((c) => c.id !== id)
            return nova && relevante(nova) ? [nova, ...semEla] : semEla
          })
        },
      )
      // Sem este retorno de status, uma assinatura que falha e' silenciosa:
      // a tela fica parada e nao ha como saber se o problema foi o banco, o
      // Realtime ou o navegador. Com ele, o Console responde a pergunta.
      .subscribe((status, erro) => {
        // eslint-disable-next-line no-console
        console.log('[liguin] assinatura:', status, erro ?? '')
        if (typeof window !== 'undefined') {
          ;(window as unknown as Record<string, unknown>).__liguin = {
            status,
            erro: erro ? String(erro) : null,
            ramal: meuRamal ?? null,
            em: new Date().toISOString(),
          }
        }
      })

    return () => {
      vivo = false
      void supabase.removeChannel(canal)
    }
  }, [meuRamal])

  return chamadas
}
