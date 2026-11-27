---
spec_id: SPEC-023
title: "Context Caching Vertex AI, Lock de Concorrência Distribuído e Injeção Dinâmica de Catálogo com Cache de Alteração no Início do Agente (Anero Café)"
product:
  - anero-cafe-support
  - paralax-platform
capability: conversational-ai-agent
scope: multi-repo
bounded_context: "Conversational Agent / Performance, Cache & Concorrência"
origin_module: paralax-spec-hub
target_repositories:
  - repo: paralax-ia/anero-cafe-support
    wave: 1
    role: ai-agent
    prompts:
      - anero_cafe/instruction
      - anero_cafe/atendimento_normal
  - repo: paralax-ia/argocd
    wave: 2
    role: gitops
prompts:
  - name: anero_cafe/instruction
    target_repo: paralax-ia/anero-cafe-support
    file: anero_cafe/prompts.py
    symbol: INSTRUCTION
    description: "Instrução de sistema para o agente Anero Café com catálogo injetado dinamicamente no início da execução e suporte a Context Caching"
  - name: anero_cafe/atendimento_normal
    target_repo: paralax-ia/anero-cafe-support
    file: anero_cafe/prompts.py
    symbol: INSTRUCTION_ATENDIMENTO_NORMAL
    description: "Prompt de atendimento normal com catálogo compacto pré-carregado no system instruction e gatilho de envio de PDF alinhado à SPEC-021/SPEC-022"
status: APPROVED
---

# SPEC-023: Context Caching Vertex AI, Lock de Concorrência Distribuído e Injeção Dinâmica de Catálogo com Cache de Alteração no Início do Agente (Anero Café)

> **Product:** [`anero-cafe-support`](../products/anero-cafe-support.yaml) | [`paralax-platform`](../products/paralax-platform.yaml)  
> **Business Capability:** [`conversational-ai-agent`](../capabilities/conversational-ai-agent/capability.yaml)  
> **Scope:** Agente de IA (`anero-cafe-support`) e Configurações GitOps (`argocd`)  
> **Bounded Context:** Conversational Agent / Performance, Cache & Concorrência  
> **Status:** APPROVED  
> **Autor:** Eduardo F. Santos  
> **Data de Criação:** 2026-11-27  
> **Data de Revisão:** 2026-11-27  
> **Parent Specs & Alinhamento:**  
> - [`SPEC-016`](./SPEC-016-integracao-google-drive-conhecimento-agentes.md) (Integração Google Drive e Service Accounts)  
> - [`SPEC-018`](./SPEC-018-desativacao-segmentacao-crm-templates-jinja-anero-cafe.md) (Não-fragmentação de mensagens no WhatsApp)  
> - [`SPEC-021`](./SPEC-021-disparo-catalogo-pdf-via-google-drive-anero-cafe.md) (Disparo de catálogo em PDF como anexo nativo de documento)  
> - [`SPEC-022`](./SPEC-022-generalizacao-pdf-drive-md5.md) (Padrão de cache em duas camadas no Google Drive, verificação de integridade MD5 e desacoplamento 12-Factor)

---

## 1. Contexto e Motivação (The "Why")

Durante a investigação profunda de causa raiz (RCA com Ishikawa e 5 Whys) do incidente com o contato de telefone `+55 61 9881-7744` (conversa `909` no CRM), identificou-se que o robô parou de responder devido à conjunção de **três fatores sistêmicos**:

1. **Multi-turn Function Calling Redundante (Latência > 270s):**
   - Na **SPEC-021**, estabeleceu-se o envio do catálogo em PDF como anexo nativo. Porém, quando o cliente perguntava abertamente *"quais cafés vocês têm?"*, o modelo realizava múltiplos roundtrips de LLM: gastava **136 segundos no primeiro turno** apenas para decidir invocar a ferramenta `get_catalog_overview`, e mais **141 segundos no segundo turno** para redigir o texto após o retorno da ferramenta.
   - O catálogo de cafés da cafeteria é relativamente pequeno e estável (6 rótulos principais: *Especial da Casa, Catuaí Amarelo, Bourbon Amarelo, etc.*). Forçar o modelo a rodar um ciclo de function calling toda vez que um cliente pergunta sobre cafés disponíveis sobrecarrega o tempo de resposta e degrada a experiência.

