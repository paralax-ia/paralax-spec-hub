---
spec_id: SPEC-012
title: "Identificação de Linha PJ/PF, Roteamento Multi-Agente e Regras de Precificação e Pedidos via paralax-evo-crm"
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

# SPEC-012: Identificação de Linha PJ/PF, Roteamento Multi-Agente e Regras de Precificação e Pedidos via `paralax-evo-crm`

> **Product:** [`anero-cafe-support`](../products/anero-cafe-support.yaml) | [`paralax-platform`](../products/paralax-platform.yaml)  
> **Business Capability:** [`customer-relationship-management`](../capabilities/customer-relationship-management/capability.yaml)  
> **Scope:** Platform / Multi-repo (Onda 1: SDK `paralax-evo-crm`; Onda 2: Agente `anero-cafe-support`)  
> **Bounded Context:** CRM (Supporting Subdomain) / Identificação e Gestão de Contatos  
> **Status:** DRAFT (Aguardando Aprovação)  
> **Autor:** Antigravity & Eduardo F. Santos  
> **Data de Atualização:** 2026-11-09  

---

## 1. Contexto e Motivação

O atendimento digital do **Anero Café** opera com fluxos diferenciados para pessoas físicas e empresas, segmentando os contatos a partir da titularidade da linha e do perfil de compra no CRM Core (`evo-ai-crm-community`).

### 1.1. Heurística de Entrada e Classificação da Linha:
Quando a linha manda mensagem, a biblioteca `paralax-evo-crm` executa a seguinte sequência:
1. **Verificação de Cadastro no CRM:**
   - Verifica se a linha/telefone já possui contato cadastrado no CRM (`crm_api.get_contact_by_phone`).
   - Se cadastrada, verifica se possui CPF ou CNPJ registrado (`tax_id` ou atributos).
2. **Identificação de "CNPJ Cadastrado":**
   - Se existir contato previamente cadastrado do tipo CNPJ (ex: `tax_id` com 14 dígitos ou `type == 'company'`), identifica o interlocutor como **CNPJ Cadastrado**.
3. **Identificação pela Linha Telefônica ("CNPJ Não Cadastrado"):**
   - Caso NÃO seja um CNPJ cadastrado (ou seja uma nova linha, ou cadastrada como CPF/sem documento):
   - Tenta descobrir pela linha se existe um CNPJ vinculado (metadados do canal, WhatsApp Business Profile, cadastro da operadora).
   - Em caso positivo: identifica a linha como **CNPJ Não Cadastrado**.
   - Em caso negativo: identifica como **Atendimento Normal (Pessoa Física / Não Identificado)**.

---

## 2. Arquitetura e Regras de Negócio dos Três Agentes

```
                       ┌─────────────────────────────────────────┐
                       │      Mensagem Recebida da Linha         │
                       └────────────────────┬────────────────────┘
                                            │
                                            ▼
                       ┌─────────────────────────────────────────┐
                       │  Classificação da Linha (paralax-crm)   │
                       │   • Linha cadastrada no CRM?            │
                       │   • Possui CPF ou CNPJ?                 │
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
                 │                         │ │                         │
                 │ • NÃO MOSTRA PREÇO EM   │ │ • MOSTRA PREÇOS DO SITE │
                 │   NENHUMA HIPÓTESE      │ │ • Aceita pedidos com    │
                 │ • Consulta catálogo     │ │   base nesses preços    │
                 │ • Aceita pedidos apenas │ └────────────┬────────────┘
                 └─────────────────────────┘              │
                                                          │ Durante a conversa identifica
                                                          │ que usuário se trata de empresa
                                                          │ (ex: pedido B2B, cotação corporativa)
                                                          ▼
                                             ┌─────────────────────────┐
                                             │        AGENTE 3         │
                                             │   Empresa Identificada  │
                                             │  (Coleta & Qualificação)│
                                             │                         │
                                             │ • NÃO MOSTRA PREÇO      │
                                             │ • Informa que o pedido  │
                                             │   será analisado        │
                                             │ • Cadastro PJ requer    │
                                             │   APROVAÇÃO MANUAL 👤   │
                                             └─────────────────────────┘
```

### 2.1. Regras Específicas de Precificação e Pedidos por Agente:

| Agente | Perfil / Momento | Regra de Exibição de Preços | Regra de Solicitação de Pedidos |
|---|---|---|---|
| **Agente 1** (`B2BCadastradoAgent`) | Clientes previamente cadastrados como CNPJ | **NÃO MOSTRA PREÇO EM NENHUMA HIPÓTESE.** Consulta o catálogo e descreve produtos normalmente (origens, notas sensoriais, grãos, moagens), mas oculta qualquer valor monetário. | **Aceita solicitações de pedidos apenas.** Registra os itens e quantidades para processamento pelo faturamento corporativo no CRM. |
| **Agente 2** (`AtendimentoNormalAgent`) | Consumidores em geral / Pessoa Física | **MOSTRA OS PREÇOS DO SITE.** Utiliza ferramentas de catálogo para informar valores vigentes da cafeteria física e do e-commerce. | **Permite solicitações de pedidos com base no preço exibido.** Conduz pedidos de varejo direto para consumidores finais. |
| **Agente 3** (`LeadB2BQualificacaoAgent`) | Empresa identificada durante o atendimento normal | **NÃO MOSTRA PREÇO.** Informa com clareza ao cliente corporativo que os valores e condições serão definidos sob medida. | **Informa que o pedido e o cadastro serão analisados.** Registra o pedido como solicitação comercial para **aprovação manual** da equipe humana. |

