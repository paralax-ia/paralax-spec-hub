---
spec_id: SPEC-005
title: "Organização da Base de Contatos via Cards de Prospectos Sem Alteração no CRM Core"
product:
  - paralax-platform
  - paralax-support
  - anero-cafe-support
  - customer-support-vehicles
capability: customer-relationship-management
scope: platform
bounded_context: "CRM (Supporting Subdomain)"
origin_module: paralax-evo-crm
target_repositories:
  - repo: paralax-ia/paralax-evo-crm
    wave: 1
    role: sdk
  - repo: paralax-ia/paralax-support
    wave: 2
    role: ai-agent
  - repo: paralax-ia/anero-cafe-support
    wave: 2
    role: ai-agent
  - repo: paralax-ia/customer-support-vehicles
    wave: 2
    role: ai-agent
status: DRAFT
---

# SPEC-005: Organização da Base de Contatos via Cards de Prospectos Sem Alteração no CRM Core

> **Product:** [`paralax-platform`](../products/paralax-platform.yaml) | [`paralax-support`](../products/paralax-support.yaml) | [`anero-cafe-support`](../products/anero-cafe-support.yaml) | [`customer-support-vehicles`](../products/customer-support-vehicles.yaml)  
> **Business Capability:** [`customer-relationship-management`](../capabilities/customer-relationship-management/capability.yaml)  
> **Scope:** Platform (Opt-in por Agente)  
> **Bounded Context:** CRM (Supporting Subdomain)  
> **Status:** DRAFT  
> **Autor:** Eduardo F. Santos  
> **Data de Criação:** 2026-10-19  
> **Arquitetura 12-Factor:** Zero arquivos de configuração salvos no Git; toda configuração é gerada exclusivamente a partir de variáveis de ambiente  
> **Repositórios Impactados:**  
> - `paralax-ia/paralax-evo-crm` (Onda 1 - SDK de Integração, Modelos de Card de Prospecto, Extrator LLM Reutilizável e Callback Opt-in)  
> - `paralax-ia/paralax-support` (Onda 2 - Ativação e Integração do Card de Prospecto no Agente Paralax)  
> - `paralax-ia/anero-cafe-support` (Onda 2 - Ativação e Integração do Card de Prospecto no Agente Anero Café)  
> - `paralax-ia/customer-support-vehicles` (Onda 2 - Ativação e Integração do Card de Prospecto no Agente Vehicles)  
> - *(Sem alterações em `paralax-ia/evo-ai-crm-community`)*

---

## 1. Contexto e Motivação

A operação comercial e de atendimento precisa organizar de forma estruturada a base de contatos recebidos pelos canais digitais (WhatsApp / Meta Ads / Site), **sem realizar qualquer modificação no código-fonte do backend do CRM (`evo-ai-crm-community`)**.

A partir de cada contato recebido pelos agentes da plataforma que optarem por utilizar esta capacidade, deve ser criado e mantido automaticamente um **card estruturado de prospecto** (utilizando a infraestrutura de cards de pipeline e metadados já existente na API REST do CRM via SDK `paralax-evo-crm`), consolidando as informações perenes essenciais para identificação e acompanhamento do ciclo de vida do contato:

1. **Nome do prospecto (`prospect_name`):** Identificação nominal do contato, contemplando que o prospecto pode evoluir e se tornar um cliente ativo no futuro (`lifecycle_stage: "prospect" | "customer"`).
2. **Telefone (`phone`):** Número de telefone de contato padronizado (ex: formato internacional E.164 ou identificador do canal).
3. **Dúvida ou demanda inicial (`initial_demand`):** Síntese clara da dúvida, dor ou solicitação apresentada logo no início do contato.
4. **Interesse identificado (`identified_interest`):** Produto, serviço, solução ou item de catálogo em que foi identificado interesse durante a interação.