2. **Ausência de Context Caching (Warning do Google ADK):**
   - O Google ADK emite warning explícito alertando que o `App` não possui `context_cache_config`. A cada transferência ou novo turno, todos os ~4.765 tokens de prompt estático e declarações de ferramentas eram reenviados e processados do zero pelo Vertex AI sem nenhum cache, maximizando o TTFT (*Time to First Token*) e o custo.

3. **Falha de Contenção de Concorrência e Cancelamento HTTP Ineficaz:**
   - O `evo-bot-runtime` possui debounce de 5s. Quando a janela expirou, enviou a requisição 1 para o agente.
   - Como a IA levou mais de 2 minutos para responder, o cliente enviou uma segunda mensagem 8 segundos depois.
   - O `evo-bot-runtime` cancelou o contexto do cliente HTTP em Go (`pipeline.ai.cancelled`), mas no backend Python (`anero-cafe-support`), **o Uvicorn/FastAPI não cancela corrotinas em execução quando o cliente HTTP fecha o socket TCP**.
   - Como o endpoint `/crm/run` não possuía nenhum Mutex/Lock no Redis por `conversation_id`, a requisição 1 continuou rodando em background e a requisição 2 foi disparada 5 segundos depois, gerando duas corrotinas executando simultaneamente na mesma sessão do Vertex AI (`agentengine://`), causando colisão de eventos e exaustão de cotas.

4. **Efeito Dominó de Timeout e Rejeição 422 no CRM:**
   - Aos 150 segundos (`AI_CALL_TIMEOUT_SECONDS`), o `evo-bot-runtime` abortou a espera e enviou a mensagem de erro genérica: *"Um minuto. Já te respondo"*.
   - A conversa no CRM permaneceu sem resposta humana e foi auto-resolvida por inatividade após 15 minutos (`status: "resolved"`).
   - Quando o cliente mandou nova mensagem às 00:00, o runtime tentou reenviar a mensagem de erro, mas o CRM rejeitou o dispatch com **HTTP 422 Unprocessable Entity** (proibido postar mensagens ou anexos em conversas resolvidas). Para completar, a chave `crm_handoff` no Redis silenciou o robô por 24 horas.

---

## 2. Alinhamento Arquitetural com as SPECs 021 e 022

A presente especificação integra e harmoniza as decisões de arquitetura estabelecidas nas **SPECs 021 e 022**:

| Aspecto Arquitetural | SPEC-021 | SPEC-022 | SPEC-023 (Esta Spec) |
| :--- | :--- | :--- | :--- |
| **Papel do Google Drive** | SSOT do catálogo visual em PDF. | SSOT universal de documentos e mídias. | SSOT tanto do documento PDF quanto dos metadados de texto do catálogo. |
| **Mecanismo de Cache no Drive** | Cache local de URL com TTL de 3600s. | Cache em 2 camadas: Memória (TTL) + Polling leve de `modifiedTime` e `md5Checksum`. | Aplica o padrão de 2 camadas da SPEC-022: verifica `modifiedTime` e hash antes de qualquer download. |
| **Forma de Entrega ao Usuário** | Anexo nativo de documento PDF via WhatsApp. | Validação criptográfica MD5 do binário entregue. | **Resposta textual instantânea em 1 turno** (catálogo embutido no prompt) + **Oferta do PDF** disparado via tool da SPEC-021/SPEC-022 quando solicitado. |
| **Estabilidade de Prompt** | Dinâmico via Langfuse. | N/A (biblioteca core). | Prompt do sistema 100% determinístico e estável enquanto o Drive não muda, viabilizando **Context Caching no Vertex AI**. |
| **Concorrência e Resiliência** | Timeout de 150s no runtime. | Fallback resiliente no storage em caso de queda do Drive. | **Distributed Mutex Lock no Redis** (`crm_lock:{id}`) e **Auto-reabertura de conversas resolvidas** no CRM. |

---

## 3. Arquitetura da Solução

