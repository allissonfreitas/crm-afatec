# Prompts para ligar o Agente Express ao CRM

Dois passos, nesta ordem. O desenho está em `INTEGRACAO-AGENTE-EXPRESS.md`; aqui é só o
que se cola no Claude Code da VPS.

**Etapa A** mexe só no CRM e não toca no agente — é segura de rodar mesmo antes de decidir
se a integração vai existir. **Etapa B** mexe no `afatec-agent-core`, que é o WhatsApp da
empresa em produção.

---

## Etapa A — preparar o CRM para receber

```
No clone do CRM em /opt/crm-afatec, dê git pull e aplique duas migrações novas no
Supabase, nesta ordem, com ON_ERROR_STOP=1. Leia cada arquivo antes de rodar.

  db/06_integracao.sql       — funções que o Agente Express vai chamar
  db/07_papel_integracao.sql — papel próprio para o agente, no lugar da service_role

Nenhuma das duas cria, altera ou revoga nada no schema public. A 06 adiciona uma coluna
(crm.atividades.ref_externa) e três funções; a 07 cria o papel crm_integracao. As duas
são idempotentes.

Depois de aplicar, confirme:

  select proname,
         has_function_privilege('anon', oid, 'execute')           as anon,
         has_function_privilege('crm_integracao', oid, 'execute') as integracao
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'crm' and proname like '%whatsapp%' order by 1;

  Esperado: anon = f em todas; integracao = t nas três de integração.

  set role crm_integracao;
  select 1 from crm.clientes limit 1;   -- tem que dar permission denied
  reset role;

Em seguida gere o token que o agente vai usar. Ele é um JWT assinado com o mesmo
JWT_SECRET que já está no .env do stack do Supabase, com o payload:

  { "role": "crm_integracao", "iss": "supabase", "iat": <agora>, "exp": <agora + 10 anos> }

Gere na VPS, não me mande o token nem o JWT_SECRET. Guarde o token em
/root/crm-integracao.token com chmod 600 e me diga só o tamanho em caracteres.

Teste o token pelo PostgREST antes de seguir (o header Content-Profile é obrigatório,
o CRM não está no schema public):

  curl -s -X POST "https://zapmaxapi.afatec.net/rest/v1/rpc/registrar_atendimento_whatsapp" \
    -H "apikey: $TOKEN" -H "Authorization: Bearer $TOKEN" \
    -H "Content-Profile: crm" -H "Content-Type: application/json" \
    -d '{"p_telefone":"5531900000000","p_nome":"Teste integracao","p_resumo":"ping","p_agente":"teste"}'

  Esperado: um JSON com cliente_id e atividade_id.

Limpe o teste e me avise o resultado. PARE aqui — não mexa no agente ainda.

  delete from crm.atividades where ref_externa like 'wa:5531900000000%';
  delete from crm.clientes where telefone_chave = crm.chave_telefone('5531900000000');
```

---

## Etapa B — o agente passa a alimentar o CRM

Só depois que a Etapa A voltar verde.

```
No afatec-agent-core, adicione a integração com o CRM. Três regras que valem para tudo
abaixo, porque o webhook processa a mensagem de forma síncrona:

  1. A chamada ao CRM é DEPOIS da resposta ir para o cliente, nunca antes.
  2. Ela não pode lançar. Envolva de modo que qualquer erro vire log e siga.
     Atenção ao try que envolve MessageService.handle: como `sending` já é true nesse
     ponto, uma exceção ali é relançada e o webhook devolve 5xx mesmo com o cliente já
     tendo recebido a resposta.
  3. Timeout curto (3s) e sem retry. CRM fora do ar não pode fazer o WhatsApp parar.

Variáveis novas no .env, lendo o token de /root/crm-integracao.token (não escreva o
valor em nenhum arquivo versionado):

  CRM_ENABLED=true
  CRM_DRY_RUN=true          # começa em true
  CRM_URL=https://zapmaxapi.afatec.net
  CRM_TOKEN=<o token da etapa A>

Crie um cliente HTTP pequeno (src/crm/client.ts ou equivalente ao padrão do projeto) com
uma função por ponto de integração. Todas as requisições levam:

  apikey: $CRM_TOKEN
  Authorization: Bearer $CRM_TOKEN
  Content-Profile: crm
  Content-Type: application/json

PONTO 1 e 2 — toda conversa vira cliente, atividade e (no comercial) oportunidade.
Uma única chamada, em MessageService.handle, depois de sender.send e de memory.mark,
antes do return:

  POST /rest/v1/rpc/registrar_atendimento_whatsapp
  {
    "p_telefone": remoteJid.split('@')[0],
    "p_nome": <nome do contato, se houver>,
    "p_resumo": <o texto da mensagem ou o resumo da conversa>,
    "p_agente": result.agent,
    "p_abrir_oportunidade": result.agent === 'comercial'
  }

  A função é idempotente: sem p_ref ela agrupa por contato e por dia, então chamar a cada
  mensagem atualiza a mesma atividade em vez de poluir a timeline. Não precisa de estado
  no agente. Também resolve o nono dígito, então mande o número cru do JID — nada muda na
  tabela contacts.

PONTO 3 — chamada de voz do WhatsApp vira chamada perdida e tarefa de retorno.
Em normalize.ts, o evento CALL hoje morre no filtro de eventos. Não basta acrescentar
'CALL' à lista: o safeParse logo abaixo exige key.{id,remoteJid,fromMe}, que um payload
de chamada não tem, e devolveria 400 para a Evolution. Faça um desvio próprio ANTES desse
safeParse, com schema e tipo de retorno separados, e mande:

  POST /rest/v1/rpc/registrar_chamada_whatsapp
  { "p_id_externo": <id da chamada>, "p_telefone": <from sem o sufixo>, "p_payload": <o evento> }

Com CRM_DRY_RUN=true, logue o que seria enviado e não envie. Me mostre três logs de
dry-run reais (uma conversa comum, uma que foi para o comercial e, se aparecer, uma
chamada) antes de eu liberar o CRM_DRY_RUN=false.

Não faça deploy nem reinicie o agente sem me avisar. PARE e me mostre o diff.
```

---

## O que dá para conferir no CRM depois que sair do dry-run

| onde | o que deve aparecer |
|---|---|
| Clientes | cada contato do WhatsApp como lead, origem WhatsApp, um por pessoa mesmo com o nono dígito variando |
| Ficha do cliente | uma atividade `whatsapp` por dia de conversa, com o resumo |
| Funil | oportunidade na primeira etapa quando o roteador mandou para o comercial, uma por cliente |
| Agenda | tarefa "Retornar chamada de WhatsApp" em aberto, quando alguém tentar ligar |

## Como desligar

`CRM_ENABLED=false` no agente. O CRM continua de pé e o WhatsApp continua respondendo —
os dois lados são independentes de propósito.
