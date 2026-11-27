---
spec_id: SPEC-023
title: "Context Caching no ADK, Injeção Dinâmica da Lista de Preços no System Prompt e Lock de Concorrência por Conversa no Backend"
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
    description: "Instrução de sistema para o agente Anero Café com a lista de preços embutida dinamicamente no system instruction e suporte a Context Caching"
  - name: anero_cafe/atendimento_normal
    target_repo: paralax-ia/anero-cafe-support
    file: anero_cafe/prompts.py
    symbol: INSTRUCTION_ATENDIMENTO_NORMAL
    description: "Prompt de atendimento normal com lista de preços pré-carregada para resposta em único turno e ferramenta send_catalog_pdf preservada para envio de anexo"
status: APPROVED
---

# SPEC-023: Context Caching no ADK, Injeção Dinâmica da Lista de Preços no System Prompt e Lock de Concorrência por Conversa no Backend

> **Product:** [`anero-cafe-support`](../products/anero-cafe-support.yaml) | [`paralax-platform`](../products/paralax-platform.yaml)  
> **Business Capability:** [`conversational-ai-agent`](../capabilities/conversational-ai-agent/capability.yaml)  
> **Scope:** Agente de IA (`anero-cafe-support`) e GitOps (`argocd`)  
> **Bounded Context:** Conversational Agent / Performance, Cache & Concorrência  
> **Status:** APPROVED  
> **Autor:** Eduardo F. Santos  
> **Data de Criação:** 2026-11-27  
> **Distinção Fundamental de Arquivos do Anero Café:**  
> - **Arquivo 1 - Catálogo PDF (`GOOGLE_DRIVE_CATALOG_PDF_FILE_ID`):** Definido e governado pelas SPECs 021 e 022. É o catálogo visual diagramado em PDF enviado como documento anexo no WhatsApp via ferramenta `send_catalog_pdf` (usando o `GoogleDrivePdfManager`). **Permanece inalterado nesta spec.**  
> - **Arquivo 2 - Lista de Preços e Cafés (`GOOGLE_DRIVE_PF_FILE_ID`):** Arquivo de dados/texto no Google Drive contendo a relação de cafés, características sensoriais, moagens e tabela de preços de varejo. **É o foco da Solução A desta spec.**

---

## 1. Contexto e Objetivos

Durante a investigação de causa raiz (RCA) do incidente com o contato `+55 61 9881-7744` (conversa `909` no CRM), diagnosticou-se que o robô parou de responder devido à conjunção de roundtrips excessivos de LLM, ausência de cache de contexto no Vertex AI e concorrência descontrolada entre mensagens simultâneas.

Esta especificação possui **três objetivos estritos e bem definidos**:

1. **Habilitar o Context Caching no Google ADK / Vertex AI:**
   Configurar `context_cache_config` na entidade `App` do ADK para criar e manter em cache no Vertex AI o prefixo fixo da aplicação (system instruction longo + schemas de ferramentas), reduzindo drasticamente o TTFT (*Time to First Token*) e o custo de inferência.
2. **Evitar a Chamada de Tool para a Lista de Preços (Solução A):**
   Baixar o arquivo da **lista de preços** (`GOOGLE_DRIVE_PF_FILE_ID`) via callback no início do agente (`before_agent`), utilizando **validação de alteração do arquivo** (`modifiedTime` / `md5Checksum`) no Google Drive para só baixar se houver alteração real, e injetar o texto da lista de preços diretamente no **system prompt**. Com isso, o modelo responde sobre cafés e preços em **1 único turno de LLM**, eliminando a tool call redundante de `get_catalog_overview` (que demorava 136s por turno).
3. **Criar o Lock por Conversa no Backend (Solução C):**
   Implementar um Mutex Distribuído no Redis por `conversation_id` (`crm_lock:{context_id}`) no endpoint `/crm/run` do backend Python, garantindo que múltiplas mensagens enviadas em rajada pelo usuário não disparem execuções concorrentes na mesma sessão do Vertex AI.

