---
spec_id: SPEC-012
title: "Identificação de Cliente e Classificação PJ/PF com Heurística em Três Etapas - anero-cafe-support"
product:
  - anero-cafe-support
capability: customer-relationship-management
scope: product
bounded_context: "CRM (Supporting Subdomain) / Identificação de Clientes"
origin_module: anero-cafe-support
target_repositories:
  - repo: paralax-ia/anero-cafe-support
    wave: 1
    role: ai-agent
status: DRAFT
---

# SPEC-012: Identificação de Cliente e Classificação PJ/PF com Heurística em Três Etapas - anero-cafe-support

> **Product:** [`anero-cafe-support`](../products/anero-cafe-support.yaml)  
> **Business Capability:** [`customer-relationship-management`](../capabilities/customer-relationship-management/capability.yaml)  
> **Scope:** Product (`anero-cafe-support`)  
> **Bounded Context:** CRM (Supporting Subdomain) / Identificação de Clientes  
> **Status:** DRAFT  
> **Autor:** Antigravity & Eduardo F. Santos  
> **Data de Criação:** 2026-11-09  
> **Repositórios Alvo:**  
> - `paralax-ia/anero-cafe-support` (Onda 1 - Agente de IA)

---

## 1. Contexto e Motivação

O concierge virtual do **Anero Café** atende diariamente tanto clientes consumidores finais (Pessoa Física - PF) em busca de cafés especiais para consumo próprio, quanto contas corporativas e empresas parceiras (Pessoa Jurídica - PJ) interessadas em compras em lote, café corporativo para escritórios, consultorias e parcerias comerciais.

Para garantir um tratamento adequado, roteamento assertivo de pedidos, correta emissão fiscal e organização da base de contatos no CRM, é indispensável que o agente determine com precisão se o interlocutor é **Pessoa Jurídica (PJ)** ou **Pessoa Física (PF)**.

A identificação deve seguir estritamente uma **heurística sequencial em três etapas**:
1. **Verificação no Cadastro do CRM:** Se o contato já for cadastrado, verificar se possui CNPJ informado (`tax_id` com 14 dígitos ou nos atributos) ou se já está classificado como Pessoa Jurídica (`type == 'company'`).
2. **Verificação na Linha Telefônica:** Caso a primeira verificação não identifique o cliente como PJ, verificar se a informação de CNPJ existe vinculada à linha telefônica (em metadados de canal/inbox, titularidade ou perfil comercial do número).
3. **Confirmação Ativa com o Cliente:** Caso ambas as fontes anteriores não possuam a informação, o agente deve cordialmente solicitar que o cliente confirme se é PJ ou PF, fornecendo o seu CNPJ ou CPF, persistindo imediatamente o documento e a classificação no registro do contato no CRM.

---

## 2. Escopo e Repositórios Afetados

```
┌────────────────────────────────────────────────────────────────────────┐
│                        ONDA 1: anero-cafe-support                      │
├────────────────────────────────────────────────────────────────────────┤
│ • Serviço de Identificação: `anero_cafe/services/customer_id.py`       │
│   - Sanitização e validação de CPF (11 dígitos) e CNPJ (14 dígitos)    │
│   - Heurística em 3 etapas (cadastro CRM -> linha telefônica -> ativo)  │
│   - Atualização do contato no CRM via REST (`PATCH /api/v1/contacts`)  │
│                                                                        │
│ • Ferramentas ADK: `anero_cafe/tools/customer_identification.py`       │
│   - `save_customer_identification`: tool para persistir CPF/CNPJ       │
│                                                                        │
│ • Callbacks & Contexto de Sessão: `shared_libraries/callbacks.py`      │
│   - `before_agent`: executa heurística e popula `session.state`        │
│   - `before_model`: instrui o LLM dinamicamente se faltar documento    │
│                                                                        │
│ • Prompt do Sistema: `anero_cafe/prompts.py`                           │
│   - Diretrizes de tom e abordagem cordial para solicitação de CPF/CNPJ │
│                                                                        │
│ • Testes Unitários: `tests/unit/` com TDD estrito e `Business Rule:`   │
└────────────────────────────────────────────────────────────────────────┘
```

- [ ] **[Onda 1] `paralax-ia/anero-cafe-support`:**
  - Implementação completa da heurística de identificação de cliente.
  - Testes unitários cobrindo todos os ramos da heurística.
  - Zero alteração no código legado do CRM (`evo-ai-crm-community`).

---

## 3. Contratos de Interface

### 3.1. Modelos de Domínio Pydantic

```python
from enum import Enum
from pydantic import BaseModel, Field


class CustomerClassification(str, Enum):
    """Classificação do tipo de cliente."""
    PJ = "PJ"  # Pessoa Jurídica
    PF = "PF"  # Pessoa Física
    UNKNOWN = "UNKNOWN"  # Não identificado


class IdentificationSource(str, Enum):
    """Origem que determinou a identificação do cliente."""
    CRM_REGISTRATION = "crm_registration"
    PHONE_LINE = "phone_line"
    CUSTOMER_CONFIRMATION = "customer_confirmation"
    PENDING = "pending"


class IdentificationStatus(BaseModel):
    """Estado consolidado da identificação do cliente."""
    classification: CustomerClassification = CustomerClassification.UNKNOWN
    tax_id: str | None = None
    source: IdentificationSource = IdentificationSource.PENDING
    needs_confirmation: bool = True
    details: str = ""
```

