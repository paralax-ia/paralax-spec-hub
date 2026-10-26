---
spec_id: SPEC-007
title: "Transbordo para Celular do Atendente com Resumo Estruturado da Conversa"
product:
  - anero-cafe-support
  - paralax-platform
capability: customer-relationship-management
scope: platform
bounded_context: "CRM & Transbordo de Atendimento (Supporting Subdomain)"
origin_module: paralax-evo-crm
target_repositories:
  - repo: paralax-ia/paralax-evo-crm
    wave: 1
    role: sdk
  - repo: paralax-ia/anero-cafe-support
    wave: 2
    role: ai-agent
status: DRAFT
---

# SPEC-007: Transbordo para Celular do Atendente com Resumo Estruturado da Conversa

> **Product:** [`anero-cafe-support`](../products/anero-cafe-support.yaml) | [`paralax-platform`](../products/paralax-platform.yaml)  
> **Business Capability:** [`customer-relationship-management`](../capabilities/customer-relationship-management/capability.yaml)  
> **Scope:** Platform (Disponível para todos os agentes, com adoção piloto no Anero Café)  
> **Bounded Context:** CRM & Transbordo de Atendimento (Supporting Subdomain)  
> **Status:** DRAFT  
> **Autor:** Eduardo F. Santos  
> **Data de Criação:** 2026-10-26  
> **Arquitetura 12-Factor:** Zero arquivos de configuração salvos no Git; toda configuração é gerada exclusivamente a partir de variáveis de ambiente  
> **Diretriz de Prompts:** Prompts de sistema e templates de instrução para LLM devem ser estritamente redigidos em inglês  
> **Repositórios Impactados:**  
> - `paralax-ia/paralax-evo-crm` (Onda 1 - SDK Compartilhado: Modelos de Dados, Sumarizador via LLM e Ferramenta de Transbordo para Celular)  
> - `paralax-ia/anero-cafe-support` (Onda 2 - Agente Anero Café: Configuração 12-Factor, Registro da Ferramenta e Instruções de Transbordo em Compras)

---

## 1. Contexto e Motivação

Os agentes de inteligência artificial da plataforma Paralax IA (como o concierge virtual do **Anero Café**) desempenham com eficácia o atendimento receptivo, a apresentação do catálogo de cafés especiais, métodos de extração e esclarecimento de dúvidas operacionais.

No entanto, no comércio conversacional via canais digitais (como WhatsApp), quando o cliente decide realizar uma **ação transacional crítica** — em especial uma **compra**, fechamento de pedido de café/grãos, encomenda de pacotes ou solicitação de negociação comercial —, o fluxo de atendimento precisa ser transferido para um **número de celular específico** (o WhatsApp do barista, atendente comercial ou gerente da loja).

### O Desafio Atual e Limitações
1. **Transbordo Tradicional Restrito à Interface Web do CRM:**
   O transbordo existente (`request_human_handoff`) limita-se a alterar o status da conversa no CRM para `"open"`. Esse fluxo depende de um operador humano conectado na interface web do CRM para visualizar a fila de espera. No modelo operacional do Anero Café e do comércio ágil, os atendentes e baristas operam no chão de loja com aparelhos de celular/WhatsApp próprios.
2. **Perda de Contexto e Fricção na Compra:**
   Se o cliente apenas for orientado a enviar mensagem para outro número sem que o atendente receba o contexto prévio, o cliente é obrigado a repetir todas as informações já passadas à IA (produtos de interesse, quantidade, moagem, endereço de entrega).
3. **Necessidade de Continuidade no Celular do Atendente:**
   Quando uma ação como **compra** é solicitada, o sistema deve:
   - Gerar um **resumo estruturado da conversa** (`ConversationSummary`) consolidando o nome do cliente, telefone, intenção (ex: compra), itens de interesse e histórico.
   - Enviar a notificação com esse resumo diretamente para o **número de celular do atendente** (`target_phone_number`).
   - Fornecer ao cliente um **link direto do WhatsApp (`wa.me`)** contendo mensagem contextual pré-preenchida para que ele inicie o diálogo diretamente com o atendente humano, sem fricção.
   - Atualizar a conversa no CRM, registrando o transbordo e notas de contexto.

