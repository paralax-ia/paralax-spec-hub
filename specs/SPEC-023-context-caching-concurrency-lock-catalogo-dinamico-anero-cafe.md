---
spec_id: SPEC-023
title: "Context Caching no ADK via paralax.agents.common.app, Injeção Dinâmica da Lista de Preços e Lock de Concorrência no SDK"
product:
  - anero-cafe-support
  - paralax-platform
capability: conversational-ai-agent
scope: multi-repo
bounded_context: "Conversational Agent / Performance, Cache & Concorrência"
origin_module: paralax-spec-hub
target_repositories:
  - repo: paralax-ia/paralax-agents-common
    wave: 1
    role: shared-library
  - repo: paralax-ia/paralax-evo-crm
    wave: 1
    role: sdk
  - repo: paralax-ia/anero-cafe-support
    wave: 2
    role: ai-agent
    prompts:
      - anero_cafe/instruction
      - anero_cafe/atendimento_normal
  - repo: paralax-ia/argocd
    wave: 3
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

# SPEC-023: Context Caching no ADK via paralax.agents.common.app, Injeção Dinâmica da Lista de Preços e Lock de Concorrência no SDK

> **Product:** [`anero-cafe-support`](../products/anero-cafe-support.yaml) | [`paralax-platform`](../products/paralax-platform.yaml)  
> **Business Capability:** [`conversational-ai-agent`](../capabilities/conversational-ai-agent/capability.yaml)  
> **Scope:** Shared Library (`paralax-agents-common`), SDK CRM (`paralax-evo-crm`), Agente de IA (`anero-cafe-support`) e GitOps (`argocd`)  
> **Bounded Context:** Conversational Agent / Performance, Cache & Concorrência  
> **Status:** APPROVED  
> **Autor:** Eduardo F. Santos  
> **Data de Criação:** 2026-11-27  
> **Data de Revisão:** 2026-11-27  
> **Distinção Fundamental de Arquivos do Anero Café:**  
> - **Arquivo 1 - Catálogo PDF (`GOOGLE_DRIVE_CATALOG_PDF_FILE_ID`):** Definido e governado pelas SPECs 021 e 022. É o catálogo visual diagramado em PDF enviado como documento anexo no WhatsApp via ferramenta `send_catalog_pdf` (usando o `GoogleDrivePdfManager`). **Permanece inalterado nesta spec.**  
> - **Arquivo 2 - Lista de Preços e Cafés (`GOOGLE_DRIVE_PF_FILE_ID`):** Arquivo de dados/texto no Google Drive contendo a relação de cafés, características sensoriais, moagens e tabela de preços de varejo. **É o foco da Solução A desta spec.**

---

## 1. Contexto e Objetivos

Durante a investigação de causa raiz (RCA) do incidente com o contato `+55 61 9881-7744` (conversa `909` no CRM), diagnosticou-se que o robô parou de responder devido à conjunção de roundtrips excessivos de LLM, ausência de cache de contexto no Vertex AI e concorrência descontrolada entre mensagens simultâneas.

Esta especificação possui **três objetivos estritos e bem definidos**:

1. **Generalizar e Habilitar o Context Caching no `paralax-agents-common` (Namespace `app`):**
   Criar o módulo `paralax.agents.common.app` na biblioteca compartilhada para prover a fábrica `create_cached_app` e a configuração padronizada de `ContextCacheConfig` com governança 12-Factor, permitindo que o `anero-cafe-support` (e qualquer outro agente da plataforma) instancie seu `App` com Context Caching ativo no Vertex AI em uma única linha declarativa.
2. **Evitar a Chamada de Tool para a Lista de Preços (Solução A):**
   Baixar o arquivo da **lista de preços** (`GOOGLE_DRIVE_PF_FILE_ID`) via callback no início do agente (`before_agent`), utilizando **validação de alteração do arquivo** (`modifiedTime` / `md5Checksum`) no Google Drive para só baixar se houver alteração real, e injetar o texto da lista de preços diretamente no **system prompt**. Com isso, o modelo responde sobre cafés e preços em **1 único turno de LLM**, eliminando a tool call redundante de `get_catalog_overview` (que demorava 136s por turno).
