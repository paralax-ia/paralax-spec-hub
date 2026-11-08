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
status: PROPOSED
---

# SPEC-011: Sincronização Dinâmica e Contínua de Prompts via Langfuse na Biblioteca `paralax-agents-common`

> **Product:** [`paralax-platform`](../products/paralax-platform.yaml)  
> **Business Capability:** [`conversational-ai-agent`](../capabilities/conversational-ai-agent/capability.yaml)  
> **Scope:** Platform  
> **Bounded Context:** Orquestração Conversacional e Resiliência de Agentes de IA (Core Subdomain)  
> **Status:** PROPOSED  
> **Autor:** Eduardo F. Santos & Antigravity  
> **Data de Criação:** 2026-11-08  
> **Repositórios Alvo:**
> - `paralax-ia/paralax-agents-common` (Onda 1 - Base/Shared Library)
> - `paralax-ia/customer-support-vehicles` (Onda 2 - Consumidor Piloto)
> - `paralax-ia/duo-dermato-support` (Onda 3 - Rollout Frotas)
> - `paralax-ia/anero-cafe-support` (Onda 3 - Rollout Frotas)
> - `paralax-ia/paralax-support` (Onda 3 - Rollout Frotas)

---

## 1. Contexto e Motivação

### 1.1. Diagnóstico do Problema
Nos agentes conversacionais do ecossistema Paralax IA (`customer-support-vehicles`, `duo-dermato-support`, `anero-cafe-support`, `paralax-support`), o carregamento do prompt do Langfuse é realizado de forma estática no momento da inicialização do contêiner (`create_root_agent()`):

```python
langfuse_prompt = langfuse_client.get_prompt(prompt_name)
instruction_prompt = langfuse_prompt.compile()
root_agent = Agent(instruction=instruction_prompt, ...) # Congelado em memória
```

Isso gera um acoplamento indesejado:
1. **Invalidação Tardia:** Alterações de prompt realizadas no painel do Langfuse (ex: ajustes em guardrails, novos fluxos de atendimento ou correções de comportamento) **não têm efeito** em pods em execução no GKE.
2. **Dependência de Reinício:** A aplicação de novos prompts exige o reinício manual dos pods (`kubectl rollout restart`) ou o disparo de novo pipeline de CI/CD.

### 1.2. Requisitos Mandatórios
- **Reutilização Global (Onda 1):** A lógica de gestão de prompts dinâmicos deve residir centralmente na biblioteca compartilhada `paralax-agents-common`, disponibilizando componentes de fácil integração para qualquer agente Google ADK.
- **Sincronização Contínua Garantida ("Sempre Sincronizado"):** Uma atualização realizada no Langfuse deve ser deterministicamente propagada para o agente em tempo de execução, combinando revalidação per-turn (pull) com invalidação sob demanda (push/webhook).
- **Zero Latência Adicional:** A resolução de prompt em conversas em andamento não pode adicionar chamadas de rede bloqueantes ao caminho crítico do usuário.
- **Tolerância a Falhas:** Quedas ou oscilações no Langfuse devem cair transparentemente no último prompt válido em memória ou no fallback compilado local (`INSTRUCTION`).

---

## 2. Arquitetura da Solução

Adotaremos a **Estratégia de Sincronização em Dupla Camada (Push + Pull Híbrido)**:

```mermaid
flowchart TD
    subgraph Langfuse Cloud
        UI["Langfuse UI / API"] -->|Publica nova versão| LF_PROMPTS["Prompt: vehicles/vehicle_search_agent_instruction"]
        LF_PROMPTS -.->|Webhook de publicação| WH_EVENT["Event: prompt.updated"]
    end

    subgraph paralax-agents-common [Onda 1: paralax-agents-common]
        DPM["DynamicPromptManager"]
        CACHE["Cache em Memória (Stale-While-Revalidate)"]
        WH_ROUTER["PromptManagementRouter (FastAPI)"]
        
        DPM <--> CACHE
        WH_ROUTER -->|refresh(force=True)| DPM
    end

    subgraph customer-support-vehicles [Onda 2: Consumidor Piloto]
        MSG["Mensagem do Usuário"] --> CRM_ROUTER["Router CRM (/run)"]
        CRM_ROUTER --> RUNNER["Google ADK Runner"]
        RUNNER --> AGENT["Google ADK Agent"]
        
        AGENT -->|instruction=prompt_manager.get_instruction (Callable)| DPM
        
        DPM -->|1. Retorna prompt em cache| AGENT
        DPM -.->|2. Se expirado: revalidação em background| LF_PROMPTS
        
        WH_EVENT -.->|Push imediato| WH_ROUTER
        ADMIN["POST /prompts/refresh"] -->|Invalidação manual| WH_ROUTER
    end
```

