---
spec_id: SPEC-012
title: "Identificação de Linha PJ/PF, Roteamento Multi-Agente e Fluxo B2B com Aprovação Manual via paralax-evo-crm"
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

# SPEC-012: Identificação de Linha PJ/PF, Roteamento Multi-Agente e Fluxo B2B com Aprovação Manual via `paralax-evo-crm`

> **Product:** [`anero-cafe-support`](../products/anero-cafe-support.yaml) | [`paralax-platform`](../products/paralax-platform.yaml)  
> **Business Capability:** [`customer-relationship-management`](../capabilities/customer-relationship-management/capability.yaml)  
> **Scope:** Platform / Multi-repo (Onda 1: SDK `paralax-evo-crm`; Onda 2: Agente `anero-cafe-support`)  
> **Bounded Context:** CRM (Supporting Subdomain) / Identificação e Gestão de Contatos  
> **Status:** DRAFT (Aguardando Aprovação)  
> **Autor:** Antigravity & Eduardo F. Santos  
> **Data de Atualização:** 2026-11-09  
> **Regra Crítica de Negócio:** **O Agente 3 NÃO cadastra a empresa de forma autônoma; o cadastro corporativo exige obrigatoriamente aprovação manual humana.**

---

## 1. Contexto e Motivação

O atendimento digital do **Anero Café** precisa segmentar seus fluxos de atendimento com base na titularidade da linha e no perfil do interlocutor, roteando para **três agentes especializados de IA** a partir da identificação no CRM e metadados de canal.

### 1.1. Heurística de Entrada e Classificação da Linha:
Quando a linha manda mensagem, o sistema executa a seguinte sequência:
1. **Verificação de Cadastro no CRM:**
   - Verifica se a linha/telefone já possui contato cadastrado no CRM (`crm_api.get_contact_by_phone`).
   - Se cadastrada, verifica se possui CPF ou CNPJ registrado (`tax_id` ou atributos).
2. **Identificação de "CNPJ Cadastrado":**
   - Se existir contato previamente aprovado/cadastrado do tipo CNPJ (ex: `tax_id` com 14 dígitos ou `type == 'company'`), identifica o interlocutor como **CNPJ Cadastrado**.
3. **Identificação pela Linha Telefônica ("CNPJ Não Cadastrado"):**
   - Caso NÃO seja um CNPJ cadastrado (ou seja uma nova linha, ou cadastrada como CPF/sem documento):
   - Tenta descobrir pela linha se existe um CNPJ vinculado (metadados do canal, WhatsApp Business Profile, cadastro da operadora).
   - Em caso positivo: identifica a linha como **CNPJ Não Cadastrado**.
   - Em caso negativo: identifica como **Atendimento Normal (Pessoa Física / Não Identificado)**.

---

## 2. Arquitetura dos Três Agentes de IA

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
                 │  • Pedidos corporativos │ └────────────┬────────────┘
                 │  • Faturamento B2B      │              │
                 │  • Tabela PJ cadastrada │              │ Durante a conversa identifica
                 └─────────────────────────┘              │ que usuário se trata de empresa
                                                          │ (ex: pedido B2B, cotação corporativa)
                                                          ▼
                                             ┌─────────────────────────┐
                                             │        AGENTE 3         │
                                             │   Empresa Identificada  │
                                             │  (Coleta & Qualificação)│
                                             │  • Coleta CNPJ e dados  │
                                             │  • Registra solicitação │
                                             │  • NÃO cadastra direto  │
                                             │  • APROVAÇÃO MANUAL 👤 │
                                             └─────────────────────────┘