```
 ┌────────────────────────────────────────────────────────────────────────┐
 │                    GOOGLE DRIVE (CATÁLOGO CANÔNICO)                    │
 │               • ID: GOOGLE_DRIVE_CATALOG_FILE_ID                       │
 │               • Metadados: modifiedTime & md5Checksum                  │
 └──────────────────────────────────┬─────────────────────────────────────┘
                                    │ (Checagem leve de metadados: ~150ms)
                                    ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │               CatalogSyncService (Padrão SPEC-022)                     │
 │   • Camada 1: Cache em Memória com TTL configurável (ex: 300s)         │
 │   • Camada 2: Comparação de modifiedTime / md5Checksum                 │
 │   • ZERO downloads se o arquivo não tiver sofrido alteração!           │
 │   • Fallback gracioso: serve último cache válido se Drive oscilar      │
 └──────────────────────────────────┬─────────────────────────────────────┘
                                    │
                                    ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │            ADK Lifecycle Callback (before_agent / Prompt)              │
 │   • Injeta catálogo compacto no prompt de instruções (system_instruction)│
 │   • Prompt estático e imutável durante turnos da conversa              │
 │   • Elimina tool call get_catalog_overview (resposta em 1 turno!)      │
 └──────────────────────────────────┬─────────────────────────────────────┘
                                    │
                                    ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │               Google ADK App + Vertex AI Context Caching               │
 │   • App(context_cache_config=ContextCacheConfig(ttl=1800, min=2048))   │
 │   • Vertex AI cria CachedContent para o prefixo fixo estável           │
 │   • Redução de TTFT (-70%) e desconto de 75% no custo de tokens       │
 └────────────────────────────────────────────────────────────────────────┘
                                    ▲
                                    │
 ┌────────────────────────────────────────────────────────────────────────┐
 │             FastAPI Router (/crm/run) com Mutex Distribuído            │
 │   • Distributed Lock no Redis por conversation_id (crm_lock:{id})      │
 │   • Serializa/bloqueia requisições simultâneas na mesma sessão         │
 │   • Se a conversa estiver 'resolved', reabre e limpa o crm_handoff     │
 └────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Especificação Técnica e Contratos de Interface

### 4.1. Sincronização Inteligente de Catálogo (`CatalogSyncService`)
Localização: `anero_cafe/services/catalog_sync.py`

Em perfeita harmonia com o padrão estabelecido no `GoogleDrivePdfManager` da **SPEC-022**:
1. Utiliza a Service Account DWD para autenticação com a API do Google Drive v3 (`https://www.googleapis.com/auth/drive.readonly`).
2. **Camada 1 (Memória / TTL):** Mantém em cache o texto do catálogo compacto formatado, o timestamp da última checagem (`last_checked_at`) e o `last_modified_time` / `last_md5`. Se o intervalo desde a última checagem for menor que `CATALOG_CACHE_TTL_SECONDS` (padrão: 300s), retorna imediatamente da memória sem nenhuma chamada de rede.
3. **Camada 2 (Polling Leve de Metadados):** Ao expirar o TTL, faz apenas `drive_service.files().get(fileId=..., fields="id, modifiedTime, md5Checksum")`.
   - Se `modifiedTime` (ou `md5Checksum`) for idêntico ao do cache: atualiza `last_checked_at = now()` e **NÃO realiza download**.
   - Se for diferente: baixa o binário/conteúdo via `files().get_media()`, executa a formatação do resumo do cardápio compacto e atualiza o cache local e Redis (`anero_catalog_cache`).
4. **Resiliência e Fallback (SPEC-022):** Se a API do Google Drive retornar 429, 5xx ou timeout de rede, o serviço registra aviso em log e continua servindo o último catálogo em cache válido, assegurando 100% de disponibilidade no atendimento.

```python
class CatalogSyncService:
    """Gerenciador de sincronização do catálogo de cafés com cache condicional em 2 camadas."""

    def __init__(
        self,
        file_id: str,
        redis_client: Any | None = None,
        cache_ttl_seconds: int = 300,
        drive_service: Any | None = None,
    ) -> None:
        """Inicializa o serviço de sincronização seguindo o padrão 12-Factor."""
        ...

    async def get_compact_catalog(self, force_refresh: bool = False) -> str:
        """Retorna o texto compacto do catálogo, baixando do Drive apenas se alterado."""
        ...

    async def has_file_changed(self) -> bool:
        """Verifica se os metadados do arquivo no Google Drive mudaram via modifiedTime/MD5."""
        ...
```

### 4.2. Injeção no Início do Agente e Relação com o Catálogo em PDF (SPEC-021)
Localização: `anero_cafe/shared_libraries/callbacks.py`

1. Na invocação de `before_agent(callback_context)`:
   - O serviço `catalog_sync_service.get_compact_catalog()` é chamado.
   - O catálogo compacto de cafés é injetado nas instruções do agente (`DynamicPromptManager` / `system_instruction`).