---

## 2. Arquitetura da Solução

```
 ┌────────────────────────────────────────────────────────────────────────┐
 │            GOOGLE DRIVE: LISTA DE PREÇOS (GOOGLE_DRIVE_PF_FILE_ID)     │
 │            • Metadados: modifiedTime & md5Checksum                     │
 └──────────────────────────────────┬─────────────────────────────────────┘
                                    │ (Checagem leve de metadados: ~150ms)
                                    ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │            PriceListSyncService (Cache com Validação de Alteração)     │
 │   • Camada 1: Cache em Memória com TTL (300s)                          │
 │   • Camada 2: Comparação de modifiedTime / md5Checksum                 │
 │   • ZERO downloads se o arquivo de preços não mudou no Drive!          │
 └──────────────────────────────────┬─────────────────────────────────────┘
                                    │
                                    ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │            ADK Lifecycle Callback (before_agent / Prompt)              │
 │   • Injeta a lista de preços no prompt de instruções (system_instruction)│
 │   • Prompt estático e imutável durante os turnos da conversa           │
 │   • Elimina tool call get_catalog_overview (resposta em 1 turno!)      │
 └──────────────────────────────────┬─────────────────────────────────────┘
                                    │
                                    ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │               Google ADK App + Vertex AI Context Caching               │
 │   • App(context_cache_config=ContextCacheConfig(ttl=1800, min=2048))   │
 │   • Vertex AI cria CachedContent para o prefixo fixo estável           │
 │   • Redução de TTFT (-70%) e desconto de 75% no custo de tokens        │
 └────────────────────────────────────────────────────────────────────────┘
                                    ▲
                                    │
 ┌────────────────────────────────────────────────────────────────────────┐
 │         FastAPI Router (/crm/run) com Lock por Conversa (Solução C)    │
 │   • Distributed Lock no Redis por conversation_id (crm_lock:{id})      │
 │   • Bloqueia requisições simultâneas na mesma sessão Vertex AI         │
 │   • Liberação atômica no bloco finally                                 │
 └────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Especificação Técnica dos Três Pilares

### 3.1. Pilar 1: Habilitação do Context Caching no Google ADK
Localização: `anero_cafe/agent.py` e `anero_cafe/__init__.py`

1. No arquivo `anero_cafe/agent.py`, define-se a instância de `ContextCacheConfig` e envelopa-se o agente na entidade de alto nível `App`:
```python
from google.adk.apps.app import App
from google.adk.agents.context_cache_config import ContextCacheConfig
from google.genai.types import HttpOptions

context_cache_config = ContextCacheConfig(
    ttl_seconds=1800,        # 30 minutos de vida útil no Vertex AI
    cache_intervals=10,      # Reuso de até 10 turnos antes de invalidar
    min_tokens=2048,         # Piso mínimo de tokens para Gemini 2.5 / 3.x
    create_http_options=HttpOptions(timeout=10000),
)

app = App(
    name="anero_cafe",
    root_agent=root_agent,
    context_cache_config=context_cache_config,
)
```

2. No `anero_cafe/__init__.py`, expõe-se `app` e `root_agent`:
```python
from .agent import app, root_agent