### 3.2. Funções de Serviço

```python
def sanitize_tax_id(tax_id: str | None) -> str:
    """Remove caracteres não numéricos de CPF ou CNPJ."""
    ...

def validate_tax_id(tax_id: str) -> tuple[bool, CustomerClassification]:
    """Valida tamanho e formato: 11 dígitos -> PF (CPF); 14 dígitos -> PJ (CNPJ)."""
    ...

def evaluate_customer_identification(
    contact_data: dict[str, Any] | None,
    line_metadata: dict[str, Any] | None = None,
) -> IdentificationStatus:
    """Executa os passos 1 e 2 da heurística de identificação."""
    ...

async def update_crm_contact_tax_id(
    crm_url: str,
    crm_token: str,
    contact_id: str,
    tax_id: str,
    classification: CustomerClassification,
) -> dict[str, Any]:
    """Persiste tax_id e type ('company' ou 'person') no CRM."""
    ...
```

### 3.3. Ferramenta ADK (Tool)

```python
async def save_customer_identification(
    ctx: ToolContext,
    tax_id: str,
) -> dict[str, Any]:
    """Salva a informação de CPF ou CNPJ confirmada pelo cliente no contato do CRM.
    
    Args:
        ctx: Contexto da ferramenta contendo a sessão.
        tax_id: Número de CPF (11 dígitos) ou CNPJ (14 dígitos) informado pelo cliente.
        
    Returns:
        Dicionário com o resultado da persistência e classificação atribuída.
    """
    ...
```

---

## 4. Critérios de Aceitação (Gherkin BDD)

### Cenário 1: Cliente cadastrado no CRM com CNPJ
- **Dado** uma mensagem recebida de um contato cujo cadastro no CRM possui `tax_id` com 14 dígitos válidos (CNPJ)
- **Quando** o agente processa a requisição através de `before_agent`
- **Então** o cliente é imediatamente classificado como `PJ`
- **E** `needs_confirmation` é definido como `False`
- **E** o agente prossegue diretamente com o atendimento sem solicitar documentos.

### Cenário 2: Cliente cadastrado no CRM classificado como Pessoa Jurídica
- **Dado** uma mensagem recebida de um contato cujo cadastro no CRM possui `type == 'company'`
- **Quando** a heurística do passo 1 é executada
- **Então** o cliente é identificado como `PJ` com `source == "crm_registration"`
- **E** o agente não solicita confirmação de documento.

### Cenário 3: Cliente sem CNPJ no cadastro, mas com CNPJ na linha telefônica
- **Dado** um contato cujo cadastro no CRM não possui CNPJ nem classificação `company`
- **Mas** os metadados da linha telefônica associada contêm registro de CNPJ da empresa titular
- **Quando** a heurística avalia o passo 2
- **Então** o cliente é classificado como `PJ` com `source == "phone_line"`
- **E** o CNPJ e o tipo `company` são sincronizados no cadastro do contato no CRM
- **E** `needs_confirmation` é definido como `False`.

### Cenário 4: Ambas as fontes ausentes — solicitação ativa de CPF ou CNPJ
- **Dado** um contato sem CNPJ/classificação no cadastro e sem dados de CNPJ na linha telefônica
- **Quando** o agente inicia o turno conversacional
- **Então** o agente é instruído a solicitar cordialmente que o cliente informe seu CNPJ ou CPF
- **E** `needs_confirmation` permanece `True`.

### Cenário 5: Cliente confirma CNPJ (14 dígitos)
- **Dado** que o cliente forneceu um CNPJ ("12.345.678/0001-90" ou "12345678000190")
- **Quando** o agente invoca `save_customer_identification`
- **Então** o documento é sanitizado para 14 dígitos numéricos
- **E** o contato é atualizado no CRM com `tax_id` sanitizado e `type = 'company'`
- **E** a sessão é atualizada com `classification = 'PJ'` e `needs_confirmation = False`
- **E** o agente agradece e continua com o atendimento específico para PJ.

### Cenário 6: Cliente confirma CPF (11 dígitos)
- **Dado** que o cliente forneceu um CPF ("123.456.789-00" ou "12345678900")
- **Quando** o agente invoca `save_customer_identification`
- **Então** o documento é sanitizado para 11 dígitos numéricos
- **E** o contato é atualizado no CRM com `tax_id` sanitizado e `type = 'person'`
- **E** a sessão é atualizada com `classification = 'PF'` e `needs_confirmation = False`
- **E** o agente segue com o atendimento para consumidor pessoa física.

### Cenário 7: Documento com formato inválido
- **Dado** que o cliente digitou uma sequência com quantidade incorreta de dígitos (ex: 8 dígitos)
- **Quando** `save_customer_identification` é acionado
- **Então** a ferramenta retorna status de erro indicando formato inválido
- **E** o agente solicita gentilmente a correção sem interromper a sessão.

---

## 5. Plano de Rollout e Compatibilidade

- **SemVer:** Minor bump em `anero-cafe-support` (`0.2.0`).
- **Arquitetura 12-Factor:** Parâmetros de CRM (`CRM_URL`, `CRM_TOKEN`) lidos de variáveis de ambiente já existentes.
- **Isolamento e Qualidade:**
  - Formatação e linting validados via `just verify` (pyright, ruff, isort, import-linter, pytest).
  - TDD obrigatório para todos os cenários da heurística.
  - Docstrings no padrão Google com prefixo `Business Rule:` nos testes.