---

## 3. Modelo de Dados do CRM e Integração via `paralax-evo-crm`

A integração respeita a integridade do CRM Core (`evo-ai-crm-community`):

1. **`Contact` (tabela `contacts`):**
   - Agente 1 atende contatos cujo `type == 'company'` e possuem `tax_id` de 14 dígitos (CNPJ).
   - Agente 2 atende contatos onde `type == 'person'` ou não identificados.
   - Agente 3 não altera o contato para `company` de forma autônoma; o contato permanece como `lead` até que o operador humano aprove o cadastro.
2. **Pipeline de Oportunidades (`pipeline_items` e `pipelines`):**
   - O Agente 1 registra pedidos B2B de clientes cadastrados no pipeline de pedidos corporativos.
   - O Agente 3 registra solicitações B2B no pipeline de "Aprovação Cadastral e Pedidos B2B" com notas detalhando os produtos de interesse e dados da empresa.
3. **Catálogo e Consulta de Produtos:**
   - Ferramenta `coffee_search` adaptada: nos Agentes 1 e 3, a formatação de retorno da ferramenta omite campos de preço antes da entrega ao LLM, garantindo defesa em profundidade (defense-in-depth) contra vazamento acidental de preços pelo modelo.

---

## 4. Planejamento em Ondas Topológicas

### 🌊 Onda 1: `paralax-ia/paralax-evo-crm` (SDK)
- **Modelos Pydantic (`paralax/evo/crm/models.py`):**
  - `ContactClassificationStatus`: `"CNPJ_CADASTRADO"`, `"CNPJ_NAO_CADASTRADO"`, `"ATENDIMENTO_NORMAL"`.
  - `CompanyRegistrationRequest`: payload estruturado contendo `contact_id`, `conversation_id`, `cnpj`, `company_name`, `contact_name`, `items_requested`, `notes`.
  - `LineClassificationResult`: resultado consolidado da análise de entrada.
- **Métodos no `CRMAPIClient` (`paralax/evo/crm/client.py`):**
  - `get_contact_by_phone(phone_number: str) -> CRMContact | None`
  - `get_contact_sync(contact_id: str) -> CRMContact`
  - `classify_incoming_line(phone_number: str, line_metadata: dict | None) -> LineClassificationResult`
  - `submit_company_registration_request(request: CompanyRegistrationRequest) -> PipelineItem`: registra a solicitação corporativa no pipeline de aprovação manual com tags e campos customizados, sem efetivar a alteração de tipo no contato.
- **Testes Unitários:** Validação com TDD em `tests/paralax/evo/crm/test_client_contact.py`.
- **Release:** Publicação da versão `0.2.12` no Artifact Registry.

### 🌊 Onda 2: `paralax-ia/anero-cafe-support` (Agentes)
- **Atualização de Dependência:** Bump para `paralax-evo-crm>=0.2.12` e `uv sync`.
- **Implementação dos 3 Agentes (`anero_cafe/agents/`):**
  - `b2b_cadastrado_agent.py` (Agente 1): Prompt rigoroso proibindo exibição de preços + mascaramento de preços nas tools. Aceita apenas registro de pedidos corporativos.
  - `atendimento_normal_agent.py` (Agente 2): Exibe preços do site normalmente e aceita pedidos no preço tabelado. Detecta intenção de empresa e transfere para o Agente 3.
  - `lead_b2b_qualificacao_agent.py` (Agente 3): Proíbe exibição de preços, informa que o pedido e cadastro serão analisados e envia solicitação para aprovação manual.
- **Orquestrador de Entrada:** Roteia para Agente 1 se `CNPJ_CADASTRADO` ou Agente 2 nos demais casos.
- **Testes Unitários:** Cobertura estrita com TDD de todas as regras de precificação e pedidos.

---

## 5. Critérios de Aceitação (Gherkin BDD)

- **Cenário 1: Agente 1 — Proibição Estrita de Preço e Aceite de Pedido**
  - **Dado** cliente corporativo cadastrado (CNPJ Cadastrado) em atendimento com o **Agente 1**
  - **Quando** o cliente consulta o catálogo de cafés e solicita o valor de um pacote de grãos
  - **Então** o Agente 1 descreve os cafés normalmente (notas sensoriais, método, torra), mas **NÃO informa o preço em nenhuma hipótese**
  - **E** aceita a solicitação de pedido corporativo registrando quantidades e itens para faturamento posterior.

- **Cenário 2: Agente 2 — Exibição de Preços do Site e Pedidos de Varejo**
  - **Dado** consumidor final ou novo cliente em atendimento com o **Agente 2**
  - **Quando** o cliente consulta os produtos do cardápio
  - **Então** o Agente 2 **informa os preços públicos do site**
  - **E** permite solicitações de pedido com base nesse preço.

- **Cenário 3: Agente 3 — Omissão de Preço e Aviso de Análise Manual**
  - **Dado** empresa identificada durante o atendimento normal, transferida para o **Agente 3**
  - **Quando** o cliente solicita cotação ou faz pedido corporativo
  - **Então** o Agente 3 **NÃO mostra preços**
  - **E** informa que a solicitação de pedido e o cadastro corporativo **serão analisados manualmente** pela equipe comercial/financeira
  - **E** registra a solicitação no CRM para aprovação manual humana.
