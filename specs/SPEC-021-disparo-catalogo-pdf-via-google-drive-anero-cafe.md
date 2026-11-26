---
spec_id: SPEC-021
title: "Disparo de Catálogo em PDF via Google Drive e Fluxo Conversacional de Cardápio no Anero Café"
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
    description: "System instructions for Anero Cafe agent with PDF catalog dispatch and fixed conversational flow"
  - name: anero_cafe/atendimento_normal
    target_repo: paralax-ia/anero-cafe-support
    file: anero_cafe/prompts.py
    symbol: INSTRUCTION_ATENDIMENTO_NORMAL
    description: "Retail conversational prompt for Anero Cafe normal attendance with deterministic PDF dispatch"
status: APPROVED
---

# SPEC-021: Disparo de Catálogo em PDF via Google Drive e Fluxo Conversacional de Cardápio no Anero Café

> **Product:** [`anero-cafe-support`](../products/anero-cafe-support.yaml) | [`paralax-platform`](../products/paralax-platform.yaml)  
> **Business Capability:** [`conversational-ai-agent`](../capabilities/conversational-ai-agent/capability.yaml)  
> **Scope:** Agente de IA (`anero-cafe-support`) e GitOps (`argocd`)  
> **Bounded Context:** Conversational Agent / Canais & Envio de Documentos  
> **Status:** DRAFT  
> **Autor:** Eduardo F. Santos  
> **Data de Criação:** 2026-11-26  
> **Parent Spec:** [`SPEC-016`](./SPEC-016-integracao-google-drive-conhecimento-agentes.md) (Infraestrutura de leitura do Google Drive)  
> **Arquitetura 12-Factor:** Zero arquivos binários no Git; o catálogo reside no Google Drive sob o ID `GOOGLE_DRIVE_CATALOG_PDF_FILE_ID` injetado via variáveis de ambiente centralizadas no ArgoCD.  

---

## 1. Contexto e Motivação

Durante o primeiro contato com a torrefação **Anero Café** no WhatsApp oficial, grande parte dos clientes pergunta de forma aberta sobre:
- Os cafés disponíveis;
- Preços dos cafés e tabelas de valor;
- Catálogo de produtos e cardápio geral.

Na arquitetura anterior (estabelecida pela **SPEC-018**), a resposta era gerada por meio de templates Jinja2 que montavam cards de texto com todos os cafés cadastrados. Embora tenha resolvido o problema de fatiamento indevido no WhatsApp, a listagem completa em texto ainda gera mensagens muito extensas e sobrecarregadas de informação para clientes que desejam apenas folhear o portfólio visual da cafeteria.

A cafeteria possui um **catálogo oficial diagramado em formato PDF**, mantido e atualizado de forma centralizada em uma pasta do **Google Drive**.

Esta especificação define:
1. Uma **nova ferramenta (tool)** no agente `anero-cafe-support` para disponibilizar o PDF oficial do catálogo.
2. A integração transparente para que o documento do Google Drive seja servido com terminação `.pdf`, permitindo que o orquestrador (`evo-bot-runtime`) e o CRM o enviem como **documento/arquivo nativo no WhatsApp**.
3. O fluxo conversacional determinístico de atendimento:
   - Mensagem inicial: `"Deixa eu te mandar o nosso catálogo aqui"`
   - Disparo do documento PDF.
   - Mensagem de fechamento: `"Dá uma olhada, eu tiro suas dúvidas e a gente monta o seu pedido"`
4. A manutenção das ferramentas de consulta pontual (`coffee_search`, `get_coffee_details`) para sanar dúvidas específicas (notas sensoriais, torra, moagens) após o cliente consultar o PDF.

---

## 2. Escopo e Repositórios Afetados (Ondas Topológicas)

- [ ] **Sub-tarefa 1 (`paralax-ia/anero-cafe-support`):** [Onda 1] Implementação da tool `send_catalog_pdf`, rota HTTP estática de download/cache do PDF do Google Drive (`GET /assets/catalogo_anero.pdf`), atualização dos prompts governados no Langfuse e suíte de testes unitários com TDD.
- [ ] **Sub-tarefa 2 (`paralax-ia/argocd`):** [Onda 2] Declaração declarativa 12-Factor das variáveis `GOOGLE_DRIVE_CATALOG_PDF_FILE_ID` e `CATALOG_PDF_PUBLIC_URL` no overlay `prod/anero-cafe-support`.

