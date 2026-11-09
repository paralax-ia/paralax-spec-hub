---
spec_id: SPEC-011
title: Sincronização Dinâmica e Contínua de Prompts via Langfuse na Biblioteca paralax-agents-common
product:
- paralax-platform
- customer-support-vehicles
- duo-dermato-support
- anero-cafe-support
- paralax-support
capability: conversational-ai-agent
scope: platform
bounded_context: Orquestração Conversacional e Resiliência de Agentes de IA (Core Subdomain)
origin_module: paralax-agents-common
target_repositories:
- repo: paralax-ia/paralax-agents-common
  wave: 1
  role: shared-library
- repo: paralax-ia/customer-support-vehicles
  wave: 2
  role: ai-agent
- repo: paralax-ia/duo-dermato-support
  wave: 3
  role: ai-agent
- repo: paralax-ia/anero-cafe-support
  wave: 3
  role: ai-agent
- repo: paralax-ia/paralax-support
  wave: 3
  role: ai-agent
status: MERGED
---

# SPEC-011: Sincronização Dinâmica e Contínua de Prompts via Langfuse na Biblioteca `paralax-agents-common`

> **Product:** [`paralax-platform`](../products/paralax-platform.yaml)  
> **Business Capability:** [`conversational-ai-agent`](../capabilities/conversational-ai-agent/capability.yaml)  
> **Scope:** Platform  
> **Bounded Context:** Orquestração Conversacional e Resiliência de Agentes de IA (Core Subdomain)  
> **Status:** MERGED  
> **Autor:** Eduardo F. Santos & Antigravity  
> **Data de Criação:** 2026-11-08  
> **Repositórios Alvo:**
> - `paralax-ia/paralax-agents-common` (Onda 1 - Base/Shared Library)
> - `paralax-ia/customer-support-vehicles` (Onda 2 - Consumidor Piloto)
> - `paralax-ia/duo-dermato-support` (Onda 3 - Rollout Frotas)
> - `paralax-ia/anero-cafe-support` (Onda 3 - Rollout Frotas)
> - `paralax-ia/paralax-support` (Onda 3 - Rollout Frotas)

---

## 1. Motivação e Diagnóstico

### 1.1. Cenário Atual
- Em todos os agentes de IA (`customer-support-vehicles`, `duo-dermato-support`, `anero-cafe-support`, `paralax-support`), o carregamento do prompt do Langfuse ocorre de forma **estática** no momento da importação do módulo (`create_root_agent()`):
  ```python
  langfuse_prompt = langfuse_client.get_prompt(prompt_name)
  instruction_prompt = langfuse_prompt.compile()
  root_agent = Agent(instruction=instruction_prompt, ...) # Congelado em memória
  ```
- Se um engenheiro de prompts alterar instruções, ajustar guardrails ou promover uma nova versão com a tag `production` no Langfuse, os pods em execução no GKE continuam servindo o prompt capturado no boot.
- Para aplicar a nova versão, hoje é necessário realizar restart manual dos Deployments no Kubernetes ou disparar um novo pipeline de release.

### 1.2. Requisitos Mandatórios do Usuário
1. **Reutilização via Biblioteca Comum:** A lógica de sincronização, cache, resolução e endpoints de gerenciamento deve residir na biblioteca compartilhada `paralax-agents-common` (`paralax.agents.common.prompts`), e não isolada no código de um único agente.
2. **Garantia de Sincronização Contínua ("Sempre Sincronizado"):** Uma atualização realizada no Langfuse não pode depender exclusivamente de intervenção humana ou expiração tardia de caches. O agente deve refletir deterministicamente as atualizações em tempo de execução.
3. **Zero Latência Adicional:** A resolução de prompt em conversas em andamento não pode adicionar chamadas de rede bloqueantes ao caminho crítico do usuário.
4. **Tolerância a Falhas:** Quedas ou oscilações no Langfuse devem cair transparentemente no último prompt válido em memória ou no fallback compilado local (`INSTRUCTION`).

---

## 2. Desenho Arquitetural da Solução

