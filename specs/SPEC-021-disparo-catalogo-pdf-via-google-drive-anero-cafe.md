---
spec_id: SPEC-021
title: "Disparo de Catálogo em PDF como Anexo via Google Drive e Fluxo Conversacional de Cardápio no Anero Café"
product:
  - anero-cafe-support
  - paralax-platform
capability: conversational-ai-agent
scope: single-repo
bounded_context: "Conversational Agent / Canais & Envio de Documentos"
origin_module: anero-cafe-support
target_repositories:
  - repo: paralax-ia/anero-cafe-support
    wave: 1
    role: ai-agent
    prompts:
      - anero_cafe/instruction
      - anero_cafe/atendimento_normal
  - repo: paralax-ia/argocd
    wave: 2
    role: gitops
prompts:
  - name: anero_cafe/instruction
    target_repo: paralax-ia/anero-cafe-support
    file: anero_cafe/prompts.py
    symbol: INSTRUCTION
    description: "System instructions for Anero Cafe agent with PDF catalog attachment dispatch and fixed conversational flow"
  - name: anero_cafe/atendimento_normal
    target_repo: paralax-ia/anero-cafe-support
    file: anero_cafe/prompts.py
    symbol: INSTRUCTION_ATENDIMENTO_NORMAL
    description: "Retail conversational prompt for Anero Cafe normal attendance with deterministic PDF catalog attachment dispatch"
status: APPROVED
---

# SPEC-021: Disparo de Catálogo em PDF como Anexo via Google Drive e Fluxo Conversacional de Cardápio no Anero Café

> **Product:** [`anero-cafe-support`](../products/anero-cafe-support.yaml) | [`paralax-platform`](../products/paralax-platform.yaml)  
> **Business Capability:** [`conversational-ai-agent`](../capabilities/conversational-ai-agent/capability.yaml)  
> **Scope:** Agente de IA (`anero-cafe-support`) e GitOps (`argocd`)  
> **Bounded Context:** Conversational Agent / Canais & Envio de Documentos  
> **Status:** APPROVED  
> **Autor:** Eduardo F. Santos  
> **Data de Criação:** 2026-11-26  
> **Data de Atualização:** 2026-11-27  
> **Parent Spec:** [`SPEC-016`](./SPEC-016-integracao-google-drive-conhecimento-agentes.md) (Infraestrutura de leitura do Google Drive)  
> **Arquitetura 12-Factor:** O catálogo reside no Google Drive sob o ID `GOOGLE_DRIVE_CATALOG_PDF_FILE_ID` injetado via variáveis de ambiente centralizadas no ArgoCD. O arquivo deve ser entregue na conversa do WhatsApp como **anexo nativo de documento (PDF)**, e não como link externo de navegação do Google Drive.  

---

## 1. Contexto e Motivação

Durante o primeiro contato com a torrefação **Anero Café** no WhatsApp oficial, grande parte dos clientes pergunta de forma aberta sobre:
- Os cafés disponíveis;
- Preços dos cafés e tabelas de valor;
- Catálogo de produtos e cardápio geral.

Na arquitetura anterior (estabelecida pela **SPEC-018**), a resposta era gerada por meio de templates Jinja2 que montavam cards de texto com todos os cafés cadastrados. Embora tenha resolvido o problema de fatiamento indevido no WhatsApp, a listagem completa em texto ainda gera mensagens muito extensas e sobrecarregadas de informação para clientes que desejam apenas folhear o portfólio visual da cafeteria.

A cafeteria possui um **catálogo oficial diagramado em formato PDF**, mantido e atualizado de forma centralizada em uma pasta do **Google Drive**.

> [!IMPORTANT]
> **Diretriz de Negócio Obrigatória:**  
> **Não é para enviar o link do Google Drive para o cliente**, e sim **enviar o arquivo PDF como anexo** diretamente na conversa do WhatsApp. Links externos de Drive geram atrito na experiência, exigem login ou saída do aplicativo de mensagens, enquanto o arquivo PDF enviado como anexo nativo permite abertura, leitura e download imediatos dentro do próprio WhatsApp.