2. **Eliminação do Roundtrip de LLM:** O modelo passa a ter conhecimento inato de todos os cafés, notas sensoriais, preços de varejo e moagens. Perguntas como *"quais cafés vocês têm?"*, *"qual o valor do café da casa?"* ou *"vocês têm moagem para prensa?"* são respondidas em **1 único turno de LLM** (< 20 segundos).
3. **Harmonização com a SPEC-021 (Disparo de PDF):**
   - A ferramenta `send_catalog_pdf` (que utiliza o `GoogleDrivePdfManager` da SPEC-022) permanece ativa e é acionada:
     - Quando o cliente solicitar expressamente o arquivo (ex: *"me manda o catálogo em PDF"*, *"tem cardápio para baixar?"*).
     - Ou como fechamento proativo opcional sugerido pelo modelo: *"Se quiser ver as fotos e detalhes diagramados, posso te enviar o nosso catálogo em PDF também!"*.
   - A ferramenta legada `get_catalog_overview` é deprecada para consultas conversacionais normais, eliminando o gargalo de latência.

### 4.3. Habilitação de Context Caching no Google ADK
Localização: `anero_cafe/agent.py` e `anero_cafe/__init__.py`

Como o catálogo é injetado no início do agente de forma idempotente e só muda quando o arquivo do Drive for editado, o prefixo do prompt do sistema permanece **estável e constante entre turnos de conversa**, preenchendo todos os requisitos para o Context Caching do Gemini:

1. O `anero_cafe/agent.py` define a configuração de cache de contexto:
```python
from google.adk.apps.app import App
from google.adk.agents.context_cache_config import ContextCacheConfig
from google.genai.types import HttpOptions

context_cache_config = ContextCacheConfig(
    ttl_seconds=1800,        # 30 minutos de vida útil no Vertex AI
    cache_intervals=10,      # Reuso de até 10 turnos antes de revalidar
    min_tokens=2048,         # Piso mínimo de tokens (atendido pelos ~4.700 tokens do prompt)
    create_http_options=HttpOptions(timeout=10000),
)

app = App(
    name="anero_cafe",
    root_agent=root_agent,
    context_cache_config=context_cache_config,
)
```
2. O `anero_cafe/__init__.py` exporta `app` e `root_agent`:
```python
from .agent import app, root_agent

__all__ = ["app", "root_agent"]
```
3. O `AgentLoader` do ADK detecta a entidade `app`, repassa `context_cache_config` ao `Runner` e o `GeminiContextCacheManager` ativa o cache de contexto no Vertex AI Reasoning Engine.

### 4.4. Lock Distribuído de Concorrência e Auto-Reabertura (Solução C)
Localização: `anero_cafe/routers/crm.py`

1. **Distributed Lock (Mutex no Redis):**
   - Ao receber `POST /crm/run`, o router tenta adquirir o lock atômico:
     ```python
     lock_acquired = await redis_client.set(
         f"crm_lock:{context_id}", "locked", nx=True, ex=180
     )
     if not lock_acquired:
         logger.warning("Concorrência detectada: requisição para contextId %s em processamento.", context_id)
         return {
             "jsonrpc": "2.0",
             "id": request.id,
             "result": {"artifacts": [{"parts": [{"type": "text", "text": ""}]}]},
         }
     ```
   - No bloco `finally`, a chave `crm_lock:{context_id}` é liberada via script Lua ou verificação atômica.
2. **Auto-Reabertura de Conversa Resolvida:**
   - Consulta o status da conversa via `crm_api.get_conversation(context_id)`.
   - Se `status == "resolved"`:
     - Reabre a conversa no CRM (`status: "open"`).
     - Deleta a chave `crm_handoff:{context_id}` no Redis.
     - Permite que o robô responda e entregue textos ou anexos PDF sem que o CRM rejeite com `HTTP 422 Unprocessable Entity`.

### 4.5. Governança de Prompts (§3.5)
Os prompts governados no Langfuse são refinados:
- **`anero_cafe/instruction`**: Adição da diretriz clara: *"Você possui o catálogo oficial de cafés especiais embutido diretamente nas instruções do seu sistema. Ao responder dúvidas sobre cafés disponíveis, notas sensoriais ou preços de varejo, responda IMEDIATAMENTE usando essas informações, sem chamar nenhuma ferramenta externa de overview."*
- **`anero_cafe/atendimento_normal`**: Mesma diretriz, mantendo a chamada da ferramenta `send_catalog_pdf` (SPEC-021 / SPEC-022) reservada para quando o cliente pedir explicitamente o arquivo ou cardápio em PDF.

---