### Decisões Arquiteturais e de Domínio Obrigatórias
- **Ausência de Classificação Estática Frio/Quente na Base de Contatos:** Um contato **não deve** ser classificado como `"frio"` ou `"quente"` no card da base de contatos. O estado de temperatura é efêmero e restrito ao momento específico de uma interação, mudando naturalmente ao longo do tempo. Portanto, o card de organização da base de contatos armazena apenas os atributos estruturais e de contexto comercial do prospecto (`prospect_name`, `phone`, `initial_demand`, `identified_interest` e `lifecycle_stage`), sem qualquer campo ou enum de temperatura (`lead_temperature`).
- **Adoção Modular Opt-in pelos Agentes ("Agentes que Assim Desejarem"):** A funcionalidade deve ser disponibilizada de forma reutilizável no SDK `paralax-evo-crm` e habilitada individualmente apenas nos agentes que desejarem utilizá-la (controlada via variáveis de ambiente de ativação). Neste momento, os agentes contemplados na Onda 2 são:
  1. **Paralax (`paralax-ia/paralax-support`)**
  2. **Anero Café (`paralax-ia/anero-cafe-support`)**
  3. **Vehicles (`paralax-ia/customer-support-vehicles`)**
- **Zero Alteração no Código do CRM (`evo-ai-crm-community`):** Toda a inteligência de estruturação, enriquecimento e persistência do card ocorre exclusivamente na camada de SDK (`paralax-evo-crm`) e nos agentes consumidores opt-in, consumindo os endpoints REST nativos de pipelines/cards (`custom_fields` e `notes`) já disponíveis no CRM.
- **Inteligência 100% via LLM:** A extração do nome do prospecto, telefone, dúvida/demanda inicial e interesse identificado deve ser realizada pelo LLM com saída estruturada (Pydantic), sem depender de expressões regulares rígidas ou listas de palavras-chave hardcoded.
- **Princípio 12-Factor (Zero Config no Git):** Nenhuma configuração estática (`.env`, `.yaml`, `.json`) deve ser versionada no Git; toda parametrização é resolvida exclusivamente via variáveis de ambiente (`os.environ`).

---

## 2. Escopo e Repositórios Afetados

```
┌────────────────────────────────────────────────────────────────────┐
│                     ONDA 1 (PENDENTE - TASK-1)                     │
│                   paralax-ia/paralax-evo-crm                       │
│  • Modelos Pydantic: `ProspectContactCard`, `ProspectCardExtraction`│
│    e `ContactLifecycleStage` ("prospect" | "customer")             │
│    (SEM classificação estática de lead frio/quente)                │
│  • Método `upsert_prospect_contact_card` em `CRMAPIClient`         │
│  • Extrator LLM compartilhado `extract_prospect_card_with_llm` e   │
│    orquestrador opt-in `sync_prospect_contact_card` em             │
│    `paralax/evo/crm/callbacks.py`                                  │
│  • Suíte de testes unitários em `tests/unit/`                      │
└──────────────┬──────────────────┬──────────────────┬───────────────┘
               │                  │                  │
               ▼                  ▼                  ▼
┌──────────────────────┐ ┌──────────────────┐ ┌──────────────────────┐
│  ONDA 2 (TASK-2)     │ │  ONDA 2 (TASK-3) │ │  ONDA 2 (TASK-4)     │
│  paralax-support     │ │anero-cafe-support│ │customer-support-     │
│  (Agente Paralax)    │ │(Agente AneroCafé)│ │vehicles (Vehicles)   │
│  • Opt-in via env    │ │  • Opt-in via env│ │  • Opt-in via env    │
│  • Callback pós-     │ │  • Callback pós- │ │  • Callback pós-     │
│    conversa criando/ │ │    conversa      │ │    conversa criando/ │
│    atualizando card  │ │    criando card  │ │    atualizando card  │
│  • Testes unitários  │ │  • Testes unit.  │ │  • Testes unitários  │
└──────────────────────┘ └──────────────────┘ └──────────────────────┘
```

- [ ] **[Onda 1] `paralax-ia/paralax-evo-crm` (`task-1`):**
  - Definir o tipo literal `ContactLifecycleStage` (`"prospect"`, `"customer"`).
  - Implementar os modelos Pydantic `ProspectContactCard` e `ProspectCardExtraction` em `paralax/evo/crm/models.py` contendo exclusivamente `prospect_name`, `phone`, `initial_demand`, `identified_interest` e `lifecycle_stage` (sem classificação de frio/quente).
  - Implementar o método assíncrono `upsert_prospect_contact_card` em `CRMAPIClient` (`paralax/evo/crm/client.py`), que cria ou atualiza o card vinculado à conversa/contato no pipeline configurado do CRM preenchendo `custom_fields` e `notes` formatados, sem exigir qualquer mudança no backend do CRM.
  - Disponibilizar em `paralax/evo/crm/callbacks.py` as funções reutilizáveis `extract_prospect_card_with_llm` e `sync_prospect_contact_card` para que qualquer agente do ecossistema possa habilitar a organização da base de contatos de forma opt-in.
  - Garantir cobertura completa de testes unitários em `tests/unit/` com docstrings `Business Rule:`.