3. **Criar o Lock por Conversa no Backend via Decorator Reutilizável no SDK (Solução C):**
   Implementar um decorator reutilizável `@conversation_lock` no pacote SDK `paralax-evo-crm` (`paralax.evo.crm.lock`). O decorator gerencia a aquisição atômica e liberação de lock distribuído no Redis por `conversation_id` (`crm_lock:{context_id}`), protegendo qualquer endpoint de agente contra colisões decorrentes de múltiplas mensagens em rajada sem poluir o código do agente com boilerplate de Redis.

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
 │      SHARED LIB paralax-agents-common (Namespace app / Objetivo 1)     │
 │   • paralax.agents.common.app.create_cached_app(name, root_agent)      │
 │   • Configura ContextCacheConfig(ttl=1800, min=2048) via 12-Factor     │
 │   • Vertex AI cria CachedContent para o prefixo fixo estável           │
 │   • Redução de TTFT (-70%) e desconto de 75% no custo de tokens        │
 └────────────────────────────────────────────────────────────────────────┘
                                    ▲
                                    │
 ┌────────────────────────────────────────────────────────────────────────┐
 │     SDK paralax-evo-crm: @conversation_lock (Reutilizável / Solução C) │
 │   • Decorator assíncrono: @conversation_lock(ttl_seconds=180)          │
 │   • Adquire crm_lock:{context_id} no Redis de forma não-bloqueante     │
 │   • Rejeita chamadas concorrentes da mesma conversa com retorno seguro │
 │   • Liberação atômica no bloco finally                                 │
 └────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Especificação Técnica dos Três Pilares

### 3.1. Pilar 1: Generalização de Context Caching em `paralax.agents.common.app`
Localização: `paralax/agents/common/app.py` (no repositório `paralax-agents-common`)

Para padronizar e governar o ciclo de vida de aplicações Google ADK em todo o ecossistema Paralax IA, a fábrica de `App` com Context Caching é centralizada no namespace `app`:

1. **Definição de `paralax.agents.common.app`:**
```python
"""App factory and Context Caching governance for Google ADK agents."""

from __future__ import annotations

import logging
import os
from typing import Any

from google.adk.agents.context_cache_config import ContextCacheConfig
from google.adk.apps.app import App
from google.genai.types import HttpOptions

logger = logging.getLogger(__name__)


def get_default_context_cache_config(
    ttl_seconds: int | None = None,
    min_tokens: int | None = None,
    cache_intervals: int | None = None,
    timeout_ms: int = 10000,
) -> ContextCacheConfig | None:
    """Retorna a configuração padrão de Context Caching governada por variáveis de ambiente.

    Args:
        ttl_seconds: TTL opcional em segundos.
        min_tokens: Piso mínimo de tokens para ativar o cache.
        cache_intervals: Quantidade de turnos antes de revalidar o cache.
        timeout_ms: Timeout em milissegundos para a criação do cache no Vertex AI.

    Returns:
        Instância de ContextCacheConfig ou None se desabilitado via ENABLE_CONTEXT_CACHE=false.
    """
    enabled_raw = os.environ.get("ENABLE_CONTEXT_CACHE", "true").strip().lower()
    if enabled_raw not in ("true", "1", "yes", "t"):
        logger.info("Context Caching desabilitado via ENABLE_CONTEXT_CACHE=false.")
        return None

    resolved_ttl = ttl_seconds or int(os.environ.get("CONTEXT_CACHE_TTL_SECONDS", "1800"))
    resolved_min_tokens = min_tokens or int(os.environ.get("CONTEXT_CACHE_MIN_TOKENS", "2048"))
    resolved_intervals = cache_intervals or int(os.environ.get("CONTEXT_CACHE_INTERVALS", "10"))

    return ContextCacheConfig(
        ttl_seconds=resolved_ttl,
        min_tokens=resolved_min_tokens,
        cache_intervals=resolved_intervals,
        create_http_options=HttpOptions(timeout=timeout_ms),
    )


def create_cached_app(
    name: str,
    root_agent: Any,
    plugins: list[Any] | None = None,
    **cache_kwargs: Any,
) -> App:
    """Fábrica para instanciar App do Google ADK com governança centralizada de Context Caching.

    Args:
        name: Nome canônico da aplicação.
        root_agent: Agente raiz (BaseAgent) da aplicação.
        plugins: Lista de plugins compartilhados do ADK.
        **cache_kwargs: Parâmetros opcionais para sobrescrever defaults de cache.

    Returns:
        Instância de App configurada e pronta para execução no Runner.
    """
    cache_config = get_default_context_cache_config(**cache_kwargs)
    return App(
        name=name,
        root_agent=root_agent,
        plugins=plugins or [],
        context_cache_config=cache_config,
    )
```

