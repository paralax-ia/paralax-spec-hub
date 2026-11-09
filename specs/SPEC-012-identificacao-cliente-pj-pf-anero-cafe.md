---
spec_id: SPEC-012
title: "Identificação de Linha PJ/PF, Roteamento Multi-Agente e Integração CRM via paralax-evo-crm"
product:
  - anero-cafe-support
  - paralax-platform
capability: customer-relationship-management
scope: platform
bounded_context: "CRM (Supporting Subdomain) / Identificação de Clientes & Orquestração Multi-Agente"
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

# SPEC-012: Identificação de Linha PJ/PF, Roteamento Multi-Agente e Integração CRM via `paralax-evo-crm`

> **Product:** [`anero-cafe-support`](../products/anero-cafe-support.yaml) | [`paralax-platform`](../products/paralax-platform.yaml)  
> **Business Capability:** [`customer-relationship-management`](../capabilities/customer-relationship-management/capability.yaml)  
> **Scope:** Platform / Multi-repo (Onda 1: SDK `paralax-evo-crm`; Onda 2: Agente `anero-cafe-support`)  
> **Bounded Context:** CRM (Supporting Subdomain) / Identificação e Gestão de Contatos  
> **Status:** DRAFT (Aguardando Aprovação)  
> **Autor:** Antigravity & Eduardo F. Santos  
> **Data de Criação:** 2026-11-09  
> **Repositórios Alvo:**  
> - `paralax-ia/paralax-evo-crm` (Onda 1 - SDK Client & Modelos)  
> - `paralax-ia/anero-cafe-support` (Onda 2 - Agentes Especializados & Orquestração)  

---

## 1. Contexto e Motivação

O atendimento digital do **Anero Café** precisa segmentar seus fluxos de atendimento com base na titularidade da linha e no perfil do interlocutor, roteando para **três agentes especializados de IA** a partir da identificação no CRM e metadados de canal.

### 1.1. Heurística de Entrada e Classificação da Linha:
Quando a linha manda mensagem, o sistema executa a seguinte sequência:
1. **Verificação de Cadastro no CRM:**
   - Verifica se a linha/contato está cadastrada no CRM (`crm_api.get_contact` / `get_contact_by_phone`).
   - Se cadastrada, verifica se possui CPF ou CNPJ registrado (`tax_id` ou atributos).
2. **Identificação de "CNPJ Cadastrado":**
   - Se existir contato do tipo CNPJ (ex: `tax_id` com 14 dígitos ou `type == 'company'`), identifica o interlocutor como **CNPJ Cadastrado**.
3. **Identificação pela Linha Telefônica ("CNPJ Não Cadastrado"):**
   - Caso NÃO seja um CNPJ cadastrado, tenta descobrir pela linha se existe um CNPJ vinculado (metadados do canal, WhatsApp Business Profile, cadastro da operadora).
   - Em caso positivo: identifica a linha como **CNPJ Não Cadastrado**.
   - Em caso negativo: identifica como **Atendimento Normal (Pessoa Física / Não Identificado)**.

---

## 2. Arquitetura dos Três Agentes de IA

A partir da classificação da linha e do fluxo conversacional, operam **três agentes especializados**:

```
                       ┌─────────────────────────────────────────┐
                       │      Mensagem Recebida da Linha         │
                       └────────────────────┬────────────────────┘
                                            │
                                            ▼
                       ┌─────────────────────────────────────────┐
                       │  Heurística de Linha (via paralax-crm)  │
                       │   • Está cadastrado no CRM?             │
                       │   • Tem CPF ou CNPJ?                    │
                       │   • Há CNPJ vinculado à linha?          │
                       └──────┬───────────────────────────┬──────┘
                              │                           │
          [CNPJ Cadastrado]   │                           │ [Demais Casos: Não Cadastrado
                              │                           │  ou Linha com CNPJ não cadastrado]
                              ▼                           ▼
                 ┌─────────────────────────┐ ┌─────────────────────────┐
                 │        AGENTE 1         │ │        AGENTE 2         │
                 │   Clientes Cadastrados  │ │   Atendimento Normal    │
                 │          CNPJ           │ │   (Pessoa Física/Menu)  │
                 │  • Pedidos corporativos │ └────────────┬────────────┘
                 │  • Faturamento B2B      │              │
                 │  • Tabela PJ cadastrada │              │ Durante a conversa identifica
                 └─────────────────────────┘              │ que usuário se trata de empresa
                                                          │ (ex: pedido B2B, confirmação CNPJ)
                                                          ▼
                                             ┌─────────────────────────┐
                                             │        AGENTE 3         │
                                             │   Empresa Identificada  │
                                             │   (Onboarding B2B)      │
                                             │  • Qualificação de lead │
                                             │  • Coleta/Valida CNPJ   │
                                             │  • Salva contato no CRM │
                                             └─────────────────────────┘
```

### Detalhamento dos Agentes:
1. **Agente 1 — Clientes Cadastrados CNPJ (`B2BCadastradoAgent`):**
   - **Gatilho de Ativação:** Linha reconhecida como **"CNPJ Cadastrado"** logo na entrada.
   - **Escopo:** Atendimento prioritário a empresas parceiras já registradas no CRM (recorrência de grãos corporativos, contratos de locação/comodato de máquinas de café espresso, emissão de segundas vias de nota fiscal e faturamento).
2. **Agente 2 — Atendimento Normal (`AtendimentoNormalAgent`):**
   - **Gatilho de Ativação:** Entrada inicial de todos os demais contatos (Pessoas Físicas, novos clientes, e linhas com "CNPJ Não Cadastrado" que ainda não entraram em fluxo corporativo).
   - **Escopo:** Informações sobre o menu, horário da cafeteria física, métodos de preparo, cafés especiais para consumo próprio e reservas.
   - **Capacidade Especial:** Sensor conversacional. Se durante o diálogo o usuário solicitar condições para empresas, compras corporativas, ou confirmar que fala em nome de uma pessoa jurídica, realiza o **handoff interno para o Agente 3**.
