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
    description: "Prompt de atendimento normal com conhecimento de catálogo pré-carregado no system instruction para resposta direta em único turno"
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
> **Parent Specs:**  
> - [`SPEC-016`](./SPEC-016-integracao-google-drive-conhecimento-agentes.md) (Integração Google Drive)  
> - [`SPEC-018`](./SPEC-018-desativacao-segmentacao-crm-templates-jinja-anero-cafe.md) (Não-fragmentação de mensagens WhatsApp)  
> - [`SPEC-021`](./SPEC-021-disparo-catalogo-pdf-via-google-drive-anero-cafe.md) (Disparo de catálogo PDF)

---

## 1. Contexto e Motivação (The "Why")

Durante a investigação de causa raiz (RCA) do incidente com o contato de telefone `+55 61 9881-7744` (conversa `909` no CRM), identificou-se que o robô parou de responder devido a uma combinação de latência extrema, roundtrips redundantes de LLM e colisão de concorrência:

1. **Multi-turn Function Calling Redundante:** O modelo `gemini-3.8-flash` consumiu **136 segundos no primeiro turno** apenas para decidir invocar a ferramenta `get_catalog_overview`, e mais **141 segundos no segundo turno** para redigir o texto após o retorno da ferramenta. Para responder perguntas básicas como *"quais cafés vocês têm?"*, o sistema realizou 2 roundtrips de inferência completos, totalizando mais de 270 segundos.
2. **Ausência de Context Caching:** Toda requisição reenviava ~4.765 tokens de prompt estático sem cache no Vertex AI. O Google ADK emite warning explícito alertando que o `App` não possui `context_cache_config`, impedindo o reaproveitamento de tokens no modelo.
3. **Falha de Contenção de Concorrência (Cancelamento HTTP Ineficaz):**
   - O `evo-bot-runtime` possui debounce de 5s. Quando a janela expirou, enviou a requisição 1 para a IA.
   - Como a IA levou mais de 2 minutos para responder, o usuário mandou nova mensagem após 8 segundos.
   - O `evo-bot-runtime` cancelou o contexto do cliente HTTP em Go (`pipeline.ai.cancelled`), mas no backend Python/FastAPI (`anero-cafe-support`), **o Uvicorn não cancela corrotinas em background após desconexão do cliente HTTP**.
   - Como o endpoint `/crm/run` não possuía nenhum Mutex/Lock no Redis por `conversation_id`, a requisição 1 continuou rodando e a requisição 2 foi disparada 5 segundos depois, gerando duas corrotinas executando simultaneamente na mesma sessão do Vertex AI (`agentengine://`), degradando a performance e corrompendo o estado.
4. **Efeito Dominó de Timeout e Rejeição 422 no CRM:**
   - Aos 150 segundos (`AI_CALL_TIMEOUT_SECONDS`), o `evo-bot-runtime` abortou a espera e enviou a mensagem de erro genérica: *"Um minuto. Já te respondo"*.
   - A conversa no CRM permaneceu sem resposta humana e foi auto-resolvida por inatividade após 15 minutos (`status: "resolved"`).
   - Quando o cliente mandou nova mensagem às 00:00, o runtime tentou reenviar a mensagem de erro, mas o CRM rejeitou o dispatch com **HTTP 422 Unprocessable Entity** (proibido postar em conversas resolvidas). Além disso, a chave `crm_handoff` no Redis silenciou o robô por 24 horas.

---

## 2. Arquitetura da Solução