2. **Consumo no Agente `anero-cafe-support` (`anero_cafe/agent.py` e `anero_cafe/__init__.py`):**
```python
from paralax.agents.common.app import create_cached_app

# Instanciação centralizada com 1 linha
app = create_cached_app(name="anero_cafe", root_agent=root_agent)
```
E no `anero_cafe/__init__.py`:
```python
from .agent import app, root_agent

__all__ = ["app", "root_agent"]
```

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

### 3.3. Pilar 3: Decorator Reutilizável de Lock por Conversa no SDK `paralax-evo-crm` (Solução C)
Localização: `paralax/evo/crm/lock.py` (no repositório `paralax-evo-crm`)

Para evitar duplicação de lógica e garantir que todos os agentes do ecossistema possam se proteger contra rajadas de mensagens, o lock distribuído é encapsulado em um decorator reutilizável no SDK comum.

1. **Definição e Assinatura do Decorator (`paralax.evo.crm.lock`):**
```python
from functools import wraps
import logging
from typing import Any, Callable

logger = logging.getLogger(__name__)


def conversation_lock(
    ttl_seconds: int = 180,
    key_prefix: str = "crm_lock",
) -> Callable[..., Any]:
    """Decorator assíncrono para garantir lock distribuído por conversa no Redis.

    Business Rule: Impede que mensagens simultâneas da mesma conversa (rajadas ou
    mensagens rápidas) executem pipelines concorrentes na mesma sessão do LLM,
    evitando conflito de estado, corrupção de sessão e exaustão de cotas.

    Args:
        ttl_seconds: Tempo de vida do lock no Redis em segundos (safety backstop).
        key_prefix: Prefixo da chave de lock no Redis.

    Returns:
        Função decorada com proteção de concorrência.
    """
    def decorator(func: Callable[..., Any]) -> Callable[..., Any]:
        @wraps(func)
        async def wrapper(*args: Any, **kwargs: Any) -> Any:
            # 1. Extração do context_id e do request a partir de args/kwargs
            request = kwargs.get("request")
            if not request and args:
                for arg in args:
                    if hasattr(arg, "params") and hasattr(arg.params, "context_id"):
                        request = arg
                        break

            context_id = None
            if request and hasattr(request, "params"):
                context_id = getattr(request.params, "context_id", None)

            # 2. Resolução do cliente Redis
            redis_client = kwargs.get("redis_client")
            if not redis_client and hasattr(func, "__self__"):
                redis_client = getattr(func.__self__, "redis_client", None)

            # Se não houver context_id ou redis_client, prossegue sem lock
            if not context_id or not redis_client:
                return await func(*args, **kwargs)

            lock_key = f"{key_prefix}:{context_id}"
            lock_acquired = await redis_client.set(lock_key, "locked", nx=True, ex=ttl_seconds)

            if not lock_acquired:
                logger.warning(
                    "Concorrência detectada: chamada para contextId %s ignorada pois outra requisição já está em processamento.",
                    context_id,
                )
                request_id = getattr(request, "id", None)
                return {
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "result": {"artifacts": [{"parts": [{"type": "text", "text": ""}]}]},
                }

            try:
                return await func(*args, **kwargs)
            finally:
                try:
                    await redis_client.delete(lock_key)
                except Exception as cleanup_err:
                    logger.error("Erro ao liberar lock %s: %s", lock_key, cleanup_err)

        return wrapper
    return decorator
```

2. **Consumo Elegante no Agente (`anero_cafe/routers/crm.py`):**
No agente `anero-cafe-support`, o endpoint simplesmente importa e aplica o decorator:
```python
from paralax.evo.crm.lock import conversation_lock

@router.post("/run")
@conversation_lock(ttl_seconds=180)
async def run_agent(request: CrmRequest):
    ...
```

---

## 4. Critérios de Aceitação (Gherkin)

### Cenário 1: Fábrica `paralax.agents.common.app.create_cached_app` cria App com ContextCacheConfig
- **Dado** que um agente invoca `create_cached_app(name="meu_agente", root_agent=root_agent)`
- **Quando** a variável `ENABLE_CONTEXT_CACHE` for "true" (ou não definida)
- **Então** o objeto `App` retornado deve possuir `context_cache_config` preenchido
- **E** `context_cache_config.ttl_seconds` deve respeitar `CONTEXT_CACHE_TTL_SECONDS` (default: 1800).