### Diretrizes de Engenharia e Arquitetura
- **Disponibilidade Global com Piloto no Anero Café:** A ferramenta de transbordo para celular e a inteligência de sumarização devem ser desenvolvidas de forma genérica e reutilizável na camada de SDK (`paralax-evo-crm`), permitindo que qualquer agente do ecossistema a utilize de forma opt-in. A primeira aplicação em produção ocorrerá no agente **Anero Café** (`anero-cafe-support`).
- **Prompts Estritamente em Inglês (English-Only Prompts):** O template de prompt do LLM para sumarização (`CONVERSATION_SUMMARY_PROMPT_TEMPLATE`) e as instruções de sistema em `anero_cafe/prompts.py` devem ser redigidos exclusivamente em inglês, assegurando precisão, baixa ambiguidade e conformidade estrita com o esquema Pydantic.
- **Princípio 12-Factor (Zero Config no Git):** O número de telefone do celular do atendente (`ATTENDANT_PHONE_NUMBER`) e as flags de ativação devem ser configurados exclusivamente a partir de variáveis de ambiente (`os.environ`), sem arquivos `.env` ou `.yaml` versionados no Git.
- **Resiliência e Tolerância a Falhas:** Caso ocorra falha temporária no disparo da mensagem ao celular do atendente via CRM, a ferramenta não deve interromper a interação com o usuário: o link direto `wa.me` deve ser entregue ao cliente como canal de contingência garantido.
- **Padrões de Código Python (PEP 8, Google Docstrings, Sem Funções Aninhadas):** Código 100% aderente aos padrões corporativos, sem blocos `try...except` aninhados ou em imports, com docstrings Google completas.

---

## 2. Escopo e Repositórios Afetados

```
┌────────────────────────────────────────────────────────────────────────┐
│                       ONDA 1 (PENDENTE - TASK-1)                       │
│                       paralax-ia/paralax-evo-crm                       │
│  • Modelos Pydantic tipados: `ConversationSummary`,                    │
│    `MobileHandoffResult` e `HandoffActionType`                         │
│  • Módulo `paralax/evo/crm/mobile_handoff.py`:                         │
│    - Sumarizador via LLM com prompt estritamente em inglês             │
│    - Gerador de link de redirecionamento WhatsApp (wa.me)              │
│    - Ferramenta ADK `@safe_tool` e `@observe`:                         │
│      `transfer_to_mobile_attendant`                                    │
│  • Suíte completa de testes unitários em `tests/unit/`                 │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                       ONDA 2 (PENDENTE - TASK-2)                       │
│                      paralax-ia/anero-cafe-support                     │
│  • Atualização da dependência `paralax-evo-crm`                        │
│  • Mapeamento 12-Factor em `anero_cafe/config.py`:                     │
│    `ATTENDANT_PHONE_NUMBER` e `ENABLE_MOBILE_HANDOFF`                  │
│  • Registro de `transfer_to_mobile_attendant` em `anero_cafe/agent.py` │
│  • Atualização de instruções em inglês em `anero_cafe/prompts.py`      │
│    para acionar transbordo em intenções de compra/pedidos              │
│  • Suíte completa de testes unitários em `tests/unit/`                 │
└────────────────────────────────────────────────────────────────────────┘
```

- [ ] **[Onda 1] `paralax-ia/paralax-evo-crm` (`task-1`):**
  - Implementar em `paralax/evo/crm/models.py` os modelos Pydantic:
    - `HandoffActionType`: Literal categorizando a ação (`"purchase"`, `"order"`, `"support"`, `"human_request"`, `"other"`).
    - `ConversationSummary`: Estrutura consolidando `customer_name`, `customer_phone`, `action_type`, `items_of_interest` e `summary_text`.
    - `MobileHandoffResult`: Estrutura de retorno com `success`, `target_phone`, `whatsapp_link`, `summary` e `message`.
  - Criar o módulo `paralax/evo/crm/mobile_handoff.py`:
    - Template de prompt em inglês estrito: `CONVERSATION_SUMMARY_PROMPT_TEMPLATE`.
    - Função `generate_conversation_summary(conversation_history: str, action_type: str, app_config: Any, llm_client: Any) -> ConversationSummary`.
    - Função utilitária `build_whatsapp_direct_link(phone_number: str, prefilled_text: str) -> str`.
    - Ferramenta ADK `@safe_tool` e `@observe`:
      `async def transfer_to_mobile_attendant(ctx: ToolContext, target_phone_number: str, action_type: str, reason: str, items_of_interest: list[str] | None = None) -> dict[str, Any]`.
    - Notificação via `crm_api.send_message` para o canal/conversa do atendente ou envio de mensagem de WhatsApp estruturada.
    - Atualização do status da conversa no CRM (`toggle_conversation_status` para `"open"`) e anexação de nota interna.
  - Testes unitários em `tests/unit/test_mobile_handoff.py` validando sumarização, montagem de URL `wa.me`, proteção contra erros de rede e docstrings `Business Rule:`.

