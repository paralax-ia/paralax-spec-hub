---
spec_id: SPEC-012
title: "Identificação de Linha PJ/PF, Roteamento Multi-Agente e Regras de Precificação e Notificação de Pedidos"
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
    prompts:
      - anero_cafe/instruction
      - anero_cafe/b2b_cadastrado
      - anero_cafe/lead_b2b_qualificacao
prompts:
  - anero_cafe/instruction
  - anero_cafe/b2b_cadastrado
  - anero_cafe/lead_b2b_qualificacao
status: DRAFT
---

# SPEC-012: Identificação de Linha PJ/PF, Roteamento Multi-Agente e Regras de Precificação e Notificação de Pedidos

> **Product:** [`anero-cafe-support`](../products/anero-cafe-support.yaml) | [`paralax-platform`](../products/paralax-platform.yaml)  
> **Business Capability:** [`customer-relationship-management`](../capabilities/customer-relationship-management/capability.yaml)  
> **Scope:** Platform / Multi-repo (Onda 1: SDK `paralax-evo-crm`; Onda 2: Agente `anero-cafe-support`)  
> **Bounded Context:** CRM (Supporting Subdomain) / Identificação e Gestão de Contatos  
> **Status:** DRAFT (Aprovado / Em Implementação)  
> **Autor:** Antigravity & Eduardo F. Santos  
> **Data de Atualização:** 2026-11-10  

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
                                             │    PJ Não Cadastrado    │
                                             │ (Catálogo & Notificação)│
                                             │                         │
                                             │ • NÃO MOSTRA PREÇO      │
                                             │ • Busca no catálogo     │
                                             │ • Coleta dados e pedido │
                                             │ • Envia NOTIFICAÇÃO ao  │
                                             │   dono da Anero 📲       │
                                             └─────────────────────────┘