### 2.1. Camada Pull (Per-Turn Dynamic Instruction)
O Google ADK suporta nativamente instruções dinâmicas através da assinatura:
```python
instruction: Union[str, Callable[[ReadonlyContext], Union[str, Awaitable[str]]]]
```
Em cada turno/mensagem processada pelo `Runner`, o ADK invoca `canonical_instruction(ctx)`, que chama `dynamic_prompt_manager.get_instruction(ctx)`.

### 2.2. Stale-While-Revalidate com Cache TTL
O `DynamicPromptManager` delega para o SDK do Langfuse com `cache_ttl_seconds` configurável (padrão: 120s):
- Se o cache está válido: retorno imediato em memória (~0.05ms).
- Se o cache expirou: o SDK entrega a versão em memória instantaneamente e dispara thread em background para buscar a nova versão.
- Falha de rede: mantém a versão ativa sem interromper a sessão do usuário.

### 2.3. Camada Push (Invalidação Imediata via API/Webhook)
O módulo `paralax.agents.common.routers` exporta uma factory de router FastAPI:
- **`POST /prompts/refresh`**: Invalida o cache local (`clear_prompt_cache()`) e sincroniza imediatamente com o Langfuse. Protegido via `X-Agent-Api-Key` ou Bearer Token.
- **`GET /prompts/status`**: Retorna telemetria da versão ativa, origem (`remote`/`fallback`), labels e timestamp da última sincronização.

---

## 3. Contratos e Interfaces da Biblioteca

### 3.1. `paralax.agents.common.prompts.DynamicPromptManager`
```python
class DynamicPromptManager:
    """Gerenciador de prompts dinâmicos com cache e fallback para o Google ADK."""

    def __init__(
        self,
        prompt_name: str,
        fallback_instruction: str,
        langfuse_client: Optional[Langfuse] = None,
        cache_ttl_seconds: int = 120,
        label: str = "production",
    ) -> None:
        ...

    def get_instruction(self, ctx: Any = None) -> str:
        """Retorna o texto de instrução resolvido, com fallback resiliente."""
        ...

    def refresh(self, force: bool = True) -> dict[str, Any]:
        """Força limpeza de cache e recarregamento síncrono da versão mais recente."""
        ...

    def get_status(self) -> dict[str, Any]:
        """Retorna telemetria sobre a versão e estado do prompt."""
        ...
```

### 3.2. `paralax.agents.common.routers.create_prompt_management_router`
```python
def create_prompt_management_router(
    prompt_manager: DynamicPromptManager,
    expected_api_key: Optional[str] = None,
) -> APIRouter:
    """Cria router FastAPI com endpoints /prompts/refresh e /prompts/status."""
    ...
```

---

## 4. Plano de Execução em Ondas Topológicas