- [ ] **[Onda 2] `paralax-ia/paralax-support` (`task-2`):**
  - Atualizar a dependência `paralax-evo-crm` (`uv lock --upgrade-package paralax-evo-crm`).
  - Configurar suporte opt-in via variáveis de ambiente (`ENABLE_PROSPECT_CARD_SYNC` / `PROSPECT_CARD_PIPELINE_NAME`, ou compartilhando `ENABLE_SALES_PIPELINE` / `SALES_PIPELINE_NAME` quando habilitado) em `support/config.py`.
  - Integrar a extração via LLM e atualização automática do card (`upsert_prospect_contact_card` / `sync_prospect_contact_card`) no callback pós-conversa (`after_agent_pipeline_callback` em `support/shared_libraries/callbacks.py`), consolidando `prospect_name`, `phone`, `initial_demand` e `identified_interest`.
  - Criar testes unitários em `tests/unit/` validando a criação/atualização do card de prospecto e o comportamento opt-in.

- [ ] **[Onda 2] `paralax-ia/anero-cafe-support` (`task-3`):**
  - Atualizar a dependência `paralax-evo-crm` (`uv lock --upgrade-package paralax-evo-crm`).
  - Adicionar em `anero_cafe/config.py` as variáveis de ambiente opt-in `ENABLE_PROSPECT_CARD_SYNC` (bool, padrão `False`) e `PROSPECT_CARD_PIPELINE_NAME` (str, padrão `""`), mantendo conformidade 12-Factor.
  - Registrar e implementar `after_agent_callback` em `anero_cafe/shared_libraries/callbacks.py` e `anero_cafe/agent.py` invocando `sync_prospect_contact_card` para organizar os contatos recebidos pelo concierge do Anero Café (nome do prospecto, telefone, dúvida/demanda inicial e interesse identificado em cafés/produtos/pedidos).
  - Criar testes unitários em `tests/unit/` validando o fluxo opt-in e a persistência resiliente no CRM.

- [ ] **[Onda 2] `paralax-ia/customer-support-vehicles` (`task-4`):**
  - Atualizar a dependência `paralax-evo-crm` (`uv lock --upgrade-package paralax-evo-crm`).
  - Adicionar em `vehicles/config.py` as variáveis de ambiente opt-in `ENABLE_PROSPECT_CARD_SYNC` (bool, padrão `False`) e `PROSPECT_CARD_PIPELINE_NAME` (str, padrão `""`), mantendo conformidade 12-Factor.
  - Registrar e implementar `after_agent_callback` em `vehicles/shared_libraries/callbacks.py` e `vehicles/agent.py` invocando `sync_prospect_contact_card` para organizar os contatos recebidos pelo agente automotivo (nome do prospecto, telefone, dúvida/demanda inicial e interesse identificado em veículos/modelos/financiamento).
  - Criar testes unitários em `tests/unit/` validando o fluxo opt-in e a persistência resiliente no CRM.

---

## 3. Contratos de Interface

### 3.1. Modelos de Domínio no SDK (`paralax-evo-crm` — `paralax/evo/crm/models.py`)