Esta especificação define:
1. Uma **ferramenta (tool)** no agente `anero-cafe-support` (`send_catalog_pdf`) para disparar o catálogo em PDF diagramado como **documento/anexo nativo**.
2. Aderência estrita ao **12-Factor**: o agente consome declarativamente a variável de ambiente `GOOGLE_DRIVE_CATALOG_PDF_FILE_ID` sem credenciais ou IDs arbitrários fixados em código.
3. O fluxo conversacional determinístico de atendimento (Tríade Determinística):
   - Mensagem inicial: `"Deixa eu te mandar o nosso catálogo aqui"`
   - Disparo do **PDF do catálogo como anexo** na conversa (via ferramenta `send_catalog_pdf`).
   - Mensagem de fechamento: `"Dá uma olhada, eu tiro suas dúvidas e a gente monta o seu pedido"`
4. A manutenção das ferramentas de consulta pontual (`coffee_search`, `get_coffee_details`) para sanar dúvidas específicas (notas sensoriais, torra, moagens) após o cliente consultar o PDF anexo.

---

## 2. Escopo e Repositórios Afetados (Ondas Topológicas)

- [x] **Sub-tarefa 1 (`paralax-ia/anero-cafe-support`):** [Onda 1] Implementação da tool `send_catalog_pdf`, atualização dos prompts governados no Langfuse e suíte de testes unitários com TDD. [PR #48](https://github.com/paralax-ia/anero-cafe-support/pull/48) / [PR #49](https://github.com/paralax-ia/anero-cafe-support/pull/49)
- [x] **Sub-tarefa 2 (`paralax-ia/argocd`):** [Onda 2] Declaração declarativa 12-Factor da variável `GOOGLE_DRIVE_CATALOG_PDF_FILE_ID: "1ORQJaJjceD9DqU4ZLR_jAOqtrR9vGWlB"` no overlay `prod/anero-cafe-support` (`patch-env.yaml`). [PR #33](https://github.com/paralax-ia/argocd/pull/33)

```
┌────────────────────────────────────────────────────────────────────────┐
│                        ONDA 1: AGENTE DE IA                            │
│                    paralax-ia/anero-cafe-support                       │
│  • Tool `send_catalog_pdf` (dispara PDF como anexo nativo)             │
│  • Consumo 12-Factor de `GOOGLE_DRIVE_CATALOG_PDF_FILE_ID`             │
│  • Prompts governados: `anero_cafe/instruction` e `atendimento_normal` │
│  • Testes TDD com docstrings `Business Rule:`                          │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                          ONDA 2: GITOPS                                │
│                         paralax-ia/argocd                              │
│  • Injeção de `GOOGLE_DRIVE_CATALOG_PDF_FILE_ID` no overlay de prod     │
│  • Permissão Leitor para a Service Account do agente no Google Drive   │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Contratos de Arquitetura e Engenharia

### 3.1. Viabilidade Técnica e Mecanismo de Disparo do PDF como Anexo

1. **Repositório Central no Google Drive (SSOT):**
   - O arquivo PDF do catálogo oficial diagramado é mantido e editado pela equipe no Google Drive.
   - O ID do arquivo no Google Drive é injetado via variável de ambiente `GOOGLE_DRIVE_CATALOG_PDF_FILE_ID`.
2. **Entrega como Anexo Nativo (WhatsApp / CRM):**
   - O agente **não deve** enviar URLs de navegação web do Google Drive (`https://drive.google.com/file/.../view`) como corpo de texto corrido.
   - O canal WhatsApp deve receber o arquivo diagramado sob o tipo **documento/anexo (`file attachment`)**, garantindo que o WhatsApp exiba o balão de anexo de documento com o ícone e nome do arquivo PDF.
3. **Contrato da Tool `send_catalog_pdf`:**
   - A ferramenta é invocada no contexto da tríade e disponibiliza a referência do arquivo PDF para a camada de despacho de anexos.
   - Em conformidade com o ecossistema de mensageria (`evo-bot-runtime` e `evolution-api`), os anexos de mídia e documentos são processados e enviados na conversa através da estrutura de `attachments` com tipo `file` e formato `application/pdf`.

### 3.2. Regras de Negócio Conversacionais e Fluxo de Atendimento

#### Gatilhos de Ativação do Catálogo em PDF:
Quando a mensagem do cliente contiver intenção explícita ou implícita sobre:
1. Catálogo ou cardápio completo de produtos (ex: *"Me passa o catálogo"*, *"Quero ver o cardápio"*);
2. Preços e tabela geral de cafés (ex: *"Quais os preços?"*, *"Quanto custam os cafés?"*);
3. Cafés disponíveis no momento (ex: *"Quais cafés vocês têm?"*, *"O que tem disponível hoje?"*).

#### Resposta Determinística Obrigatória:
O agente deve estruturar a resposta contendo:
1. Frase de Abertura:
   `"Deixa eu te mandar o nosso catálogo aqui"`
2. Disparo do Anexo:
   Invocação da ferramenta `send_catalog_pdf`, anexando o arquivo PDF do catálogo na conversa.
3. Frase de Fechamento:
   `"Dá uma olhada, eu tiro suas dúvidas e a gente monta o seu pedido"`

#### Preservação das Ferramentas de Consulta Pontual:
- As ferramentas `coffee_search` e `get_coffee_details` continuam ativas para os turnos subsequentes da conversa, quando o cliente, após analisar o PDF anexo, formular perguntas específicas:
  - *"Tem algum café com notas de frutas amarelas?"* -> invoca `coffee_search`.
  - *"Qual o valor do pacote de 1kg do Catuaí?"* -> invoca `get_coffee_details`.
  - *"Quais as moagens disponíveis para prensa?"* -> responde objetivamente com base nas moagens padrão.

#### Proteção de Precificação Corporativa (B2B):
- O PDF disponibilizado é estritamente o catálogo público de varejo (Pessoa Física).
- Em conformidade com a **SPEC-012** e **SPEC-016**, caso o cliente seja identificado como Pessoa Jurídica (empresa, cafeteria, restaurante, compra no atacado acima de 5kg):
  - É proibido cotar preços corporativos via bot.
  - O agente aciona a transferência corporativa via `transfer_to_b2b_agent` / `notify_owner_corporate_order`.

---

### 3.3. Configuração GitOps no ArgoCD (`paralax-ia/argocd`)

No repositório `argocd`, no manifesto `prod/anero-cafe-support/patch-env.yaml`:
```yaml
- name: GOOGLE_DRIVE_CATALOG_PDF_FILE_ID
  value: "1ORQJaJjceD9DqU4ZLR_jAOqtrR9vGWlB"
```

**Arquivo Alvo no Google Drive:**
- **Link Oficial:** `https://drive.google.com/file/d/1ORQJaJjceD9DqU4ZLR_jAOqtrR9vGWlB/view?usp=drive_link`
- **File ID:** `1ORQJaJjceD9DqU4ZLR_jAOqtrR9vGWlB`

**Conta de Serviço GCP (Workload Identity) que necessita de acesso Leitor (Viewer):**
- **`prod-agent-anero-cafe-support@paralax-prod.iam.gserviceaccount.com`**
- *Nota de Operação:* O proprietário do arquivo no Google Drive deve compartilhar o PDF com este e-mail concedendo permissão de **Leitor (Viewer)**.

---

### 3.5. Governança de Prompts (SPEC-PROMPT-01 & Langfuse SSOT)

- **Prompt 1:** `anero_cafe/instruction`
  - **Repositório:** `paralax-ia/anero-cafe-support`
  - **Arquivo Local / Fallback:** `anero_cafe/prompts.py` (constante `INSTRUCTION`)
  - **Papel:** Instrução mestra de sistema do agente Anero Café
  - **Alteração:** Adição da regra de disparo do PDF do catálogo como anexo em `<tools_and_search>` e `<catalog_pdf_dispatch_rule>` com a tríade determinística (abertura, tool `send_catalog_pdf` e fechamento).
  - **Idioma:** Estritamente em inglês nas diretrizes de sistema, com as frases de resposta literal em português do Brasil (PT-BR).

- **Prompt 2:** `anero_cafe/atendimento_normal`
  - **Repositório:** `paralax-ia/anero-cafe-support`
  - **Arquivo Local / Fallback:** `anero_cafe/prompts.py` (constante `INSTRUCTION_ATENDIMENTO_NORMAL`)
  - **Papel:** Instrução especializada para clientes de varejo (Pessoa Física)
  - **Alteração:** Espelhamento estrito da regra de disparo do PDF como anexo para perguntas de catálogo/preços.

---

## 4. Critérios de Aceitação (Gherkin)

```gherkin
Funcionalidade: Disparo de Catálogo em PDF como Anexo via Google Drive no Anero Café

  Contexto:
    Dado que a variável "GOOGLE_DRIVE_CATALOG_PDF_FILE_ID" está configurada com "1ORQJaJjceD9DqU4ZLR_jAOqtrR9vGWlB"
    E que a Service Account "prod-agent-anero-cafe-support@paralax-prod.iam.gserviceaccount.com" possui permissão de leitura no arquivo

  Cenário: Cliente pergunta sobre catálogo geral de produtos
    Dado um cliente no canal WhatsApp iniciando atendimento
    Quando o cliente enviar a mensagem "Vocês têm catálogo de cafés? Pode me mandar?"
    Então o agente deve responder com a frase inicial "Deixa eu te mandar o nosso catálogo aqui"
    E deve invocar a tool "send_catalog_pdf" para disparar o PDF do catálogo como anexo de documento
    E o agente não deve enviar link cru de navegação externa do Google Drive no corpo da mensagem
    E o agente deve finalizar com "Dá uma olhada, eu tiro suas dúvidas e a gente monta o seu pedido".

  Cenário: Cliente pergunta sobre a tabela de preços dos cafés
    Dado um cliente no canal WhatsApp
    Quando o cliente enviar a mensagem "Qual o preço dos cafés de vocês?"
    Então o agente não deve gerar uma lista extensa de texto com preços manuais
    E deve responder "Deixa eu te mandar o nosso catálogo aqui"
    E deve disponibilizar o PDF do catálogo como anexo via tool "send_catalog_pdf"
    E deve finalizar com "Dá uma olhada, eu tiro suas dúvidas e a gente monta o seu pedido".

  Cenário: Dúvida específica sobre notas sensoriais após envio do catálogo
    Dado que o catálogo em PDF como anexo já foi enviado na conversa
    Quando o cliente perguntar "Vi no catálogo o café Catuaí, quais são as notas sensoriais dele?"
    Então o agente não deve re-disparar o catálogo em PDF
    E deve invocar a ferramenta "get_coffee_details" ou "coffee_search"
    E responder objetivamente às dúvidas do cliente sobre o produto.

  Cenário: Execução da tool com variável de ambiente declarativa
    Dado que a configuração do agente possui "GOOGLE_DRIVE_CATALOG_PDF_FILE_ID" preenchido
    Quando a ferramenta "send_catalog_pdf" for executada
    Então ela deve disponibilizar o catálogo em PDF para anexo nativo no canal.
```

---

## 5. Plano de Rollout e Compatibilidade

1. **Onda 1 (`anero-cafe-support`):**
   - Branch `agent/paralax-spec-021-anero-cafe-support`.
   - Tool `send_catalog_pdf` conectada a `GOOGLE_DRIVE_CATALOG_PDF_FILE_ID`.
   - Atualizar constantes de prompt em `anero_cafe/prompts.py` e sincronizar rascunho (`draft`) no Langfuse.
   - Testes unitários em `tests/unit/test_catalog_pdf.py` com TDD validando contratos.
   - Validar com `just verify`.
   - PR [#48](https://github.com/paralax-ia/anero-cafe-support/pull/48) e PR [#49](https://github.com/paralax-ia/anero-cafe-support/pull/49) (concluídos).
2. **Onda 2 (`argocd`):**
   - Branch `agent/paralax-spec-021-argocd`.
   - Declarar `GOOGLE_DRIVE_CATALOG_PDF_FILE_ID: "1ORQJaJjceD9DqU4ZLR_jAOqtrR9vGWlB"` no overlay `prod/anero-cafe-support`.
   - PR [#33](https://github.com/paralax-ia/argocd/pull/33) (concluído).
3. **Fechamento e Promoção:**
   - Promover os prompts no Langfuse SSOT para `production`.
   - Merge transacional dos PRs após aprovação no Cross-Repo Gate.