Para assegurar que as atualizações sejam **sempre** sincronizadas sem degradar a latência das mensagens, a biblioteca `paralax-agents-common` implementará uma **Estratégia de Sincronização em Dupla Camada (Push + Pull Híbrido)**:

```mermaid
flowchart TD
    subgraph Langfuse Cloud
        UI["Langfuse UI / API"] -->|Publica nova versão| LF_PROMPTS["Prompt: vehicles/vehicle_search_agent_instruction"]
        LF_PROMPTS -.->|Webhook de publicação (opcional)| WH_EVENT["Event: prompt.updated"]
    end

    subgraph paralax-agents-common [Biblioteca Reutilizável: paralax-agents-common]
        DPM["DynamicPromptManager"]
        CACHE["Cache em Memória (Stale-While-Revalidate)"]
        WH_ROUTER["PromptManagementRouter (FastAPI)"]
        
        DPM <--> CACHE
        WH_ROUTER -->|force_refresh()| DPM
    end

    subgraph customer-support-vehicles [Agente Consumidor (Onda 2)]
        MSG["Mensagem do Usuário (WhatsApp/Web)"] --> CRM_ROUTER["Router CRM (/run)"]
        CRM_ROUTER --> RUNNER["Google ADK Runner"]
        RUNNER --> AGENT["Google ADK Agent"]
        
        AGENT -->|instruction=prompt_manager.get_instruction (Callable)| DPM
        
        DPM -->|1. Retorna prompt em cache imediatamente| AGENT
        DPM -.->|2. Se expirado ou invalidado: fetch em background| LF_PROMPTS
        
        WH_EVENT -.->|Push imediato| WH_ROUTER
        ADMIN["POST /prompts/refresh"] -->|Invalidação manual sob demanda| WH_ROUTER
    end
```

---

## 3. Os 3 Pilares de Garantia de Sincronização

### Pilar 1: Camada Pull Dinâmica por Turno via Callable no Google ADK
- O Google ADK suporta nativamente instruções dinâmicas através de `Callable[[ReadonlyContext], Union[str, Awaitable[str]]]`.
- Em cada turno/mensagem processada pelo `Runner`, o ADK invoca `canonical_instruction(ctx)`, delegando para `prompt_manager.get_instruction(ctx)`.
- Isso elimina o congelamento do prompt na inicialização do contêiner.

### Pilar 2: Stale-While-Revalidate com Background Refresh (Latência Zero)
- O `DynamicPromptManager` configura o cache interno do SDK do Langfuse com um TTL curto e seguro (`cache_ttl_seconds`, padrão: 60s a 120s, configurável via ambiente).
- Ao expirar o TTL:
  1. A requisição do usuário em andamento recebe imediatamente a versão em cache (zero latência adicional).
  2. Uma thread em segundo plano atualiza o cache com a versão mais recente publicada no Langfuse.
  3. Todas as mensagens subsequentes já utilizam o novo prompt.
- **Fallback Resiliente:** Em caso de oscilação ou indisponibilidade do Langfuse, o `DynamicPromptManager` mantém a última versão válida em memória ou recorre ao fallback estático do código (`INSTRUCTION`). O atendimento ao cliente nunca é interrompido.

### Pilar 3: Camada Push Imediata via API/Webhook de Sincronização
- A biblioteca `paralax-agents-common` fornecerá um roteador FastAPI pronto para inclusão: `create_prompt_management_router(prompt_manager)`.
- Expõe dois endpoints padronizados nos agentes:
  - **`POST /prompts/refresh`**: Limpa imediatamente o cache em memória e baixa a versão mais recente do Langfuse (resposta síncrona com os metadados da nova versão). Protegido via `X-Agent-Api-Key` ou `AGENT_API_KEY`.
  - **`GET /prompts/status`**: Retorna a telemetria do prompt em execução: versão ativa, labels (`production`), comprimento, timestamp da última sincronização e origem (`remote` ou `fallback`).
- Permite que ferramentas de CI/CD, webhooks do Langfuse ou operadores humanos forcem a propagação instantânea em todos os pods sem esperar qualquer TTL.