__all__ = ["app", "root_agent"]
```

3. O `AgentLoader` do ADK reconhece a variável `app` do tipo `App`, injeta `context_cache_config` no `Runner` e ativa o `GeminiContextCacheManager`. Como o prompt estático da Anero possui mais de 4.700 tokens (acima do piso mínimo), o Vertex AI instancia o `CachedContent` automaticamente.

---

### 3.2. Pilar 2: Injeção da Lista de Preços no System Prompt com Cache de Alteração (Solução A)
Localização: `anero_cafe/services/price_list_sync.py` e `anero_cafe/shared_libraries/callbacks.py`

1. **Serviço de Sincronização da Lista de Preços (`PriceListSyncService`):**
   - Aponta para o arquivo de texto/dados da lista de preços (`GOOGLE_DRIVE_PF_FILE_ID`).
   - Mantém cache em memória do texto formatado e dos metadados (`last_modified_time`, `last_md5`, `last_checked_at`).
   - **Validação de Alteração:**
     - Ao ser consultado, se o tempo decorrido for menor que o TTL configurável (`PRICE_LIST_CACHE_TTL_SECONDS=300`), retorna imediatamente da memória sem chamadas de rede.
     - Se expirado, realiza uma consulta leve de metadados no Google Drive v3 (`drive.files().get(fileId=..., fields="id, modifiedTime, md5Checksum")`).
     - Se `modifiedTime` ou `md5Checksum` for idêntico ao do cache: atualiza `last_checked_at = now()` e **não realiza download**.
     - Se houver alteração remota: baixa o conteúdo (`files().get_media()`), executa o parse das tabelas de cafés e preços, atualiza o cache e retorna o texto consolidado.
   - **Resiliência:** Se a API do Google Drive oscilar (429/5xx), utiliza o último cache válido em memória.

2. **Injeção via Callback no Início do Agente (`before_agent`):**
   - No callback `before_agent(callback_context)` em `anero_cafe/shared_libraries/callbacks.py`:
     - Obtém o texto da lista de preços atualizada via `price_list_sync_service.get_compact_price_list()`.
     - Injeta a lista de preços diretamente nas instruções do sistema (`DynamicPromptManager` / `system_instruction`).
   - **Estabilidade do Prompt:** Como a lista de preços só muda quando alguém edita o arquivo no Drive, o prompt permanece idêntico entre os turnos, garantindo **estabilidade total para o Context Caching do Vertex AI**.

3. **Eliminação da Chamada de Tool:**
   - As instruções no Langfuse orientam o modelo a responder sobre cafés, moagens e preços de varejo utilizando diretamente a lista de preços embutida no prompt.
   - O modelo responde em **1 único turno de LLM** (< 20 segundos), eliminando a chamada de `get_catalog_overview`.
   - A ferramenta `send_catalog_pdf()` (SPEC-021/SPEC-022) permanece reservada exclusivamente para quando o cliente pedir expressamente o documento PDF anexo.

---

### 3.3. Pilar 3: Lock Distribuído de Concorrência por Conversa no Backend (Solução C)
Localização: `anero_cafe/routers/crm.py`

1. **Mecanismo de Lock no FastAPI (`POST /crm/run`):**
   - Ao receber a requisição do CRM/runtime, tenta adquirir a chave `crm_lock:{context_id}` no Redis de forma atômica e não-bloqueante (`nx=True`, `ex=180`):
     ```python
     lock_acquired = await redis_client.set(
         f"crm_lock:{context_id}", "locked", nx=True, ex=180
     )
     if not lock_acquired:
         logger.warning(
             "Concorrência detectada: requisição para contextId %s ignorada pois outra chamada já está em processamento.",
             context_id,
         )
         return {
             "jsonrpc": "2.0",
             "id": request.id,
             "result": {"artifacts": [{"parts": [{"type": "text", "text": ""}]}]},
         }
     ```
   - No bloco `finally`, a chave `crm_lock:{context_id}` é liberada, garantindo que o lock nunca fique preso em caso de erro ou término normal.

2. **Benefício de Concorrência:**
   - Impede que rajadas de mensagens do cliente (ex: "oi", e 3 segundos depois "quais cafés têm?") disparem múltiplos pipelines simultâneos disputando a mesma sessão do Vertex AI (`agentengine://`), evitando colisão de eventos e timeouts em cascata.

---

## 4. Critérios de Aceitação (Gherkin)