```
 ┌────────────────────────────────────────────────────────────────────────┐
 │                    GOOGLE DRIVE (CATÁLOGO CANÔNICO)                    │
 │               • ID: GOOGLE_DRIVE_CATALOG_FILE_ID                       │
 │               • Metadados: modifiedTime & md5Checksum                  │
 └──────────────────────────────────┬─────────────────────────────────────┘
                                    │ (Checagem leve de metadados: ~150ms)
                                    ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │               CatalogSyncService (Cache em 2 Camadas)                  │
 │   • Camada 1: Cache em Memória com TTL (ex: 300s)                      │
 │   • Camada 2: Comparação de hash/modifiedTime antes de baixar          │
 │   • Só baixa e refaz parse se o arquivo tiver sido alterado!           │
 └──────────────────────────────────┬─────────────────────────────────────┘
                                    │
                                    ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │            ADK Lifecycle Callback (before_agent / Prompt)              │
 │   • Injeta catálogo compacto no prompt de instruções (system_instruction)│
 │   • Elimina tool call de overview (resposta em 1 turno de LLM!)       │
 └──────────────────────────────────┬─────────────────────────────────────┘
                                    │
                                    ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │               Google ADK App + Vertex AI Context Caching               │
 │   • App(context_cache_config=ContextCacheConfig(ttl=1800, min=2048))   │
 │   • Vertex AI cria CachedContent para o prefixo fixo estável           │
 │   • Redução drástica de TTFT (-70%) e custo (-75%)                     │
 └────────────────────────────────────────────────────────────────────────┘
                                    ▲
                                    │
 ┌────────────────────────────────────────────────────────────────────────┐
 │             FastAPI Router (/crm/run) com Mutex Distribuído            │
 │   • Distributed Lock no Redis por conversation_id (crm_lock:{id})      │
 │   • Rejeita ou serializa requisições simultâneas na mesma sessão       │
 │   • Se conversa estiver 'resolved', reabre e limpa crm_handoff        │
 └────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Especificação Técnica e Contratos de Interface

### 3.1. Sincronização Inteligente de Catálogo (`CatalogSyncService`)
Localização: `anero_cafe/services/catalog_sync.py`

Regras de Negócio:
1. Utiliza a Service Account DWD (`GOOGLE_APPLICATION_CREDENTIALS` ou Application Default Credentials) para consultar a API do Google Drive v3.
2. Faz apenas `drive.files().get(fileId=..., fields="id, name, modifiedTime, md5Checksum")` para inspecionar os metadados.
3. Se o `modifiedTime` for idêntico ao armazenado no cache local em memória (ou Redis):
   - **ZERO downloads:** Retorna a versão parseada em memória imediatamente.
4. Se o `modifiedTime` for diferente:
   - Baixa o conteúdo do arquivo via `drive.files().get_media(fileId=...)`.
   - Realiza a formatação do catálogo compacto (nome, notas sensoriais, torra, região, preços de varejo e moagens disponíveis).
   - Atualiza o cache em memória e a chave no Redis (`anero_catalog_cache`).

```python
class CatalogSyncService:
    """Gerenciador de sincronização do catálogo de cafés com cache condicional."""

    def __init__(
        self,
        file_id: str,
        redis_client: Any | None = None,
        cache_ttl_seconds: int = 300,
    ) -> None:
        """Inicializa o serviço de sincronização."""
        ...

    async def get_compact_catalog(self, force_refresh: bool = False) -> str:
        """Retorna o texto compacto do catálogo, baixando do Drive apenas se alterado."""
        ...

    async def has_file_changed(self) -> bool:
        """Verifica se os metadados do arquivo no Google Drive mudaram."""
        ...
```

### 3.2. Injeção no Início do Agente (`before_agent_callback`)
Localização: `anero_cafe/shared_libraries/callbacks.py`

1. Na invocação de `before_agent(callback_context)`:
   - O serviço `catalog_sync_service.get_compact_catalog()` é chamado.
   - O catálogo compacto é anexado ao contexto da sessão ou injetado nas instruções ativas do agente (`DynamicPromptManager` / `system_instruction`).
2. O modelo passa a ter conhecimento prévio e estático de todos os cafés da cafeteria.
3. **Regra de Eliminação de Roundtrip:** A ferramenta `get_catalog_overview` torna-se obsoleta para perguntas simples de catálogo. O prompt instrui o modelo a responder diretamente sobre os cafés usando as informações já presentes nas instruções do sistema.

### 3.3. Habilitação de Context Caching no Google ADK
Localização: `anero_cafe/agent.py` e `anero_cafe/__init__.py`

1. O `anero_cafe/agent.py` define a configuração de cache de contexto:
```python
from google.adk.apps.app import App
from google.adk.agents.context_cache_config import ContextCacheConfig
from google.genai.types import HttpOptions