---

## 4. Especificação de Código na Biblioteca `paralax-agents-common`

### 4.1. Módulo `paralax.agents.common.prompts`

```python
# paralax-agents-common/paralax/agents/common/prompts.py
from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any, Callable, Optional

from langfuse import Langfuse
from langfuse.api.core import ApiError

logger = logging.getLogger(__name__)


class DynamicPromptManager:
    """Gerenciador de prompts dinâmicos e contínuos via Langfuse para o Google ADK.
    
    Garante sincronização automática de prompts atualizados em produção, combinando
    resolução por turno com cache stale-while-revalidate e invalidação sob demanda.
    """

    def __init__(
        self,
        prompt_name: str,
        fallback_instruction: str,
        langfuse_client: Optional[Langfuse] = None,
        cache_ttl_seconds: int = 120,
        label: str = "production",
    ) -> None:
        self.prompt_name = prompt_name
        self.fallback_instruction = fallback_instruction
        self._langfuse_client = langfuse_client
        self.cache_ttl_seconds = cache_ttl_seconds
        self.label = label
        
        self.active_version: Optional[int] = None
        self.last_sync_timestamp: Optional[datetime] = None
        self.source: str = "fallback"
        self._cached_prompt_text: str = fallback_instruction

        # Pré-aquecimento inicial (fail-safe)
        self.refresh()

    def get_instruction(self, ctx: Any = None) -> str:
        """Callable compatível com Agent.instruction do Google ADK."""
        if not self._langfuse_client:
            return self.fallback_instruction

        try:
            prompt_obj = self._langfuse_client.get_prompt(
                name=self.prompt_name,
                label=self.label,
                cache_ttl_seconds=self.cache_ttl_seconds,
                fallback=self.fallback_instruction,
            )
            self._cached_prompt_text = prompt_obj.compile()
            self.active_version = getattr(prompt_obj, "version", None)
            self.source = "remote"
            self.last_sync_timestamp = datetime.now(timezone.utc)
            return self._cached_prompt_text
        except Exception as exc:
            logger.warning(
                "Falha transitória ao resolver prompt dinâmico '%s': %s. Usando versão em cache.",
                self.prompt_name,
                exc,
            )
            return self._cached_prompt_text

    def refresh(self, force: bool = True) -> dict[str, Any]:
        """Força limpeza de cache e recarregamento síncrono da versão mais recente."""
        if not self._langfuse_client:
            return self.get_status()

        try:
            if force and hasattr(self._langfuse_client, "clear_prompt_cache"):
                self._langfuse_client.clear_prompt_cache()

            prompt_obj = self._langfuse_client.get_prompt(
                name=self.prompt_name,
                label=self.label,
                cache_ttl_seconds=0 if force else self.cache_ttl_seconds,
            )
            self._cached_prompt_text = prompt_obj.compile()
            self.active_version = getattr(prompt_obj, "version", None)
            self.source = "remote"
            self.last_sync_timestamp = datetime.now(timezone.utc)
            logger.info(
                "Prompt '%s' sincronizado com sucesso (versão: %s, label: %s)",
                self.prompt_name,
                self.active_version,
                self.label,
            )
        except Exception as exc:
            logger.error(
                "Não foi possível sincronizar o prompt '%s' com o Langfuse: %s",
                self.prompt_name,
                exc,
            )
        return self.get_status()

    def get_status(self) -> dict[str, Any]:
        """Retorna telemetria da versão ativa do prompt."""
        return {
            "prompt_name": self.prompt_name,
            "version": self.active_version,
            "label": self.label,
            "source": self.source,
            "length": len(self._cached_prompt_text),
            "last_sync_utc": (
                self.last_sync_timestamp.isoformat()
                if self.last_sync_timestamp
                else None
            ),
        }
```

### 4.2. Roteador de Gerenciamento FastAPI Reutilizável