```
┌────────────────────────────────────────────────────────────────────────┐
│                        ONDA 1: AGENTE DE IA                            │
│                    paralax-ia/anero-cafe-support                       │
│  • Tool `send_catalog_pdf` (ou `get_catalog_pdf`)                      │
│  • Rota de cache/serving: `GET /assets/catalogo_anero.pdf`             │
│  • Consumo do Drive via Service Account (Workload Identity SPEC-016)   │
│  • Prompts governados: `anero_cafe/instruction` e `atendimento_normal` │
│  • Testes TDD com docstrings `Business Rule:`                          │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                          ONDA 2: GITOPS                                │
│                         paralax-ia/argocd                              │
│  • Injeção de `GOOGLE_DRIVE_CATALOG_PDF_FILE_ID` no overlay de prod     │
│  • Injeção de `CATALOG_PDF_PUBLIC_URL` no deployment do agente         │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Contratos de Arquitetura e Engenharia

### 3.1. Viabilidade Técnica e Mecanismo de Disparo de Documentos

1. **Restrição Arquitetural do Orquestrador de Mensageria (`evo-bot-runtime` & `evo-ai-crm-community`):**
   - O detector de mídia do CRM (`MediaTypeDetector`) e do orquestrador (`extractMediaURLs`) analisa a extensão do arquivo na URL:
     ```ruby
     path = url.to_s.split(/[?#]/, 2).first.to_s
     segment = path.split('/').last.to_s
     ext = segment.split('.').last.to_s.downcase
     # DOCUMENT_EXT = %w[pdf doc docx xls xlsx ppt pptx txt rtf odt]
     ```
   - Uma URL direta padrão do Google Drive (ex: `https://drive.google.com/file/d/{FILE_ID}/view` ou `https://drive.google.com/uc?export=download&id={FILE_ID}`) termina em `/view` ou `/uc`. Como não termina em `.pdf`, o orquestrador não a reconhece como mídia e o WhatsApp a exibe como texto puro, além de falhar no download automático devido a cookies/telas de confirmação do Google.
2. **Solução Arquitetural: Serving de Cache com Extensão `.pdf` no Pod:**
   - O agente `anero-cafe-support` (FastAPI) expõe a rota pública:
     `GET /assets/catalogo_anero.pdf`
   - O pod utiliza a biblioteca `paralax-agents-common` e as credenciais Workload Identity da Service Account para baixar o arquivo binário correspondente a `GOOGLE_DRIVE_CATALOG_PDF_FILE_ID`.
   - O binário é mantido em cache local em memória/disco com TTL (ex: 3600 segundos).
   - O endpoint responde com `Content-Type: application/pdf` e `Content-Disposition: inline; filename="catalogo_anero.pdf"`.
   - A tool `send_catalog_pdf` retorna a URL canônica `https://<dominio-anero>/assets/catalogo_anero.pdf`.
   - O orquestrador detecta a extensão `.pdf` no path e despacha a requisição com `postbackAttachment{URL: "...", FileType: "file"}`, entregando o documento PDF nativo no WhatsApp.

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
2. Disparo da Tool:
   Invocação da ferramenta `send_catalog_pdf` (que injeta a URL do PDF a ser extraída pelo runtime).
3. Frase de Fechamento:
   `"Dá uma olhada, eu tiro suas dúvidas e a gente monta o seu pedido"`

#### Preservação das Ferramentas de Consulta Pontual:
- As ferramentas `coffee_search` e `get_coffee_details` continuam ativas para os turnos subsequentes da conversa, quando o cliente, após analisar o PDF, formular perguntas específicas:
  - *"Tem algum café com notas de frutas amarelas?"* -> invoca `coffee_search`.
  - *"Qual o valor do pacote de 1kg do Catuaí?"* -> invoca `get_coffee_details`.
  - *"Quais as moagens disponíveis para prensa?"* -> responde objetivamente com base nas moagens padrão.

#### Proteção de Precificação Corporativa (B2B):
- O PDF disponibilizado é estritamente o catálogo público de varejo (Pessoa Física).
- Em conformidade com a **SPEC-012** e **SPEC-016**, caso o cliente seja identificado como Pessoa Jurídica (empresa, cafeteria, restaurante, compra no atacado acima de 5kg):
  - É proibido cotar preços corporativos via bot.
  - O agente aciona a transferência corporativa via `transfer_to_b2b_agent` / `notify_owner_corporate_order`.

---

### 3.5. Governança de Prompts (SPEC-PROMPT-01 & Langfuse SSOT)

- **Prompt 1:** `anero_cafe/instruction`
  - **Repositório:** `paralax-ia/anero-cafe-support`
  - **Arquivo Local / Fallback:** `anero_cafe/prompts.py` (constante `INSTRUCTION`)
  - **Papel:** Instrução mestra de sistema do agente Anero Café
  - **Alteração:** Adição da regra de disparo de PDF em `<tools_and_search>` e substituição da orientação de envio de sumário longo de texto pela tríade determinística (abertura, tool de PDF e fechamento).
  - **Idioma:** Estritamente em inglês nas diretrizes de sistema, com as frases de resposta literal em português do Brasil (PT-BR).

- **Prompt 2:** `anero_cafe/atendimento_normal`
  - **Repositório:** `paralax-ia/anero-cafe-support`
  - **Arquivo Local / Fallback:** `anero_cafe/prompts.py` (constante `INSTRUCTION_ATENDIMENTO_NORMAL`)
  - **Papel:** Instrução especializada para clientes de varejo (Pessoa Física)
  - **Alteração:** Espelhamento estrito da regra de disparo do PDF para perguntas de catálogo/preços.

---

## 4. Critérios de Aceitação (Gherkin)

```gherkin
Funcionalidade: Disparo de Catálogo em PDF via Google Drive no Anero Café

  Contexto:
    Dado que a variável "GOOGLE_DRIVE_CATALOG_PDF_FILE_ID" está configurada com um ID de arquivo válido no Drive
    E que a Service Account do pod possui permissão de leitura no arquivo
    E que o endpoint "GET /assets/catalogo_anero.pdf" responde com status 200 e tipo "application/pdf"

  Cenário: Cliente pergunta sobre catálogo geral de produtos
    Dado um cliente no canal WhatsApp iniciando atendimento
    Quando o cliente enviar a mensagem "Vocês têm catálogo de cafés? Pode me mandar?"
    Então o agente deve responder com a frase inicial "Deixa eu te mandar o nosso catálogo aqui"
    E deve invocar a tool "send_catalog_pdf"
    E a mensagem deve conter a URL do catálogo com terminação ".pdf"
    E o agente deve finalizar com "Dá uma olhada, eu tiro suas dúvidas e a gente monta o seu pedido".

  Cenário: Cliente pergunta sobre a tabela de preços dos cafés
    Dado um cliente no canal WhatsApp
    Quando o cliente enviar a mensagem "Qual o preço dos cafés de vocês?"
    Então o agente não deve gerar uma lista extensa de texto com preços manuais
    E deve responder "Deixa eu te mandar o nosso catálogo aqui"
    E deve disponibilizar o PDF do catálogo via tool "send_catalog_pdf"
    E deve finalizar com "Dá uma olhada, eu tiro suas dúvidas e a gente monta o seu pedido".

  Cenário: Dúvida específica sobre notas sensoriais após envio do catálogo
    Dado que o catálogo em PDF já foi enviado na conversa
    Quando o cliente perguntar "Vi no catálogo o café Catuaí, quais são as notas sensoriais dele?"
    Então o agente não deve re-disparar o catálogo em PDF
    E deve invocar a ferramenta "get_coffee_details" ou "coffee_search"
    E responder objetivamente às dúvidas do cliente sobre o produto.

  Cenário: Detecção de anexo pelo orquestrador de mensageria
    Dado que a resposta do agente contém o link "https://anero-cafe.paralax.ia/assets/catalogo_anero.pdf"
    Quando o orquestrador "evo-bot-runtime" processar o retorno do agente
    Então a função "extractMediaURLs" deve identificar o link como attachment do tipo "file"
    E encaminhar o anexo de documento PDF nativo para entrega no WhatsApp.

  Cenário: Resiliência em caso de falha de conexão com o Google Drive
    Dado que o pod já realizou o download prévio do catálogo e o mantém em cache local
    Quando ocorrer uma indisponibilidade temporária na Google Drive API
    Então a rota "GET /assets/catalogo_anero.pdf" deve continuar servindo a cópia em cache
    E registrar aviso de log sem interromper o atendimento aos clientes.
```

---

## 5. Plano de Rollout e Compatibilidade

1. **Onda 1 (`anero-cafe-support`):**
   - Criar branch `feat/spec-021-disparo-catalogo-pdf-drive`.
   - Implementar rota `/assets/catalogo_anero.pdf` e tool `send_catalog_pdf`.
   - Atualizar constantes de prompt em `anero_cafe/prompts.py` e sincronizar rascunho (`draft`) no Langfuse.
   - Criar testes unitários em `tests/unit/test_catalog_pdf.py` com TDD.
   - Validar com `just verify`.
   - Submeter PR via `gh pr create`.
2. **Onda 2 (`argocd`):**
   - Criar branch `feat/spec-021-argocd-catalog-pdf-config`.
   - Declarar `GOOGLE_DRIVE_CATALOG_PDF_FILE_ID` e `CATALOG_PDF_PUBLIC_URL` no overlay `prod/anero-cafe-support`.
   - Submeter PR via `gh pr create`.
3. **Fechamento e Promoção:**
   - Promover os prompts no Langfuse SSOT para `production`.
   - Merge transacional dos PRs após aprovação no Cross-Repo Gate.