## 5. Critérios de Aceitação (Gherkin)

### Cenário 1: Reutilização de catálogo em cache sem re-download no Google Drive (Padrão SPEC-022)
- **Dado** que o agente Anero Café recebeu uma mensagem de atendimento
- **E** o arquivo do catálogo no Google Drive possui `modifiedTime` e `md5Checksum` idênticos aos do cache local
- **Quando** o callback `before_agent` for executado
- **Então** nenhum download de binário no Google Drive deve ser realizado
- **E** o catálogo pré-processado em memória deve ser injetado nas instruções do agente em menos de 50ms.

### Cenário 2: Download automático quando catálogo for alterado no Google Drive
- **Dado** que a equipe comercial alterou os preços ou cafés no arquivo do Google Drive (novo `modifiedTime`)
- **Quando** uma nova mensagem de cliente for recebida pelo agente
- **Então** o `CatalogSyncService` deve detectar a alteração de metadados
- **E** baixar o novo arquivo do Google Drive, atualizar o cache local e injetar o catálogo atualizado no prompt.

### Cenário 3: Resposta de catálogo em 1 único turno de LLM sem tool calling
- **Dado** que o cliente pergunta *"Quais cafés especiais vocês têm?"*
- **Quando** o agente processar a mensagem
- **Então** o modelo deve gerar a resposta completa em um único turno de inferência (`events = [model_turn]`)
- **E** nenhuma chamada para `get_catalog_overview` deve ser executada
- **E** a latência de resposta deve ser inferior a 20 segundos.

### Cenário 4: Ativação de Context Caching no Google ADK
- **Dado** que a aplicação `anero_cafe` é inicializada
- **Quando** o container subir no GKE
- **Então** a instância de `App` deve conter `context_cache_config` configurada com `ttl_seconds=1800`
- **E** nenhum warning `App can transfer between agents but has no context_cache_config` deve ser emitido nos logs.

### Cenário 5: Contenção de Concorrência com Lock Distribuído no Redis (Solução C)
- **Dado** que uma requisição HTTP para a conversa `conv-123` está em processamento no pod
- **Quando** uma segunda requisição HTTP para a mesma conversa `conv-123` chegar ao endpoint `/crm/run`
- **Então** o router deve verificar que o lock `crm_lock:conv-123` já existe no Redis
- **E** não deve disparar uma segunda execução concorrente na mesma sessão do Vertex AI.

### Cenário 6: Reabertura automática de conversa resolvida e prevenção de erro 422
- **Dado** que a conversa `conv-123` foi resolvida por inatividade (`status: "resolved"`)
- **Quando** o cliente enviar uma nova mensagem
- **Então** o router deve reabrir a conversa no CRM (`status: "open"`)
- **E** excluir a chave `crm_handoff:conv-123` no Redis
- **E** despachar a resposta do bot com sucesso sem gerar erro HTTP 422 no `evo-bot-runtime`.

---

## 6. Plano de Rollout e Decomposição em Ondas Topológicas

- [ ] **Onda 1 (`paralax-ia/anero-cafe-support`):**
  - Implementar `anero_cafe/services/catalog_sync.py` com testes unitários com TDD em `tests/unit/test_catalog_sync.py` cobrindo o cache em 2 camadas e validação de `modifiedTime`/MD5.
  - Integrar `before_agent` com injeção de catálogo no system instruction e atualizar `tests/unit/test_greeting_and_prompt_rules.py`.
  - Configurar `App` com `ContextCacheConfig` em `anero_cafe/agent.py` e exportar em `anero_cafe/__init__.py`.
  - Implementar Lock Distribuído no Redis e auto-reabertura de conversas resolvidas em `anero_cafe/routers/crm.py`.
  - Sincronizar versões draft dos prompts no Langfuse (`anero_cafe/instruction` e `anero_cafe/atendimento_normal`).
  - Executar suíte completa de verificação (`just verify`).
  - Abrir PR no repositório `anero-cafe-support`.

- [ ] **Onda 2 (`paralax-ia/argocd`):**
  - Adicionar variáveis declarativas de ambiente no manifesto `apps/anero-cafe-support/overlays/prod/`:
    - `ENABLE_CONTEXT_CACHE=true`
    - `CONTEXT_CACHE_TTL_SECONDS=1800`
    - `CATALOG_CACHE_TTL_SECONDS=300`
    - `CRM_LOCK_TIMEOUT_SECONDS=180`
  - Abrir PR no repositório `argocd`.