- [ ] **[Onda 2] `paralax-ia/anero-cafe-support` (`task-2`):**
  - Atualizar dependência `paralax-evo-crm` (`uv lock --upgrade-package paralax-evo-crm`).
  - Adicionar parâmetros de configuração 12-Factor em `anero_cafe/config.py`:
    - `ATTENDANT_PHONE_NUMBER: str = Field(default="", validation_alias="ATTENDANT_PHONE_NUMBER")`
    - `ENABLE_MOBILE_HANDOFF: bool = Field(default=True, validation_alias="ENABLE_MOBILE_HANDOFF")`
  - Registrar a ferramenta `transfer_to_mobile_attendant` na lista de ferramentas (`tools`) do `root_agent` em `anero_cafe/agent.py`.
  - Atualizar as instruções da agente em `anero_cafe/prompts.py` (estritamente em inglês):
    - Instruir o agente a acionar `transfer_to_mobile_attendant` sempre que o cliente manifestar intenção de **compra** de cafés, fechamento de pedidos, entrega, reservas ou solicitação de atendimento humano por celular.
    - Orientar a apresentar cordialmente a mensagem de confirmação e o link direto do WhatsApp fornecido pela ferramenta.
  - Criar testes unitários em `tests/unit/test_mobile_handoff.py` validando o fluxo conversacional de compra com transbordo para o celular.

---

## 3. Contratos de Interface

### 3.1. Modelos de Domínio (`paralax-evo-crm` — `paralax/evo/crm/models.py`)

```python
from typing import Any, Literal
from pydantic import BaseModel, ConfigDict, Field

HandoffActionType = Literal["purchase", "order", "support", "human_request", "other"]


class ConversationSummary(BaseModel):
    """Resumo estruturado da conversa para ser entregue ao celular do atendente."""

    customer_name: str = Field(
        default="Cliente",
        description="Nome identificado do cliente, se disponível no diálogo.",
    )
    customer_phone: str = Field(
        default="",
        description="Número de telefone do cliente no formato E.164 ou identificador do canal.",
    )
    action_type: HandoffActionType = Field(
        default="purchase",
        description="Categoria de ação que disparou o transbordo (ex: purchase, order, human_request).",
    )
    items_of_interest: list[str] = Field(
        default_factory=list,
        description="Lista de produtos, cafés, métodos ou serviços de interesse do cliente.",
    )
    summary_text: str = Field(
        description="Resumo conciso e objetivo em 2 a 3 frases explicando o que o cliente deseja e o histórico recente.",
    )
    model_config = ConfigDict(extra="allow")


class MobileHandoffResult(BaseModel):
    """Resultado da execução do transbordo para o celular do atendente."""

    success: bool = Field(
        description="Indica se o transbordo para celular foi orquestrado com sucesso.",
    )
    target_phone: str = Field(
        description="Número de telefone celular do atendente para o qual a conversa foi direcionada.",
    )
    whatsapp_link: str = Field(
        description="Link direto no formato wa.me com mensagem inicial pré-preenchida para o cliente.",
    )
    summary: ConversationSummary = Field(
        description="Objeto com o resumo estruturado da conversa gerado pelo LLM.",
    )
    notification_sent: bool = Field(
        default=False,
        description="Indica se a notificação foi despachada com sucesso ao celular do atendente.",
    )
    message: str = Field(
        description="Mensagem informativa gerada para orientar a resposta do agente ao cliente.",
    )
    model_config = ConfigDict(extra="allow")
```

---

### 3.2. Template de Prompt do Sumarizador em Inglês (`paralax/evo/crm/mobile_handoff.py`)

O prompt submetido ao modelo para consolidar o histórico da conversa deve ser **obrigatoriamente em inglês**:

```python
CONVERSATION_SUMMARY_PROMPT_TEMPLATE = """You are an expert sales and customer service coordinator.
A customer interacting with an automated AI agent has requested an action that requires transferring the conversation to a human attendant's mobile phone (such as a purchase, order closing, or specific assistance).

Analyze the conversation history provided below and generate a concise, structured handoff summary for the attendant:
- customer_name: Name of the customer, if mentioned in the conversation.
- customer_phone: Customer phone number, if mentioned in the conversation.
- action_type: Category of action requested ('purchase', 'order', 'support', 'human_request', or 'other').
- items_of_interest: Specific products, services, coffee beans, or items the customer showed interest in.
- summary_text: A concise, objective 2-3 sentence summary detailing what the customer wants, any questions they asked, and what they need to finalize.

Conversation History:
{conversation_history}"""
```