### Cenário 1: Reutilização da lista de preços em cache sem novo download no Google Drive
- **Dado** que o agente Anero Café recebeu uma mensagem de atendimento
- **E** o arquivo da lista de preços (`GOOGLE_DRIVE_PF_FILE_ID`) possui `modifiedTime` idêntico ao do cache local
- **Quando** o callback `before_agent` for acionado
- **Então** nenhum download do arquivo no Google Drive deve ser realizado
- **E** a lista de preços mantida em memória deve ser injetada no prompt em menos de 50ms.

### Cenário 2: Download condicional somente quando a lista de preços for alterada no Drive
- **Dado** que a cafeteria alterou valores ou cafés no arquivo da lista de preços no Google Drive
- **Quando** uma nova mensagem de atendimento for recebida
- **Então** o `PriceListSyncService` deve detectar a alteração de `modifiedTime` / hash
- **E** baixar o novo conteúdo, atualizar o cache local e injetar os novos preços no prompt.

### Cenário 3: Resposta de cafés e preços em 1 único turno de LLM sem chamar tool
- **Dado** que o cliente pergunta *"Quais cafés especiais vocês têm e quais os valores?"*
- **Quando** o agente processar a mensagem
- **Então** o modelo deve gerar a resposta completa em um único turno de inferência (`events = [model_turn]`)
- **E** nenhuma chamada para a tool `get_catalog_overview` deve ser executada
- **E** a latência de resposta deve ser inferior a 20 segundos.

### Cenário 4: Preservação da tool de envio de catálogo em PDF (SPEC-021/SPEC-022)
- **Dado** que o cliente pede expressamente *"Me manda o catálogo em PDF"*
- **Quando** o agente processar a mensagem
- **Então** a tool `send_catalog_pdf` deve ser invocada
- **E** a URL do catálogo PDF oficial (arquivo 1) deve ser retornada para entrega do anexo.

### Cenário 5: Habilitação de Context Caching no Google ADK
- **Dado** que o serviço `anero-cafe-support` é inicializado
- **Quando** o container subir no GKE
- **Então** a instância de `App` deve conter `context_cache_config` configurada com `ttl_seconds=1800` e `min_tokens=2048`
- **E** o log não deve apresentar warning de `can transfer between agents but has no context_cache_config`.

### Cenário 6: Bloqueio de concorrência por conversa no backend (Solução C)
- **Dado** que uma mensagem para a conversa `conv-123` está em processamento no pod
- **Quando** uma segunda requisição HTTP para a mesma conversa `conv-123` chegar ao endpoint `/crm/run`
- **Então** o router deve detectar a chave `crm_lock:conv-123` no Redis
- **E** não deve disparar uma segunda execução concorrente na mesma sessão do Vertex AI.

---

## 5. Plano de Rollout e Tarefas

- [ ] **Onda 1 (`paralax-ia/anero-cafe-support`):**
  - Implementar `PriceListSyncService` em `anero_cafe/services/price_list_sync.py` com testes unitários em `tests/unit/test_price_list_sync.py`.
  - Integrar `before_agent` em `anero_cafe/shared_libraries/callbacks.py` para injetar a lista de preços no system prompt.
  - Instanciar `App` com `ContextCacheConfig` em `anero_cafe/agent.py` e exportar em `anero_cafe/__init__.py`.
  - Implementar o Distributed Lock no Redis por `conversation_id` em `anero_cafe/routers/crm.py`.
  - Sincronizar prompts atualizados no Langfuse (`anero_cafe/instruction` e `anero_cafe/atendimento_normal`).
  - Executar suíte de validação (`just verify`).
  - Abrir PR no repositório `anero-cafe-support`.

- [ ] **Onda 2 (`paralax-ia/argocd`):**
  - Adicionar variáveis declarativas de ambiente no manifesto do `anero-cafe-support`:
    - `ENABLE_CONTEXT_CACHE=true`
    - `CONTEXT_CACHE_TTL_SECONDS=1800`
    - `PRICE_LIST_CACHE_TTL_SECONDS=300`
    - `CRM_LOCK_TIMEOUT_SECONDS=180`
  - Abrir PR no repositório `argocd`.