```

### Detalhamento dos Três Agentes:

1. **Agente 1 — Clientes Cadastrados CNPJ (`B2BCadastradoAgent`):**
   - **Gatilho de Ativação:** Linha reconhecida como **"CNPJ Cadastrado"** logo na entrada.
   - **Escopo:** Atendimento prioritário e direto a empresas que já passaram pelo fluxo de aprovação e já estão cadastradas no CRM (recorrência de grãos corporativos, contratos de comodato/locação de máquinas espresso, faturamento e segundas vias).
2. **Agente 2 — Atendimento Normal (`AtendimentoNormalAgent`):**
   - **Gatilho de Ativação:** Entrada inicial de todos os demais contatos (Pessoas Físicas, novos clientes, e linhas com "CNPJ Não Cadastrado" que ainda não entraram em fluxo corporativo).
   - **Escopo:** Informações sobre o menu, horário da cafeteria física, métodos de preparo, cafés especiais para consumo próprio e reservas.
   - **Sensor Conversacional:** Se durante o diálogo o usuário solicitar condições para empresas, compras corporativas ou confirmar que fala em nome de uma pessoa jurídica, realiza o **handoff interno para o Agente 3**.
3. **Agente 3 — Empresa Identificada Durante a Conversa (`LeadB2BQualificacaoAgent`):**
   - **Gatilho de Ativação:** Ativado **somente quando, durante a conversa, o Atendimento Normal identificar que o usuário se trata de uma empresa**.
   - **Escopo:**
     - Qualifica a demanda corporativa (volume de consumo, número de colaboradores, interesse em grãos ou máquinas).
     - Solicita cordialmente as informações da empresa (CNPJ, Razão Social/Nome da Empresa, Nome do Responsável).
     - Registra a solicitação de cadastro corporativo no CRM via biblioteca `paralax-evo-crm` (criando card de oportunidade na etapa de **"Aprovação Cadastral PJ"** no pipeline de vendas com notas e campos customizados).
   - **REGRA CRÍTICA INEGOCIÁVEL (APROVAÇÃO MANUAL):**
     - **O Agente 3 NÃO tem permissão para cadastrar ou aprovar a empresa autonomamente no CRM como cliente PJ ativo.**
     - O Agente 3 informa com clareza e cordialidade ao cliente que a solicitação de abertura de conta PJ foi registrada com sucesso e que os dados foram encaminhados para a equipe comercial/financeira para **análise e aprovação cadastral manual**.

---

## 3. Modelo de Dados do CRM e Integração via `paralax-evo-crm`

A integração respeita a integridade do CRM Core (`evo-ai-crm-community`):

1. **`Contact` (tabela `contacts`):**
   - Durante a fase de qualificação pelo Agente 3, o contato permanece com `type = 'person'` e `contact_type = 'lead'` (não é alterado para `company` nem vira `customer` automaticamente).
2. **Pipeline de Aprovação (`pipeline_items` e `pipelines`):**
   - O Agente 3 invoca `crm_api.ensure_conversation_in_pipeline` e `crm_api.create_pipeline_item` / atualiza campos customizados (`cnpj_solicitado`, `razao_social`, `demanda_estimada`), posicionando o card na etapa de **"Aprovação Cadastral Manual"**.
3. **Aprovação Manual pelo Operador Humano:**
   - O operador comercial/financeiro valida os documentos do CNPJ no CRM e, manualmente, converte o contato em `company` e aprova a conta corporativa.

---

## 4. Planejamento em Ondas Topológicas

### 🌊 Onda 1: `paralax-ia/paralax-evo-crm` (SDK)
- **Modelos Pydantic (`paralax/evo/crm/models.py`):**
  - `ContactClassificationStatus`: `"CNPJ_CADASTRADO"`, `"CNPJ_NAO_CADASTRADO"`, `"ATENDIMENTO_NORMAL"`.
  - `CompanyRegistrationRequest`: payload estruturado contendo `contact_id`, `conversation_id`, `cnpj`, `company_name`, `contact_name`, `notes`.
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
  - `b2b_cadastrado_agent.py` (Agente 1)
  - `atendimento_normal_agent.py` (Agente 2 - com detecção e handoff de intenção corporativa)
  - `lead_b2b_qualificacao_agent.py` (Agente 3 - com tool `solicitar_cadastro_pj` para aprovação manual)
- **Orquestrador de Entrada:** Roteia para Agente 1 se `CNPJ_CADASTRADO` ou Agente 2 nos demais casos.
- **Testes Unitários:** Cobertura de todos os cenários com TDD.

---

## 5. Critérios de Aceitação (Gherkin BDD)

- **Cenário 1: Entrada com CNPJ Cadastrado**
  - **Dado** mensagem de linha com CNPJ já cadastrado e aprovado no CRM
  - **Quando** a linha é classificada na entrada
  - **Então** ativa diretamente o **Agente 1 (Clientes Cadastrados CNPJ)**.

- **Cenário 2: Entrada Normal / CNPJ Não Cadastrado**
  - **Dado** mensagem de nova linha ou linha com CNPJ detectado mas ainda não cadastrado no CRM
  - **Quando** a linha é classificada na entrada
  - **Então** ativa o **Agente 2 (Atendimento Normal)**.

- **Cenário 3: Ativação do Agente 3 Durante o Atendimento Normal**
  - **Dado** cliente interagindo com o **Agente 2 (Atendimento Normal)**
  - **Quando** o cliente declara interesse corporativo (ex: "gostaria de cotação para o escritório da minha empresa")
  - **Então** o Agente 2 ativa o **Agente 3 (Empresa Identificada / Qualificação)**.

- **Cenário 4: Agente 3 Coleta Dados e Registra para Aprovação Manual (Sem Cadastro Direto)**
  - **Dado** o **Agente 3** em atendimento
  - **Quando** o cliente fornece o CNPJ ("12.345.678/0001-90") e nome da empresa
  - **Então** o Agente 3 invoca `crm_api.submit_company_registration_request`
  - **E** um card de lead é registrado no pipeline para aprovação manual
  - **E** o contato NÃO é convertido automaticamente para `type = 'company'`
  - **E** o Agente 3 informa cordialmente ao cliente que a solicitação foi enviada para análise e aprovação manual da equipe comercial.