---

### 3.3. Contrato da Ferramenta de Transbordo ADK (`paralax/evo/crm/mobile_handoff.py`)

A função deve ser decorada com `@safe_tool` e `@observe` e aceitar o contexto do Google ADK:

```python
from typing import Any, Optional
from google.adk.tools import ToolContext
from langfuse import observe
from paralax.agents.common.tools import safe_tool


@observe(capture_input=False, capture_output=False)
@safe_tool
async def transfer_to_mobile_attendant(
    ctx: ToolContext,
    action_type: str = "purchase",
    reason: str = "Customer requested purchase or human assistance",
    items_of_interest: Optional[list[str]] = None,
) -> dict[str, Any]:
    """Transfere a conversa para o celular do atendente humano com resumo estruturado.

    Esta ferramenta é acionada quando o usuário manifesta intenção de compra, fechamento
    de pedido ou solicita atendimento no WhatsApp de um atendente humano. Ela sintetiza
    o resumo da conversa via LLM, notifica o celular do atendente e gera um link
    direto do WhatsApp (`wa.me`) para o cliente dar continuidade imediata ao atendimento.

    Args:
        ctx: Contexto da ferramenta do Google ADK contendo a sessão.
        action_type: Categoria da ação ('purchase', 'order', 'human_request').
        reason: Motivo detalhado do transbordo.
        items_of_interest: Lista opcional de produtos ou itens discutidos no diálogo.

    Returns:
        Dicionário com o resultado do transbordo contendo:
        - 'success' (bool): True se o transbordo foi orquestrado.
        - 'target_phone' (str): Celular do atendente de destino.
        - 'whatsapp_link' (str): Link wa.me pré-formatado para o cliente.
        - 'summary' (dict): Resumo estruturado da conversa.
        - 'message' (str): Orientação de resposta amigável para o cliente.
    """
    ...
```

---

### 3.4. Configurações 12-Factor no Agente Anero Café (`anero_cafe/config.py`)

Configurações resolvidas exclusivamente via variáveis de ambiente:

```python
class Config(BaseSettings):
    # Transbordo para Celular do Atendente
    ATTENDANT_PHONE_NUMBER: str = Field(
        default="",
        validation_alias="ATTENDANT_PHONE_NUMBER",
        description="Número de celular no padrão E.164 (ex: +5561999999999) para transbordo.",
    )
    ENABLE_MOBILE_HANDOFF: bool = Field(
        default=True,
        validation_alias="ENABLE_MOBILE_HANDOFF",
        description="Habilita ou desabilita a capacidade de transbordo para celular.",
    )
```

---

### 3.5. Instruções da Agente Anero Café (`anero_cafe/prompts.py`)

Atualização nas seções de ferramentas e diretrizes, estritamente em inglês:

```markdown
<tools_and_search>
You have the following tools available:
- `coffee_search`: Searches for coffee products offered by Anero Café.
- `get_coffee_details`: Extracts pricing, categories, and variations of a specific coffee product.
- `transfer_to_mobile_attendant`: Transfers the conversation to the human attendant's mobile phone number (WhatsApp) when the customer requests a purchase, wants to finalize an order, or asks to speak with a human attendant.

HANDLING PURCHASES AND MOBILE HANDOFF:
When the customer expresses intent to BUY coffee, place an order, negotiate quantities, or asks to speak with a salesperson/attendant:
1. ALWAYS invoke the `transfer_to_mobile_attendant` tool specifying `action_type="purchase"` and passing any products discussed.
2. In your response to the customer:
   - Acknowledge their purchase request with enthusiasm.
   - Inform them that our store attendant has already been notified with the full summary of what they discussed.
   - Provide the WhatsApp direct link returned by the tool so the customer can start or continue the chat directly with the attendant.
</tools_and_search>
```

---

## 4. Critérios de Aceitação (Gherkin)

