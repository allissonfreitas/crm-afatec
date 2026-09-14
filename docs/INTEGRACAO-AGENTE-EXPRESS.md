# Integração CRM ↔ Agente Express (afatec-agent-core)

Proposta de como o Agente Express, que já atende o WhatsApp da Afatec, passa a alimentar
o CRM. Escrito a partir do contexto técnico do `afatec-agent-core` (Fastify + Node 22 +
PostgreSQL + Redis + Evolution API, sem n8n no caminho da mensagem).

**Nada aqui foi aplicado.** É desenho, para ser conferido contra o código antes de virar
implementação.

## O que muda no conceito de "liguin"

O CRM foi desenhado para telefonia: uma central manda `ringing` / `answered` / `hangup` e
o pop-up deixa o atendente atender. No WhatsApp isso não existe do mesmo jeito:

| | Central telefônica (Asterisk, SIP) | WhatsApp via Evolution |
|---|---|---|
| Avisa que está chamando | sim | sim, evento `CALL` |
| Atender pela aplicação | sim | **não** — não há endpoint para isso |
| Gravação | sim | não |
| Conversa de texto | não | sim, é o forte |

Ou seja: pelo WhatsApp dá para **registrar** que uma chamada de voz entrou, não para
atendê-la. O valor real da integração não está na chamada de voz — está em cada conversa
do Express virar cliente, atividade e oportunidade no CRM automaticamente.

O pop-up então passa a ter dois usos: ligação de voz de uma central (quando existir) e
"atendimento chegando" de uma conversa do WhatsApp que o Express encaminhou ao Comercial.

## Três pontos de integração

### 1. Toda conversa vira cliente e atividade

Depois que o `message-service` persiste a mensagem, o CRM recebe:

- `crm.clientes` — upsert pelo telefone. O CRM já normaliza telefone em coluna gerada
  (`telefone_norm`, `whatsapp_norm`), então o mesmo número que liga e que manda mensagem
  cai no mesmo cliente. Cliente novo nasce com `status = 'lead'` e origem `WhatsApp`.
- `crm.atividades` — uma atividade `tipo = 'whatsapp'` por conversa (não por mensagem),
  com o resumo do que foi tratado.

### 2. O Comercial cria a oportunidade

`agents/comercial/index.ts` hoje é placeholder. Quando o roteador manda a mensagem para o
Comercial, além da resposta ao cliente, o CRM ganha uma `crm.oportunidades` na primeira
etapa do funil, ligada ao cliente, com origem `WhatsApp`. É o que faz o funil encher
sozinho em vez de alguém cadastrar à mão.

### 3. Chamada de voz do WhatsApp entra como chamada perdida

O evento `CALL` da Evolution carrega `id`, `from`, `timestamp` e `isVideo`. Dá para
registrar em `crm.chamadas` com `provedor = 'evolution'`, `direcao = 'entrada'` e
`status = 'nao_atendida'`, já que não há como atender pela API. Vira tarefa de retorno.

## Contrato

O agente fala com o CRM pela API REST do Supabase (PostgREST), sem acoplar os bancos:

```
POST {SUPABASE_URL}/rest/v1/rpc/registrar_chamada
  apikey: {SERVICE_ROLE}
  Authorization: Bearer {SERVICE_ROLE}
  Content-Profile: crm          <- obrigatório, o CRM não está no schema public
  Content-Type: application/json
```

Para tabelas, o mesmo `Content-Profile: crm` em POST/PATCH e `Accept-Profile: crm` em GET.
O schema `crm` precisa estar em `PGRST_DB_SCHEMAS`.

Variáveis novas no `.env` do agente: `CRM_SUPABASE_URL`, `CRM_SERVICE_ROLE`,
`CRM_ENABLED` (para poder desligar), `CRM_DRY_RUN` (mesmo padrão do `EVOLUTION_DRY_RUN`).

## Uma restrição que o próprio agente já documenta

A seção 9 do contexto diz que o webhook processa de forma síncrona, sem fila durável. Toda
chamada ao CRM precisa então ser **fora do caminho da resposta**: disparada depois do envio
ao cliente, com timeout curto, e com falha registrada em log sem derrubar o atendimento.
Um CRM fora do ar não pode fazer o WhatsApp parar de responder.

## O que precisa ser confirmado no código antes de implementar

1. O PostgreSQL do agente é o mesmo do Supabase ou é outro? Se for o mesmo, parte da
   integração pode ser SQL direto em vez de REST.
2. Qual implementação da Evolution está em uso — a TypeScript (evento único `CALL`) ou a
   Go (`CallOffer` / `CallAccept` / `CallTerminate`)? Os nomes de evento são incompatíveis.
3. O webhook `/webhooks/evolution` hoje descarta eventos que não são mensagem de texto.
   Onde exatamente o evento de chamada seria aceito sem quebrar a normalização atual?
4. Onde termina o envio da resposta no `message-service`, para pendurar a chamada ao CRM
   depois dele.
5. O agente já tem o telefone normalizado em algum formato próprio? Vale reaproveitar em
   vez de normalizar duas vezes.