### 🌊 Onda 1: Shared Library (`paralax-ia/paralax-agents-common`)
- **Meta:** Implementar `DynamicPromptManager` e `create_prompt_management_router` com 100% de cobertura de testes e publicar nova versão no Artifact Registry.
- **Tarefas:**
  1. Criar branch `feat/dynamic-prompt-manager` a partir de `main`.
  2. Implementar `paralax/agents/common/prompts.py`.
  3. Implementar `paralax/agents/common/routers.py`.
  4. Expor novos módulos em `paralax/agents/common/__init__.py`.
  5. Criar suíte de testes unitários `tests/unit/test_dynamic_prompt_manager.py`:
     - Resolução dinâmica e fallback quando Langfuse é None.
     - Resolução com mock de Langfuse (`get_prompt` com label `production`).
     - Expiração de TTL e comportamento de revalidação.
     - Comportamento de `refresh(force=True)`.
     - Endpoints `/prompts/refresh` e `/prompts/status` com e sem autenticação de API Key.
  6. Validar com `make test` e `make lint`.
  7. Abrir PR via GitHub CLI (`gh pr create`).
  8. Gerar release de patch (`make release patch`) -> Publicar `0.0.17` no `prod-python-registry`.

---

### 🌊 Onda 2: Consumidor Piloto (`paralax-ia/customer-support-vehicles`)
- **Meta:** Adotar a versão `0.0.17` da lib, plugar a instrução dinâmica e expor os endpoints de atualização no agente de veículos.
- **Tarefas:**
  1. Criar branch `feat/dynamic-prompt-sync` a partir de `main`.
  2. Atualizar `pyproject.toml` para `paralax-agents-common>=0.0.17` e sincronizar `uv.lock`.
  3. Adicionar em `vehicles/config.py`:
     - `LANGFUSE_PROMPT_CACHE_TTL_SECONDS: int = Field(default=120, ...)`
     - `LANGFUSE_PROMPT_LABEL: str = Field(default="production", ...)`
  4. Refatorar `vehicles/agent.py`:
     - Instanciar `DynamicPromptManager` com `prompt_name="vehicles/vehicle_search_agent_instruction"` e `fallback_instruction=INSTRUCTION`.
     - Conectar `instruction=prompt_manager.get_instruction` no `Agent(...)`.
  5. Acoplar o router em `vehicles/routers/crm.py` ou `vehicles/main.py`:
     - `app.include_router(create_prompt_management_router(prompt_manager, config.AGENT_API_KEY))`.
  6. Criar testes unitários em `tests/unit/test_dynamic_prompt_integration.py`:
     - Testar que `root_agent.instruction` é um callable que resolve para a versão ativa.
     - Testar endpoint `POST /prompts/refresh` atualizando o prompt em memória.
  7. Validar com `uv run pytest tests/unit`.
  8. Abrir PR via GitHub CLI (`gh pr create`).

---

### 🌊 Onda 3: Rollout nos Demais Agentes da Frota
- **Meta:** Estender a padronização para os outros 3 agentes conversacionais.
- **Tarefas:**
  1. **`duo-dermato-support`:** Atualizar para `paralax-agents-common>=0.0.17`, plugar `DynamicPromptManager` para `duo_dermato/support`.
  2. **`anero-cafe-support`:** Atualizar para `paralax-agents-common>=0.0.17`, plugar `DynamicPromptManager` para `anero_cafe/instruction`.
  3. **`paralax-support`:** Atualizar para `paralax-agents-common>=0.0.17`, plugar `DynamicPromptManager` para `paralax/support`.
  4. Abrir PRs e validar integração contínua.

---

## 5. Critérios de Aceite e Invariantes de Qualidade

1. **Invariante de Não-Interrupção:** Nenhuma falha de rede do Langfuse pode resultar em HTTP 500 para a mensagem do usuário; o agente deve sempre recorrer ao fallback com log de warning.
2. **Invariante de Sincronização Dinâmica:** Após publicação de nova versão do prompt com label `production` no Langfuse:
   - Uma chamada a `POST /prompts/refresh` deve atualizar a instrução na próxima requisição do usuário com 0 segundos de delay.
   - Mesmo sem chamada ao endpoint de refresh, a nova versão deve passar a ser servida automaticamente assim que o `cache_ttl_seconds` expirar.
3. **Compatibilidade com Ondas Topológicas:** Nenhuma alteração no agente consome pacotes via path local ou symlink; o consumo é estritamente via wheel oficial publicada.
4. **Governança de Código:** PEP 8 estrito, Google docstrings, sem funções aninhadas, sem try-except aninhados, isort e tipagem estrita via `pyright`/`mypy`.