3. **Agente 3 — Empresa Identificada Durante a Conversa (`NovoLeadCorporativoAgent`):**
   - **Gatilho de Ativação:** Ativado **exclusivamente quando, durante a conversa, o Atendimento Normal identifica que o usuário se trata de uma empresa**.
   - **Escopo:** Condução do fluxo comercial B2B para novas empresas: apresenta condições para pessoa jurídica, solicita cordialmente a confirmação do CNPJ ou CPF para cadastro e aciona o SDK para persistir o novo CNPJ no CRM Core (`crm_api.update_contact_tax_id`).

---

## 3. Análise do Modelo de Dados do CRM Core (`evo-ai-crm-community`)

Toda a interação com o CRM baseia-se nas entidades reais do schema:

1. **`Contact` (tabela `contacts`):**
   - `id`: UUID (Primary Key).
   - `type`: `contact_type_enum` (`'person'`, `'company'`, `'group'`).
   - `tax_id`: `VARCHAR(14)` para CPF (11 dígitos) ou CNPJ (14 dígitos) sem máscara.
   - `phone_number`: Formato E.164 (ex: `+5511999999999`).
   - `additional_attributes` / `custom_attributes`: metadados e informações complementares da empresa.
2. **`ContactCompany` (tabela `contact_companies`):**
   - Vínculo M:N entre Pessoa Física (`type = 'person'`) e Empresa (`type = 'company'`).
3. **`ContactInbox` e `Channel::Whatsapp` (tabelas `contact_inboxes`, `channel_whatsapp`):**
   - Dados de canal, identificação do WhatsApp da linha e metadados de provedor.

---

## 4. Integração Obrigatória via Biblioteca `paralax-evo-crm` (Ondas Topológicas)

Nenhum agente fará chamadas HTTP diretas ou ad-hoc ao CRM. Todas as operações são delegadas à biblioteca compartilhada:

### 🌊 Onda 1: `paralax-ia/paralax-evo-crm` (SDK)
- **Modelos Pydantic (`paralax/evo/crm/models.py`):**
  - `ContactClassificationStatus(str, Enum)`: `"CNPJ_CADASTRADO"`, `"CNPJ_NAO_CADASTRADO"`, `"ATENDIMENTO_NORMAL"`.
  - `CRMContact`: Modelo com `id`, `name`, `type`, `tax_id`, `phone_number`, `companies`.
- **Métodos no `CRMAPIClient` (`paralax/evo/crm/client.py`):**
  - `get_contact_by_phone(phone_number: str) -> CRMContact | None`
  - `get_contact_sync(contact_id: str) -> CRMContact`
  - `classify_incoming_line(phone_number: str, line_metadata: dict | None = None) -> LineClassificationResult`
  - `update_contact_tax_id(contact_id: str, tax_id: str) -> CRMContact`
- **Release:** Publicação da versão `0.2.12` no Artifact Registry.

### 🌊 Onda 2: `paralax-ia/anero-cafe-support` (Agentes)
- **Atualização de Dependência:** `paralax-evo-crm>=0.2.12` via `uv sync`.
- **Agentes Especializados (`anero_cafe/agents/`):**
  - `b2b_cadastrado_agent.py` (Agente 1)
  - `atendimento_normal_agent.py` (Agente 2)
  - `empresa_onboarding_agent.py` (Agente 3)
- **Orquestrador / Router ADK:**
  - Avalia a classificação da linha no início do ciclo via `crm_api.classify_incoming_line`.
  - Direciona para o Agente 1 se `CNPJ_CADASTRADO`, ou para o Agente 2 nos demais casos.
  - Suporta delegação / sub-agent transfer para o Agente 3 quando o Agente 2 detecta intenção corporativa.

---

## 5. Critérios de Aceitação (Gherkin BDD)

- **Cenário 1: Mensagem de Linha com CNPJ Cadastrado**
  - **Dado** mensagem recebida de linha vinculada a contato no CRM com `tax_id` de 14 dígitos ou `type == 'company'`
  - **Quando** o roteador avalia a linha via `crm_api`
  - **Então** classifica como `CNPJ_CADASTRADO`
  - **E** a sessão é atendida diretamente pelo **Agente 1 (Clientes Cadastrados CNPJ)**.

- **Cenário 2: Mensagem de Linha com CNPJ Não Cadastrado**
  - **Dado** mensagem de linha não cadastrada com CNPJ no CRM, mas cujos metadados de canal (WhatsApp Business) indicam CNPJ
  - **Quando** o roteador avalia a linha
  - **Então** classifica como `CNPJ_NAO_CADASTRADO`
  - **E** inicia o diálogo pelo **Agente 2 (Atendimento Normal)** mantendo o contexto de empresa potencial.

- **Cenário 3: Atendimento Normal Identifica Empresa Durante a Conversa**
  - **Dado** conversa em andamento com o **Agente 2 (Atendimento Normal)**
  - **Quando** o cliente solicita orçamento para escritório ou indica ser empresa
  - **Então** o Agente 2 aciona a transição para o **Agente 3 (Empresa Identificada / Onboarding B2B)**.

- **Cenário 4: Agente 3 Coleta e Persiste CNPJ no CRM**
  - **Dado** o **Agente 3** em atendimento
  - **Quando** o cliente confirma o número do CNPJ
  - **Então** o Agente 3 invoca `crm_api.update_contact_tax_id` através da SDK
  - **E** o CRM atualiza o contato com `type = 'company'` e o `tax_id` sanitizado de 14 dígitos.
