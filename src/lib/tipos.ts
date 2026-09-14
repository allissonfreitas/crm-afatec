export type Papel = 'admin' | 'gestor' | 'vendedor' | 'atendente'

export type Perfil = {
  id: string
  nome: string
  email: string | null
  telefone: string | null
  ramal: string | null
  avatar_url: string | null
  papel: Papel
  ativo: boolean
}

export type Configuracoes = {
  id: number
  nome_empresa: string
  cnpj: string | null
  telefone: string | null
  email: string | null
  site: string | null
  endereco: string | null
  logo_url: string | null
  logo_escura_url: string | null
  favicon_url: string | null
  cor_primaria: string
  cor_secundaria: string
  fuso: string
}

export type StatusCliente = 'lead' | 'prospect' | 'ativo' | 'inativo' | 'perdido'

export type Cliente = {
  id: string
  tipo: 'pf' | 'pj'
  nome: string
  nome_fantasia: string | null
  documento: string | null
  email: string | null
  telefone: string | null
  whatsapp: string | null
  cidade: string | null
  uf: string | null
  status: StatusCliente
  origem_id: number | null
  responsavel_id: string | null
  tags: string[]
  observacoes: string | null
  created_at: string
}

export type Contato = {
  id: string
  cliente_id: string
  nome: string
  cargo: string | null
  email: string | null
  telefone: string | null
  principal: boolean
}

export type Etapa = {
  id: string
  funil_id: string
  nome: string
  ordem: number
  probabilidade: number
  cor: string | null
  tipo: 'aberta' | 'ganho' | 'perdido'
}

export type Oportunidade = {
  id: string
  titulo: string
  cliente_id: string
  funil_id: string
  etapa_id: string
  valor: number
  previsao_fechamento: string | null
  status: 'aberta' | 'ganha' | 'perdida'
  responsavel_id: string | null
  ordem: number
  clientes?: { nome: string } | null
}

export type Atividade = {
  id: string
  tipo: 'ligacao' | 'reuniao' | 'email' | 'whatsapp' | 'visita' | 'tarefa' | 'proposta'
  titulo: string
  descricao: string | null
  cliente_id: string | null
  oportunidade_id: string | null
  responsavel_id: string | null
  inicio: string | null
  fim: string | null
  concluida: boolean
  clientes?: { nome: string } | null
}

export type StatusChamada =
  | 'tocando' | 'em_atendimento' | 'atendida' | 'perdida'
  | 'nao_atendida' | 'ocupado' | 'falha' | 'cancelada'

export type Chamada = {
  id: string
  provedor: string
  direcao: 'entrada' | 'saida'
  status: StatusChamada
  numero_origem: string | null
  numero_destino: string | null
  ramal: string | null
  cliente_id: string | null
  contato_id: string | null
  atendente_id: string | null
  iniciada_em: string
  atendida_em: string | null
  encerrada_em: string | null
  espera_segundos: number | null
  duracao_segundos: number | null
  gravacao_url: string | null
  resumo: string | null
  observacoes: string | null
  clientes?: { id: string; nome: string } | null
  profiles?: { nome: string } | null
}

export type Nota = {
  id: string
  cliente_id: string | null
  texto: string
  autor_id: string | null
  created_at: string
}
