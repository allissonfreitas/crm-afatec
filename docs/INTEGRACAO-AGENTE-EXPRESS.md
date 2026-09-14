# Integração CRM ↔ Agente Express (afatec-agent-core)

Proposta de como o Agente Express, que já atende o WhatsApp da Afatec, passa a alimentar
o CRM. Escrito a partir do contexto técnico do `afatec-agent-core` (Fastify + Node 22 +
PostgreSQL + Redis + Evolution API, sem n8n no caminho da mensagem).

**Nada aqui foi aplicado no agente.** É desenho. As cinco perguntas abertas foram
respondidas por uma leitura do código em 14/09/2026, e as respostas estão incorporadas
abaixo com arquivo e linha.

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

## O que a leitura do código respondeu (14/09/2026)

**1. Bancos separados.** O agente usa PostgreSQL 17, banco `afatec`, serviço próprio no
compose; o Supabase é PostgreSQL 15.8, banco `postgres`. `grep -riE "supabase|crm"` no
projeto não retorna nada. SQL direto está descartado: fica REST, como previsto.

A rede `backend` do compose é `internal: true`. Isso derruba a rota para `172.17.0.1`,
então o endereço do Supabase na integração precisa ser a **URL pública HTTPS**, não o IP
do host. O agente já fala com a Evolution e com os providers de IA por HTTP, então a saída
para a internet existe — falta confirmar em qual rede o serviço `app` está ligado além da
`backend`. Se ele estiver só na rede interna, a saída precisa ser habilitada antes.

**2. Evolution TypeScript (v2).** `normalize.ts:13` aceita `messages.upsert` /
`MESSAGES_UPSERT`, e o payload é o shape Baileys (`data.key.{id,remoteJid,fromMe}`). O
serviço na VPS é `evoapicloud/evolution-api:latest`, que é a TS. Então o evento de chamada
é o `CALL` único, não os três da versão Go. Nenhum tratamento de chamada existe hoje.

**3. O evento de chamada morre em `normalize.ts:13`**, em silêncio (`return null` →
`{status:'ignored'}` → HTTP 200). E **não basta acrescentar `CALL` à lista da linha 13**:
duas linhas depois, `message.safeParse` (`:14-15`) exige `key.{id,remoteJid,fromMe}`, que
um payload de chamada não tem, e devolveria HTTP 400 para a Evolution. O caminho certo é
um desvio próprio **antes** da linha 14, com schema e tipo de retorno separados —
`NormalizedMessage` (`:3`) só modela mensagem de texto.

**4. Ponto de engate: `MessageService.handle`, entre as linhas 48 e 49** de
`src/api/message-service.ts` — depois de `sender.send` (`:47`) e de `memory.mark` (`:48`),
antes do `return` (`:49`).

Cuidado que o código impõe: esse trecho está dentro do `try` que vai da `:24` à `:50`. Se a
chamada ao CRM lançar, cai no `catch` da `:50`; como `sending` já é `true` (`:46`), ele pula
o `mark('failed')` e **relança**, e o webhook devolve 5xx mesmo com o cliente já tendo
recebido a resposta. A chamada ao CRM precisa ser envolvida de modo que não possa lançar.

**5. Telefone: resolvido do lado do CRM.** O agente guarda só o JID cru
(`contacts.remote_jid`, com o sufixo `@s.whatsapp.net`), sem normalização, e a regex de
`normalize.ts:17` aceita de 8 a 15 dígitos sem exigir o prefixo 55.

O risco real era o nono dígito: o WhatsApp entrega `553188887777` e o vendedor cadastra
`5531988887777`, e o mesmo contato viraria dois clientes. Isso foi corrigido no CRM em
`db/04_telefone_chave.sql`: a função `crm.chave_telefone()` colapsa as variações (com e sem
DDI, com e sem o nono dígito, formatado ou não) e a busca passa a usar essa chave.

**Consequência para o agente: nada muda no `contacts`.** Não precisa de coluna nova nem de
normalização própria. Basta mandar ao CRM `remoteJid.split('@')[0]`, que é o que o
`client.ts:9` já faz para montar o envio. `remote_jid` continua sendo a chave de unicidade
e da sessão no Redis, intocado.

## Onde o Comercial engata

`agents/comercial/index.ts` é placeholder de três linhas e não recebe telefone nem
tenantId de forma utilizável. A oportunidade não nasce dentro do agente: nasce no mesmo
ponto da resposta 4, olhando `result.agent === 'comercial'`.

## Funções prontas no CRM para o agente chamar

Já existem, criadas em `db/04_telefone_chave.sql`, e são idempotentes — podem ser chamadas
a cada mensagem:

| função | o que faz |
|---|---|
| `crm.upsert_cliente_whatsapp(telefone, nome, origem)` | acha o cliente pelo telefone (tolerante ao nono dígito) ou cria como lead com origem WhatsApp; devolve o id nos dois casos |
| `crm.cliente_por_telefone(telefone)` | só consulta, devolve o id ou nulo |
| `crm.registrar_chamada(...)` | registra a chamada de voz; com `provedor = 'evolution'` |