```python
from typing import Any, Literal
from pydantic import BaseModel, ConfigDict, Field

ContactLifecycleStage = Literal["prospect", "customer"]


class ProspectCardExtraction(BaseModel):
    """Estrutura extraída pelo LLM a partir da interação com o contato recebido."""

    prospect_name: str = Field(
        default="Prospecto Sem Nome",
        description="Nome identificado do prospecto (futuro potencial cliente).",
    )
    phone: str = Field(
        default="",
        description="Telefone do contato extraído dos metadados da sessão ou da conversa.",
    )
    initial_demand: str = Field(
        description="Dúvida ou demanda inicial relatada pelo contato.",
    )
    identified_interest: str = Field(
        description="Interesse comercial específico identificado no contato (produto, serviço, veículo, café ou solução).",
    )


class ProspectContactCard(BaseModel):
    """Representa o card estruturado de organização de um contato/prospecto no CRM.

    Permite organizar a base de contatos sem alterar o código-fonte do CRM core,
    persistindo os dados nos metadados (`custom_fields`) e notas do card no pipeline.
    Não inclui classificação estática de temperatura (frio/quente), pois a temperatura
    é transitória ao momento da interação e muda naturalmente ao longo do tempo.
    """

    prospect_name: str = Field(
        default="Prospecto Sem Nome",
        description="Nome do prospecto (que pode evoluir para cliente no futuro).",
    )
    phone: str = Field(
        description="Telefone do contato recebido (ex: formato E.164 ou identificador WhatsApp).",
    )
    initial_demand: str = Field(
        description="Dúvida ou demanda inicial apresentada pelo contato.",
    )
    identified_interest: str = Field(
        description="Interesse comercial identificado na interação (produto, serviço ou solução).",
    )
    lifecycle_stage: ContactLifecycleStage = Field(
        default="prospect",
        description="Estágio no ciclo de vida do contato ('prospect' por padrão, podendo tornar-se 'customer' no futuro).",
    )
    model_config = ConfigDict(extra="allow")

    def to_crm_custom_fields(
        self, extra_fields: dict[str, Any] | None = None
    ) -> dict[str, Any]:
        """Converte os atributos do card de prospecto para o dicionário `custom_fields` do CRM.

        Args:
            extra_fields: Campos adicionais opcionais a serem mesclados.

        Returns:
            Dicionário serializável pronto para envio em `custom_fields` do `PipelineItem`.
        """
        fields: dict[str, Any] = {
            "prospect_name": self.prospect_name,
            "phone": self.phone,
            "initial_demand": self.initial_demand,
            "identified_interest": self.identified_interest,
            "lifecycle_stage": self.lifecycle_stage,
        }
        if extra_fields:
            fields.update(extra_fields)
        return fields

    def to_crm_summary_note(self) -> str:
        """Gera um resumo textual estruturado do card para registro em `notes` no CRM.

        Returns:
            Nota formatada com nome do prospecto, telefone, demanda inicial e
            interesse identificado.
        """
        return (
            f"[Card de Contato - {self.lifecycle_stage.upper()}] "
            f"Nome: {self.prospect_name} | "
            f"Telefone: {self.phone} | "
            f"Demanda Inicial: {self.initial_demand} | "
            f"Interesse Identificado: {self.identified_interest}"
        )
```

---

### 3.2. Contrato do Cliente HTTP no SDK (`paralax-evo-crm` — `paralax/evo/crm/client.py`)

O método `upsert_prospect_contact_card` utiliza apenas as rotas já existentes no CRM (`GET /api/v1/pipelines`, `GET /api/v1/pipelines/by_conversation/{conversation_id}`, `POST /api/v1/pipelines/{pipeline_id}/pipeline_items` e `PATCH /api/v1/pipelines/{pipeline_id}/pipeline_items/{item_id}`):

```python
class CRMAPIClient:
    async def upsert_prospect_contact_card(
        self,
        conversation_id: str,
        pipeline_name: str,
        card: ProspectContactCard,
        target_stage_name: str | None = None,
        extra_custom_fields: dict[str, Any] | None = None,
    ) -> tuple[Pipeline, PipelineItem]:
        """Cria ou atualiza o card de um prospecto/contato no pipeline do CRM sem alterar o CRM core.

        Fluxo de Execução:
        1. Mescla os campos estruturados do `ProspectContactCard` (`prospect_name`, `phone`,
           `initial_demand`, `identified_interest`, `lifecycle_stage`) com `extra_custom_fields`.
        2. Garante a existência do card na conversa via `ensure_conversation_in_pipeline`
           no funil `pipeline_name`.
        3. Atualiza o card via `move_pipeline_item` (mantendo o estágio atual ou movendo
           para `target_stage_name` se informado), persistindo os `custom_fields` atualizados
           e a nota consolidada (`card.to_crm_summary_note()`).

        Args:
            conversation_id: Identificador da conversa no CRM.
            pipeline_name: Nome do pipeline onde os cards de contatos são organizados.
            card: Instância validada de `ProspectContactCard`.
            target_stage_name: Nome opcional da etapa de destino no pipeline.
            extra_custom_fields: Metadados complementares opcionais.

        Returns:
            Tupla `(Pipeline, PipelineItem)` com o card criado ou atualizado.

        Raises:
            CRMAPIError: Em caso de erro de comunicação com a API do CRM.
        """
        ...
```

---

### 3.3. Extrator LLM e Orquestrador Opt-in Compartilhados (`paralax-evo-crm` — `paralax/evo/crm/callbacks.py`)