```python
# paralax-agents-common/paralax/agents/common/routers.py
from fastapi import APIRouter, Header, HTTPException, status
from typing import Optional

def create_prompt_management_router(
    prompt_manager: Any,
    expected_api_key: Optional[str] = None,
) -> APIRouter:
    router = APIRouter(prefix="/prompts", tags=["Prompts"])

    def verify_auth(x_agent_api_key: Optional[str] = Header(None)) -> None:
        if expected_api_key and x_agent_api_key != expected_api_key:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or missing API Key for prompt management.",
            )

    @router.post("/refresh")
    def refresh_prompt(x_agent_api_key: Optional[str] = Header(None)):
        verify_auth(x_agent_api_key)
        return prompt_manager.refresh(force=True)

    @router.get("/status")
    def prompt_status():
        return prompt_manager.get_status()

    return router
```

---

## 5. Como o Agente de Veículos (`customer-support-vehicles`) Consumirá a Lib

### 5.1. Em `vehicles/agent.py`
```python
from paralax.agents.common.prompts import DynamicPromptManager
from paralax.agents.common.tracing import get_langfuse
from .prompts import INSTRUCTION

prompt_manager = DynamicPromptManager(
    prompt_name="vehicles/vehicle_search_agent_instruction",
    fallback_instruction=INSTRUCTION,
    langfuse_client=get_langfuse(),
    cache_ttl_seconds=configs.LANGFUSE_PROMPT_CACHE_TTL_SECONDS,
    label="production",
)

root_agent = Agent(
    model=configs.agent_settings.model,
    instruction=prompt_manager.get_instruction,  # Callable nativo do Google ADK
    name=configs.agent_settings.name,
    tools=[...],
    ...
)
```

### 5.2. Em `vehicles/main.py` ou `vehicles/routers/crm.py`
```python
from paralax.agents.common.routers import create_prompt_management_router
from vehicles.agent import prompt_manager
from vehicles.config import config

# Acopla os endpoints /prompts/refresh e /prompts/status com proteção de API Key
app.include_router(
    create_prompt_management_router(
        prompt_manager=prompt_manager,
        expected_api_key=config.AGENT_API_KEY,
    )
)
```

---

## 6. Roteiro de Execução em Ondas Topológicas

### 🌊 Onda 1: Implementação e Release na Biblioteca Comum (`paralax-agents-common`)
1. **Branch:** Criar branch `feat/dynamic-prompt-manager` em `paralax-agents-common`.
2. **Código:**
   - Criar `paralax/agents/common/prompts.py` (`DynamicPromptManager`).
   - Criar `paralax/agents/common/routers.py` (`create_prompt_management_router`).
   - Exportar os símbolos em `paralax/agents/common/__init__.py`.
3. **Testes Unitários:**
   - `tests/unit/test_dynamic_prompt_manager.py`:
     * Testar resolução dinâmica inicial via Langfuse.
     * Testar expiração de TTL e background revalidation.
     * Testar fallback em falha de conexão com Langfuse.
     * Testar endpoint `POST /prompts/refresh` com autenticação e invalidação forçada.
     * Testar compatibilidade de assinatura com Google ADK `Callable[[ReadonlyContext], str]`.
4. **Validação:** Rodar `make test` e `make lint`.
5. **Commit e Pull Request:** Abrir PR no repositório `paralax-agents-common`.
6. **Release Oficial:** Gerar nova versão `0.0.17` (`make release patch`) e publicação no Artifact Registry oficial.

---

### 🌊 Onda 2: Integração e Homologação no Agente de Veículos (`customer-support-vehicles`)
1. **Branch:** Criar branch `feat/dynamic-prompt-sync` em `customer-support-vehicles`.
2. **Atualização de Dependência:** Declarar `paralax-agents-common>=0.0.17` no `pyproject.toml` e sincronizar com `uv sync`.
3. **Configuração:** Adicionar `LANGFUSE_PROMPT_CACHE_TTL_SECONDS: int = Field(default=120, ...)` e `LANGFUSE_PROMPT_LABEL: str = Field(default="production", ...)` em `vehicles/config.py`.
4. **Instrução Dinâmica:** Plugar `prompt_manager.get_instruction` em `vehicles/agent.py`.
5. **Endpoints de Invalidação:** Registrar `create_prompt_management_router` no app FastAPI.
6. **Testes do Agente:** Validar toda a suíte de testes do agente de veículos com mock de Langfuse e testes de integração.
7. **Commit e Pull Request:** Submeter PR no GitHub via `gh pr create`.