```

### 2.1. Regras Específicas de Precificação e Pedidos por Agente:

| Agente | Perfil / Momento | Regra de Exibição de Preços | Regra de Solicitação de Pedidos / Notificação |
|---|---|---|---|
| **Agente 1** (`B2BCadastradoAgent`) | Clientes previamente cadastrados como CNPJ | **NÃO MOSTRA PREÇO EM NENHUMA HIPÓTESE.** Consulta o catálogo e descreve produtos normalmente (origens, notas sensoriais, grãos, moagens), mas oculta qualquer valor monetário. | **Aceita solicitações de pedidos apenas.** Registra os itens e quantidades para processamento pelo faturamento corporativo no CRM. |
| **Agente 2** (`AtendimentoNormalAgent`) | Consumidores em geral / Pessoa Física | **MOSTRA OS PREÇOS DO SITE.** Utiliza ferramentas de catálogo para informar valores vigentes da cafeteria física e do e-commerce. | **Permite solicitações de pedidos com base no preço exibido.** Conduz pedidos de varejo direto para consumidores finais. |
| **Agente 3** (`LeadB2BQualificacaoAgent`) | Empresa identificada / PJ não cadastrado | **NÃO MOSTRA PREÇO.** Realiza o ciclo de busca no catálogo normalmente sem exibir valores monetários. | **Notificação Direta ao Dono da Anero.** Não utiliza pipeline nem envio para aprovação cadastral de CNPJ no CRM. Ao final da interação, envia notificação completa para o dono da Anero com os dados da empresa e o pedido. |

### 2.2. Governança de Prompts e Ciclo de Vida no Langfuse (Draft -> Sync -> Produção)

1. **Regra de Prompts de Sistema em Inglês:**
   - Todos os prompts de sistema de todos os agentes (`INSTRUCTION`, `INSTRUCTION_ATENDIMENTO_NORMAL`, `INSTRUCTION_B2B_CADASTRADO`, `INSTRUCTION_LEAD_B2B_QUALIFICACAO`) devem ser **estritamente escritos em inglês** (personas, restrições, seções XML, descrições de ferramentas e regras operacionais).
   - O agente mantém a restrição obrigatória de comunicação com o usuário final em Português do Brasil: `**CRITICAL LANGUAGE RESTRICTION:** You MUST communicate with the user EXCLUSIVELY in Portuguese (PT-BR)`.
2. **Resolução Dinâmica via `DynamicPromptManager`:**
   - Cada um dos 3 agentes possui gerenciador dinâmico de prompts (`anero_cafe/instruction`, `anero_cafe/b2b_cadastrado`, `anero_cafe/lead_b2b_qualificacao`), eliminando instruções congeladas em memória e viabilizando atualizações em tempo de execução sem reinicialização de contêineres.
3. **Ciclo de Vida no Langfuse via CLI Harness (SPEC-PROMPT-01):**
   - **Centralização no Harness:** O ciclo de vida e a governança de prompts no Langfuse são orquestrados centralmente pela CLI `harness` (`harness spec run` / sensor `PromptGovernanceSensor`), não residindo como scripts bespoke nos repositórios spoke.
   - **Fase de Desenvolvimento / Execução da Spec (Draft):**
     - Prompts declarados no frontmatter da spec (`prompts:`) alterados no repositório spoke são detectados e sincronizados automaticamente no Langfuse com a label `draft`.
     - Permite testes pontuais e iterações de engenharia de prompt sem impactar o tráfego produtivo.
   - **Fase Pós-Finalização da Spec (Promoção para Produção):**
     - Após a validação da esteira e aprovação do cross-repo gate (`harness spec finish` / gate closure), a CLI `harness` promove os prompts automaticamente para a label `production` no Langfuse.
     - A label ativa consumida pelo runtime dos agentes em produção permanece sendo `production` (`LANGFUSE_PROMPT_LABEL="production"`).

---

## 3. Modelo de Notificação e Abstração no CRM

A arquitetura desacopla a infraestrutura de mensageria da regra de negócio específica da linha, garantindo despacho determinístico pelo canal correto:

1. **Origem da Notificação e Descoberta Automática de Canal:**
   - Toda solicitação processada pelo agente provém obrigatoriamente de uma conversa ativa existente em um canal (`conversation_id`).
   - O canal (`inbox_id`) **NÃO é parametrizado em nenhuma hipótese**, garantindo que o agente utilize exatamente o mesmo canal de mensageria da conversa de entrada.
2. **Ciclo Completo de Notificação no SDK `paralax-evo-crm`:**
   - O método agnóstico `notify_phone` executa o ciclo completo de ponta a ponta:
     ```python
     async def notify_phone(
         self,
         phone_number: str,
         message: str,
         conversation_id: int | str,
     ) -> dict[str, Any]
     ```
   - **Passo 1 (Descoberta do Canal):** Consulta a conversa ativa (`GET /api/v1/conversations/{conversation_id}`) e extrai o `inbox_id`.
   - **Passo 2 (Contato do Destinatário):** Localiza o contato por telefone (`GET /api/v1/contacts/search?q={phone_number}`) ou cria um novo contato (`POST /api/v1/contacts`).
   - **Passo 3 (Criação da Conversa e Despacho no Canal):** Cria a conversa de saída na mesma `inbox_id` (`POST /api/v1/conversations`) com `{ "message": { "content": message, "message_type": "outgoing" } }`, acionando o provider de mensageria (ex: WhatsApp) daquela linha.
   - **Passo 4 (Auditoria Interna):** Registra uma nota interna privada na conversa de origem (`conversation_id`) para rastreabilidade dos atendentes humanos.
3. **Responsabilidade da Mensagem e Telefone do Dono no `anero-cafe-support`:**
   - A criação e formatação do texto da notificação (contendo CNPJ, Razão Social, Contato, Telefone, Itens do Pedido de Grãos/Café e Observações) residem no próprio agente do Anero Café.
   - O telefone de destino do proprietário é configurado exclusivamente via variável de ambiente (`OWNER_PHONE_NUMBER`), provida declarativamente nos manifestos do `argocd` (`argocd/prod/anero-cafe-support/patch-env.yaml`).
4. **Catálogo e Consulta de Produtos:**
   - Ferramenta de catálogo adaptada nos Agentes 1 e 3: omite campos de preço antes da entrega ao LLM (*defense-in-depth*).

---

## 4. Planejamento em Ondas Topológicas

### 🌊 Onda 1: `paralax-ia/paralax-evo-crm` (SDK Abstrato e Reutilizável)
- **Modelos Pydantic (`paralax/evo/crm/models.py`):**
  - `ContactClassificationStatus`: `"CNPJ_CADASTRADO"`, `"CNPJ_NAO_CADASTRADO"`, `"ATENDIMENTO_NORMAL"`.
  - `CustomerClassification`: `"PJ"`, `"PF"`, `"UNKNOWN"`.
  - `CRMContact`: modelos de contato com métodos de identificação fiscal (`is_company()`, `has_cnpj()`, `has_cpf()`).
  - `LineClassificationResult`: resultado consolidado da análise de entrada.
  - Utilitários: `sanitize_tax_id(tax_id)` e `validate_tax_id(tax_id)`.
- **Métodos no `CRMAPIClient` (`paralax/evo/crm/client.py`):**
  - `get_contact_by_phone(phone_number: str) -> CRMContact | None`
  - `get_contact(contact_id: int | str) -> CRMContact`
  - `get_contact_sync(contact_id: str) -> CRMContact`
  - `create_contact(name: str, phone_number: str) -> CRMContact`
  - `get_or_create_contact(phone_number: str, name: str | None) -> CRMContact`
  - `get_conversation(context_id: str) -> dict[str, Any]`
  - `create_conversation(inbox_id: int | str, contact_id: int | str, message: dict | None) -> dict[str, Any]`
  - `record_internal_note(conversation_id: int | str, content: str) -> dict[str, Any]`
  - `classify_incoming_line(phone_number: str, line_metadata: dict | None) -> LineClassificationResult`
  - `notify_phone(phone_number: str, message: str, conversation_id: int | str) -> dict[str, Any]`: executa o ciclo completo herdando o `inbox_id` da conversa ativa e despachando a mensagem de saída.
- **Testes Unitários:** Validação com TDD em `tests/paralax/evo/crm/test_client_contact.py`.
- **Release:** Publicação da versão `0.2.13` no Artifact Registry.

### 🌊 Onda 2: `paralax-ia/anero-cafe-support` (Agentes e Regra de Notificação B2B)
- **Configuração no ArgoCD (`argocd/prod/anero-cafe-support/patch-env.yaml`):** Injeção da variável de ambiente `OWNER_PHONE_NUMBER`.
- **Atualização de Dependência:** Bump declarativo para `paralax-evo-crm>=0.2.13` e `uv sync` oficial após publicação.
- **Formatação de Notificação e Tool no Agente da Anero:**
  - Definição do schema/modelo de notificação de pedido corporativo no próprio `anero-cafe-support`.
  - Formatação do texto da mensagem com os dados cadastrais da empresa e os itens solicitados.
  - Invocação de `client.notify_phone(phone_number=settings.owner_phone_number, message=formatted_text, conversation_id=current_conversation_id)`.
- **Implementação dos 3 Agentes (`anero_cafe/agents/` ou `anero_cafe/agent.py`):**
  - `b2b_cadastrado_agent.py` (Agente 1): Consulta catálogo sem preços, proíbe valores, aceita pedidos corporativos para faturamento.
  - `atendimento_normal_agent.py` (Agente 2): Mostra preços do site e aceita pedidos no preço tabelado. Detecta empresa e transfere para o Agente 3.
  - `lead_b2b_qualificacao_agent.py` (Agente 3): Busca no catálogo sem preços, coleta os dados da empresa e o pedido, formata a mensagem e aciona a notificação para o dono da Anero ao final.
- **Testes Unitários:** Cobertura rigorosa com TDD em `tests/unit/`.

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

- **Cenário 3: Agente 3 — PJ Não Cadastrado, Omissão de Preço e Notificação ao Dono**
  - **Dado** empresa identificada (PJ não cadastrado) em atendimento com o **Agente 3**
  - **Quando** o cliente navega pelo catálogo e solicita itens
  - **Então** o Agente 3 realiza o ciclo de busca de cafés normalmente, mas **NÃO mostra preços em nenhuma hipótese**
  - **E** ao final da interação, **envia uma notificação direta para o dono da Anero** contendo os dados da empresa (CNPJ, nome, contato) e os itens do pedido.