context_cache_config = ContextCacheConfig(
    ttl_seconds=1800,        # 30 minutos de vida útil no Vertex AI
    cache_intervals=10,      # Reuso de até 10 turnos antes de invalidar
    min_tokens=2048,         # Piso mínimo de tokens para ativar cache
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
3. O `AgentLoader` do ADK detecta a entidade `app` e injeta `context_cache_config` diretamente no `Runner`, eliminando o warning e ativando o `GeminiContextCacheManager`.

### 3.4. Lock Distribuído de Concorrência e Auto-Reabertura (Solução C)
Localização: `anero_cafe/routers/crm.py`

1. **Distributed Lock (Mutex):**
   - Ao receber `POST /crm/run`, o router tenta adquirir a chave `crm_lock:{context_id}` no Redis com timeout de aquisição não-bloqueante e TTL de segurança de 180 segundos:
     ```python
     lock_acquired = await redis_client.set(
         f"crm_lock:{context_id}", "locked", nx=True, ex=180
     )
     if not lock_acquired:
         # Já existe uma requisição em execução para este context_id
         logger.warning(f"Concorrência detectada: requisição para {context_id} já em andamento.")
         return {
             "jsonrpc": "2.0",
             "id": request.id,
             "result": {"artifacts": [{"parts": [{"type": "text", "text": ""}]}]},
         }
     ```
   - No bloco `finally`, a chave `crm_lock:{context_id}` é liberada atomicamente.
2. **Auto-Reabertura de Conversa Resolvida:**
   - Antes de iniciar a inferência, consulta o status da conversa via `crm_api.get_conversation(context_id)`.
   - Se `status == "resolved"`:
     - Executa PATCH no CRM para reabrir a conversa (`status: "open"`).
     - Deleta a chave `crm_handoff:{context_id}` no Redis.
     - Permite que o robô processe a mensagem e responda normalmente.

### 3.5. Governança de Prompts (§3.5)
Os prompts governados no Langfuse são refinados:
- **`anero_cafe/instruction`**: Adição da diretriz clara: *"Você possui o catálogo oficial de cafés especiais embutido diretamente nas instruções do seu sistema. Ao responder dúvidas sobre os cafés disponíveis, características sensoriais ou preços de varejo, responda IMEDIATAMENTE usando essas informações, sem chamar nenhuma ferramenta externa."*
- **`anero_cafe/atendimento_normal`**: Mesma diretriz, mantendo a chamada da ferramenta `send_catalog_pdf` estritamente reservada para quando o cliente pedir explicitamente *"quero o catálogo em PDF"* ou *"envie o arquivo/cardápio em PDF"*.

---

## 4. Critérios de Aceitação (Gherkin)

### Cenário 1: Reutilização de catálogo em cache sem re-download no Google Drive
- **Dado** que o agente Anero Café recebeu uma mensagem de atendimento
- **E** o arquivo do catálogo no Google Drive possui `modifiedTime` idêntico ao registrado no cache local
- **Quando** o callback `before_agent` for executado
- **Então** nenhum download do binário no Google Drive deve ser realizado
- **E** o catálogo pré-processado em memória deve ser injetado nas instruções do agente em menos de 100ms.

### Cenário 2: Download automático quando catálogo for alterado no Google Drive
- **Dado** que o administrador atualizou os preços ou cafés no arquivo do Google Drive (novo `modifiedTime`)
- **Quando** uma nova mensagem de cliente for recebida pelo agente
- **Então** o `CatalogSyncService` deve detectar a alteração de metadados
- **E** baixar o novo arquivo do Google Drive, atualizar o cache local e injetar o catálogo atualizado no prompt.

### Cenário 3: Resposta de catálogo em 1 único turno de LLM sem tool calling
- **Dado** que o cliente pergunta *"Quais cafés especiais vocês têm?"*
- **Quando** o agente processar a mensagem
- **Então** o modelo deve gerar a resposta completa em um único turno de inferência (`events = [model_turn]`)
- **E** nenhuma chamada para `get_catalog_overview` deve ser executada
- **E** a latência de resposta deve ser inferior a 25 segundos.

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

### Cenário 6: Reabertura automática de conversa resolvida
- **Dado** que a conversa `conv-123` foi resolvida por inatividade (`status: "resolved"`)
- **Quando** o cliente enviar uma nova mensagem
- **Então** o router deve reabrir a conversa no CRM (`status: "open"`)
- **E** excluir a chave `crm_handoff:conv-123` no Redis
- **E** despachar a resposta do bot com sucesso sem gerar erro HTTP 422.

---

## 5. Plano de Rollout e Decomposição em Ondas Topológicas

- [ ] **Onda 1 (`paralax-ia/anero-cafe-support`):**
  - Implementar `anero_cafe/services/catalog_sync.py` com testes unitários com TDD em `tests/unit/test_catalog_sync.py`.
  - Integrar `before_agent` com injeção do catálogo e atualizar `tests/unit/test_greeting_and_prompt_rules.py`.
  - Configurar `App` com `ContextCacheConfig` em `anero_cafe/agent.py` e exportar em `anero_cafe/__init__.py`.
  - Implementar Lock Distribuído e auto-reabertura de conversas resolvidas em `anero_cafe/routers/crm.py`.
  - Sincronizar versões draft dos prompts no Langfuse (`anero_cafe/instruction` e `anero_cafe/atendimento_normal`).
  - Executar suíte completa (`just verify`).
  - Abrir PR no repositório `anero-cafe-support`.

- [ ] **Onda 2 (`paralax-ia/argocd`):**
  - Adicionar variáveis declarativas de ambiente no manifesto `apps/anero-cafe-support/overlays/prod/`:
    - `ENABLE_CONTEXT_CACHE=true`
    - `CONTEXT_CACHE_TTL_SECONDS=1800`
    - `CATALOG_METADATA_CHECK_INTERVAL_SECONDS=300`
  - Abrir PR no repositório `argocd`.