Para que qualquer agente do ecossistema (`paralax-support`, `anero-cafe-support`, `customer-support-vehicles` ou futuros agentes) possa aderir à organização da base de contatos sem duplicar lógica:

```python
from typing import Any
from paralax.evo.crm.client import CRMAPIClient
from paralax.evo.crm.models import Pipeline, PipelineItem, ProspectCardExtraction, ProspectContactCard


async def extract_prospect_card_with_llm(
    last_interaction: str,
    contact_phone: str = "",
    contact_name: str = "",
    app_config: Any = None,
    llm_client: Any = None,
) -> ProspectCardExtraction | None:
    """Analisa a interação do contato recebido via LLM para extrair os dados do card do prospecto.

    Extrai `prospect_name`, `phone`, `initial_demand` e `identified_interest` usando
    saída estruturada Pydantic (`ProspectCardExtraction`), sem classificar o contato
    como frio ou quente.

    Args:
        last_interaction: Conteúdo consolidado da interação com o contato.
        contact_phone: Telefone do contato recebido nos metadados do webhook/sessão.
        contact_name: Nome prévio do contato nos metadados do webhook/sessão, se disponível.
        app_config: Instância de configuração do agente carregada via variáveis de ambiente.
        llm_client: Cliente `google.genai.Client` opcional para injeção em testes.

    Returns:
        Instância de `ProspectCardExtraction` preenchida pelo LLM, ou `None` se a chamada falhar.
    """
    ...


async def sync_prospect_contact_card(
    conversation_id: str,
    crm_client: CRMAPIClient,
    app_config: Any,
    last_interaction: str,
    contact_phone: str = "",
    contact_name: str = "",
    target_stage_name: str | None = None,
    extra_custom_fields: dict[str, Any] | None = None,
    llm_client: Any = None,
) -> tuple[Pipeline, PipelineItem] | None:
    """Sincroniza de forma opt-in e tolerante a falhas o card do prospecto no CRM.

    Verifica se a funcionalidade está habilitada no `app_config` (`ENABLE_PROSPECT_CARD_SYNC`
    ou `ENABLE_SALES_PIPELINE`) e resolve o nome do pipeline (`PROSPECT_CARD_PIPELINE_NAME`
    ou `SALES_PIPELINE_NAME`). Caso desabilitada, retorna `None` imediatamente (no-op).
    Quando habilitada, extrai os dados via `extract_prospect_card_with_llm`, constrói o
    `ProspectContactCard` e invoca `crm_client.upsert_prospect_contact_card(...)`,
    capturando `CRMAPIError` com log de warning para nunca interromper o atendimento.
    """
    ...
```

---

### 3.4. Contrato de Configuração Opt-in nos Agentes Consumidores (`paralax-support`, `anero-cafe-support`, `customer-support-vehicles`)

Em `support/config.py`, `anero_cafe/config.py` e `vehicles/config.py`, a adesão é controlada exclusivamente via variáveis de ambiente:

```python
from pydantic import Field
from pydantic_settings import BaseSettings


class Config(BaseSettings):
    # Ativação opt-in da organização de cards de prospectos na base de contatos
    ENABLE_PROSPECT_CARD_SYNC: bool = Field(
        default=False, validation_alias="ENABLE_PROSPECT_CARD_SYNC"
    )
    PROSPECT_CARD_PIPELINE_NAME: str = Field(
        default="", validation_alias="PROSPECT_CARD_PIPELINE_NAME"
    )
```

> **Nota para `paralax-support`:** Caso `ENABLE_PROSPECT_CARD_SYNC` / `PROSPECT_CARD_PIPELINE_NAME` não estejam definidos separadamente mas `ENABLE_SALES_PIPELINE=true` e `SALES_PIPELINE_NAME` estejam ativos, o callback pós-conversa utiliza o pipeline configurado para enriquecer o card da conversa com `prospect_name`, `phone`, `initial_demand`, `identified_interest` e `lifecycle_stage="prospect"`.

---

## 4. Critérios de Aceitação (Gherkin)