### Cenário 1: Transbordo para Celular em Intenção de Compra de Café
- **Dado** que um cliente está conversando com o Anero Bot e envia a mensagem: `"Gostei muito do Catuaí Vermelho. Como faço para comprar 2 pacotes moídos para filtro?"`
- **Quando** o agente processar a intenção de compra e acionar a ferramenta `transfer_to_mobile_attendant`
- **Então** o resumo da conversa gerado pelo LLM deve conter `action_type="purchase"`, cliente identificado e o item `"Catuaí Vermelho"` na lista de interesse
- **E** a ferramenta deve gerar um link do WhatsApp no formato `https://wa.me/<ATTENDANT_PHONE_NUMBER>?text=...` contendo mensagem contextual pré-preenchida
- **E** o resultado deve registrar `success=True` e retornar a mensagem com o link para o cliente finalizar o pedido com o atendente.

### Cenário 2: Transbordo sob Solicitação Explícita de Celular do Atendente
- **Dado** que o cliente pergunta: `"Pode me passar o WhatsApp de alguém da loja para eu tirar uma dúvida sobre eventos?"`
- **Quando** a ferramenta `transfer_to_mobile_attendant` for executada com `action_type="human_request"`
- **Então** o prompt de sumarização enviado ao LLM deve ser submetido estritamente em inglês (`CONVERSATION_SUMMARY_PROMPT_TEMPLATE`)
- **E** o status da conversa no CRM deve ser atualizado para `"open"`
- **E** o link direto do WhatsApp do atendente deve ser entregue ao cliente.

### Cenário 3: Resiliência em Caso de Falha de Envio de Mensagem ao Atendente
- **Dado** que a API do CRM ou o canal de mensageria apresente instabilidade temporária (timeout ou HTTP 500) ao disparar a notificação para o celular do atendente
- **Quando** a ferramenta `transfer_to_mobile_attendant` for executada
- **Então** a exceção de envio deve ser capturada de forma tolerante (`notification_sent=False`)
- **E** a ferramenta ainda deve retornar `success=True` com o link `wa.me` válido para o cliente
- **E** o cliente não deve receber mensagem de erro técnico no chat.

### Cenário 4: Conformidade 12-Factor e Ausência de Configurações no Git
- **Dado** o repositório `anero-cafe-support`
- **Quando** a configuração `Config` for instanciada
- **Então** as variáveis `ATTENDANT_PHONE_NUMBER` e `ENABLE_MOBILE_HANDOFF` devem ser lidas exclusivamente de variáveis de ambiente (`os.environ`)
- **E** nenhum arquivo `.env` ou arquivo de configuração com dados sensíveis deve estar rastreado no Git.

### Cenário 5: Padronização de Prompts Estritamente em Inglês
- **Dado** a suíte de testes de `paralax-evo-crm` e `anero-cafe-support`
- **Quando** os templates de prompt de sumarização e as instruções da agente forem verificados
- **Então** todos os prompts de sistema e templates de instrução para LLM devem estar redigidos em inglês.

---

## 5. Plano de Rollout e Compatibilidade

1. **Sequência de Implementação por Ondas:**
   - **Onda 1 (`paralax-ia/paralax-evo-crm`):**
     1. Criação dos modelos Pydantic `ConversationSummary`, `MobileHandoffResult` e `HandoffActionType`.
     2. Implementação de `generate_conversation_summary` (com prompt em inglês), gerador de links `wa.me` e a ferramenta ADK `transfer_to_mobile_attendant`.
     3. Suíte de testes unitários em `tests/unit/test_mobile_handoff.py`.
     4. Validação com `just verify`, merge e publicação de nova versão minor do SDK no Artifact Registry.
   - **Onda 2 (`paralax-ia/anero-cafe-support`):**
     1. Atualização do lockfile do projeto para a nova versão de `paralax-evo-crm`.
     2. Mapeamento das variáveis de ambiente 12-Factor (`ATTENDANT_PHONE_NUMBER` e `ENABLE_MOBILE_HANDOFF`) em `anero_cafe/config.py`.
     3. Registro da ferramenta `transfer_to_mobile_attendant` em `anero_cafe/agent.py`.
     4. Atualização das instruções da agente em inglês em `anero_cafe/prompts.py`.
     5. Suíte de testes unitários e validação integral com `just verify`.
2. **Compatibilidade e Rollback:**
   - Alteração 100% aditiva e retrocompatível no SDK.
   - Agentes que não configurarem `ATTENDANT_PHONE_NUMBER` não sofrem qualquer impacto em seu funcionamento.
   - Caso seja necessário desabilitar o transbordo para celular no Anero Café, basta definir a variável de ambiente `ENABLE_MOBILE_HANDOFF="false"`.