### Cenário 2: Reutilização da lista de preços em cache sem novo download no Google Drive
- **Dado** que o agente Anero Café recebeu uma mensagem de atendimento
- **E** o arquivo da lista de preços (`GOOGLE_DRIVE_PF_FILE_ID`) possui `modifiedTime` idêntico ao do cache local
- **Quando** o callback `before_agent` for acionado
- **Então** nenhum download do arquivo no Google Drive deve ser realizado
- **E** a lista de preços mantida em memória deve ser injetada no prompt em menos de 50ms.

### Cenário 3: Download condicional somente quando a lista de preços for alterada no Drive
- **Dado** que a cafeteria alterou valores ou cafés no arquivo da lista de preços no Google Drive
- **Quando** uma nova mensagem de atendimento for recebida
- **Então** o `PriceListSyncService` deve detectar a alteração de `modifiedTime` / hash
- **E** baixar o novo conteúdo, atualizar o cache local e injetar os novos preços no prompt.

### Cenário 4: Resposta de cafés e preços em 1 único turno de LLM sem chamar tool
- **Dado** que o cliente pergunta *"Quais cafés especiais vocês têm e quais os valores?"*
- **Quando** o agente processar a mensagem
- **Então** o modelo deve gerar a resposta completa em um único turno de inferência (`events = [model_turn]`)
- **E** nenhuma chamada para a tool `get_catalog_overview` deve ser executada
- **E** a latência de resposta deve ser inferior a 20 segundos.

### Cenário 5: Preservação da tool de envio de catálogo em PDF (SPEC-021/SPEC-022)
- **Dado** que o cliente pede expressamente *"Me manda o catálogo em PDF"*
- **Quando** o agente processar a mensagem
- **Então** a tool `send_catalog_pdf` deve ser invocada
- **E** a URL do catálogo PDF oficial (arquivo 1) deve ser retornada para entrega do anexo nativo.

### Cenário 6: Bloqueio de concorrência por conversa no backend via decorator (Solução C)
- **Dado** que uma requisição para a conversa `conv-123` está em processamento no pod
- **Quando** uma segunda requisição HTTP para a mesma conversa `conv-123` chegar ao endpoint decorado com `@conversation_lock`
- **Então** o decorator deve detectar o lock ativo no Redis
- **E** retornar resposta segura sem disparar execução simultânea na sessão do Vertex AI.

---

## 5. Plano de Rollout e Decomposição em Ondas Topológicas

- [ ] **Onda 1A (`paralax-ia/paralax-agents-common` - Shared Library):**
  - Implementar o módulo `paralax.agents.common.app` com `create_cached_app` e `get_default_context_cache_config`.
  - Adicionar suíte de testes unitários em `tests/paralax/agents/common/test_app.py`.
  - Publicar release patch via CI/CD no Artifact Registry.

- [ ] **Onda 1B (`paralax-ia/paralax-evo-crm` - SDK):**
  - Implementar o decorator `@conversation_lock` em `paralax/evo/crm/lock.py`.
  - Suíte de testes unitários com TDD em `tests/paralax/evo/crm/test_lock.py` (cobrindo lock adquirido, lock colidido, liberação no finally e fallback em falhas de Redis).
  - Publicar release patch via CI/CD no Artifact Registry.

- [ ] **Onda 2 (`paralax-ia/anero-cafe-support` - Agente de IA):**
  - Atualizar dependências (`paralax-agents-common` e `paralax-evo-crm`) via `uv sync`.
  - Instanciar `App` utilizando `from paralax.agents.common.app import create_cached_app` e exportar em `anero_cafe/__init__.py`.
  - Decorar o router `/crm/run` com `@conversation_lock`.
  - Implementar `PriceListSyncService` em `anero_cafe/services/price_list_sync.py` com testes unitários em `tests/unit/test_price_list_sync.py`.
  - Integrar `before_agent` em `anero_cafe/shared_libraries/callbacks.py` para injetar a lista de preços no system prompt.
  - Sincronizar prompts atualizados no Langfuse (`anero_cafe/instruction` e `anero_cafe/atendimento_normal`).
  - Executar suíte completa de verificação (`just verify`).
  - Abrir PR no repositório `anero-cafe-support`.

- [ ] **Onda 3 (`paralax-ia/argocd` - GitOps):**
  - Adicionar variáveis declarativas de ambiente no manifesto do `anero-cafe-support`:
    - `ENABLE_CONTEXT_CACHE=true`
    - `CONTEXT_CACHE_TTL_SECONDS=1800`
    - `PRICE_LIST_CACHE_TTL_SECONDS=300`
    - `CRM_LOCK_TIMEOUT_SECONDS=180`
  - Abrir PR no repositório `argocd`.