### Cenário 1: Criação Automática de Card de Prospecto Sem Classificação Frio/Quente e Sem Alterar o CRM Core
- **Dado** que um novo contato envia mensagem para qualquer um dos agentes habilitados (`paralax-support`, `anero-cafe-support` ou `customer-support-vehicles`) apresentando seu nome ("Mariana Costa"), telefone (`+5511998765432`), uma dúvida/demanda inicial e um interesse específico
- **Quando** o callback pós-conversa processar o turno e acionar `upsert_prospect_contact_card` via SDK `paralax-evo-crm`
- **Então** um card deve ser criado no pipeline configurado do CRM sem qualquer alteração no código de `evo-ai-crm-community`
- **E** o `custom_fields` do card deve conter `prospect_name="Mariana Costa"`, `phone="+5511998765432"`, `initial_demand`, `identified_interest` e `lifecycle_stage="prospect"`
- **E** o card **não deve** possuir atributo `lead_temperature` nem classificar estaticamente o contato entre `"frio"` ou `"quente"`.

### Cenário 2: Aplicação Modular Opt-in nos Agentes Paralax, Anero Café e Vehicles
- **Dado** que a funcionalidade de organização da base de contatos está disponível no SDK `paralax-evo-crm`
- **Quando** as variáveis de ambiente de ativação (`ENABLE_PROSPECT_CARD_SYNC="true"` e `PROSPECT_CARD_PIPELINE_NAME`) estiverem habilitadas nos agentes `paralax-support`, `anero-cafe-support` e `customer-support-vehicles`
- **Então** cada um dos três agentes deve extrair via LLM (`extract_prospect_card_with_llm`) o nome do prospecto, telefone, demanda inicial e interesse identificado de acordo com o contexto da conversa e atualizar o card no CRM após cada interação
- **E** quando a variável de ativação estiver `"false"` (padrão opt-in desativado), o callback deve operar como *no-op* sem realizar chamadas ao LLM extrator ou à API de pipelines do CRM.

### Cenário 3: Atualização Incremental de Card de Prospecto Existente na Mesma Conversa
- **Dado** que o contato já possui um card criado anteriormente na conversa com nome padrão (`"Prospecto Sem Nome"`) e uma dúvida inicial registrada
- **Quando** em um novo turno o prospecto informar seu nome real e refinar seu interesse comercial
- **Então** o método `upsert_prospect_contact_card` deve atualizar o card existente no CRM com o novo `prospect_name` e `identified_interest` atualizado mantendo `lifecycle_stage="prospect"`
- **E** não deve duplicar cards para a mesma conversa no pipeline.

### Cenário 4: Tolerância a Falhas e Resiliência na Comunicação com o CRM
- **Dado** que a API do CRM esteja temporariamente indisponível (ex: HTTP 503 ou timeout)
- **Quando** o callback pós-conversa de `paralax-support`, `anero-cafe-support` ou `customer-support-vehicles` tentar criar ou atualizar o card do prospecto
- **Então** a exceção `CRMAPIError` deve ser capturada e registrada em log de warning no agente
- **E** a resposta ao contato no canal de atendimento não deve ser interrompida.

---

## 5. Plano de Rollout e Compatibilidade

1. **Sequência de Implementação por Ondas:**
   - **Onda 1 (`paralax-ia/paralax-evo-crm`):** Implementação de `ProspectContactCard`, `ProspectCardExtraction`, `ContactLifecycleStage`, `CRMAPIClient.upsert_prospect_contact_card`, `extract_prospect_card_with_llm` e `sync_prospect_contact_card` ➔ Validação com `just verify` ➔ Merge e publicação de nova versão SemVer (`minor`) no Artifact Registry.
   - **Onda 2 (`paralax-ia/paralax-support`, `paralax-ia/anero-cafe-support`, `paralax-ia/customer-support-vehicles`):** Atualização do pacote `paralax-evo-crm` via `uv lock --upgrade-package paralax-evo-crm` ➔ Configuração das variáveis de ambiente opt-in (`ENABLE_PROSPECT_CARD_SYNC` e `PROSPECT_CARD_PIPELINE_NAME`) e integração no callback pós-conversa de cada um dos três agentes ➔ Validação com `just verify`.
2. **Compatibilidade e Rollback:**
   - Mudança 100% aditiva e retrocompatível nos modelos e métodos de `paralax-evo-crm`.
   - Adoção estritamente opt-in por agente: agentes que não habilitarem a variável de ambiente continuam operando sem qualquer alteração de comportamento.
   - Zero migração de banco de dados ou alteração no repositório `evo-ai-crm-community`, utilizando exclusivamente os campos extensíveis `custom_fields` e `notes` já suportados pela API REST v1 do CRM.