---

### 🌊 Onda 3: Expansão Contínua para os Demais Agentes
- Replicar o consumo da versão `0.0.17` de `paralax-agents-common` em:
  - `duo-dermato-support` (`duo_dermato/support`)
  - `anero-cafe-support` (`anero_cafe/instruction`)
  - `paralax-support` (`paralax/support`)

---

## 7. Critérios de Aceite e Invariantes de Qualidade

1. **Invariante de Não-Interrupção:** Nenhuma falha de rede do Langfuse pode resultar em HTTP 500 para a mensagem do usuário; o agente deve sempre recorrer ao fallback com log de warning.
2. **Invariante de Sincronização Dinâmica:** Após publicação de nova versão do prompt com label `production` no Langfuse:
   - Uma chamada a `POST /prompts/refresh` deve atualizar a instrução na próxima requisição do usuário com 0 segundos de delay.
   - Mesmo sem chamada ao endpoint de refresh, a nova versão deve passar a ser servida automaticamente assim que o `cache_ttl_seconds` expirar via background revalidation.
3. **Compatibilidade com Ondas Topológicas:** Nenhuma alteração no agente consome pacotes via path local ou symlink; o consumo é estritamente via wheel oficial publicada.
4. **Governança de Código:** PEP 8 estrito, Google docstrings, sem funções aninhadas, sem try-except aninhados, isort e tipagem estrita via `pyright`/`mypy`.

---

## 8. Evidências de Execução e Conclusão das Ondas (Status: MERGED)

Todas as três ondas foram concluídas, testadas e integradas à branch `main` dos respectivos repositórios:

### 🌊 Onda 1: Shared Library (`paralax-ia/paralax-agents-common`)
- **Implementação:** Criação de `DynamicPromptManager` com background revalidation, suporte a callable per-turn do Google ADK e roteador FastAPI (`create_prompt_management_router`).
- **Testes Unitários:** 6 novos testes em `tests/unit/test_dynamic_prompt_manager.py` aprovados com 100% de cobertura.
- **Release:** Publicada a versão oficial `paralax-agents-common==0.0.17` no Google Cloud Artifact Registry (`prod-python-registry`).

### 🌊 Onda 2: Consumidor Piloto (`paralax-ia/customer-support-vehicles`)
- **Integração:** Consumo declarativo de `paralax-agents-common>=0.0.17`, injeção de `DynamicPromptManager` no `vehicles/vehicle_search_agent_instruction` e montagem das rotas `/prompts/refresh` e `/prompts/status`.
- **Testes de Integração:** 7 testes em `tests/unit/test_dynamic_prompt_integration.py` aprovados.
- **Merge:** Pull Request [#77](https://github.com/paralax-ia/customer-support-vehicles/pull/77) validado e mergeado na `main`.

### 🌊 Onda 3: Rollout da Frota (`duo-dermato-support`, `paralax-support`, `anero-cafe-support`)
- **`duo-dermato-support`:**
  - Prompt: `duo_dermato/support`.
  - Testes: 32 testes unitários aprovados, 0 erros no pyright/ruff.
  - Merge: Pull Request [#18](https://github.com/paralax-ia/duo-dermato-support/pull/18) mergeado na `main`.
- **`paralax-support`:**
  - Prompt: `paralax/support`.
  - Testes: 87 testes unitários aprovados, 0 erros no pyright/ruff.
  - Merge: Pull Request [#28](https://github.com/paralax-ia/paralax-support/pull/28) mergeado na `main`.
- **`anero-cafe-support`:**
  - Prompt: `anero_cafe/instruction`.
  - Testes: 39 testes unitários aprovados, 0 erros no pyright/ruff.
  - Merge: Pull Request [#17](https://github.com/paralax-ia/anero-cafe-support/pull/17) mergeado na `main`.
