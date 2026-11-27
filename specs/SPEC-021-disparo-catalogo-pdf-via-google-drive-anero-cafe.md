---
spec_id: SPEC-021
title: "Disparo de Catálogo em PDF como Anexo via Bucket do CRM e Fluxo Conversacional de Cardápio no Anero Café"
product:
  - anero-cafe-support
  - paralax-platform
capability: conversational-ai-agent
scope: multi-repo
bounded_context: "Conversational Agent / Canais & Envio de Documentos"
origin_module: anero-cafe-support
target_repositories:
  - repo: paralax-ia/terraform
    wave: 1
    role: infrastructure
  - repo: paralax-ia/anero-cafe-support
    wave: 2
    role: ai-agent
    prompts:
      - anero_cafe/instruction
      - anero_cafe/atendimento_normal
  - repo: paralax-ia/argocd
    wave: 3
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

# SPEC-021: Disparo de Catálogo em PDF como Anexo via Bucket do CRM e Fluxo Conversacional de Cardápio no Anero Café

> **Product:** [`anero-cafe-support`](../products/anero-cafe-support.yaml) | [`paralax-platform`](../products/paralax-platform.yaml)  
> **Business Capability:** [`conversational-ai-agent`](../capabilities/conversational-ai-agent/capability.yaml)  
> **Scope:** Infraestrutura (`terraform`), Agente de IA (`anero-cafe-support`) e GitOps (`argocd`)  
> **Bounded Context:** Conversational Agent / Canais & Envio de Documentos  
> **Status:** APPROVED  
> **Autor:** Eduardo F. Santos  
> **Data de Criação:** 2026-11-26  
> **Data de Atualização:** 2026-11-27  
> **Parent Spec:** [`SPEC-016`](./SPEC-016-integracao-google-drive-conhecimento-agentes.md) (Infraestrutura de leitura do Google Drive)  
> **Evolution / Generalização:** Evoluída pela [`SPEC-022`](./SPEC-022-generalizacao-pdf-drive-md5.md) (Generalização do componente `GoogleDrivePdfManager` em `paralax-agents-common` com validação criptográfica MD5). O agente `anero-cafe-support` passa a consumir o manager universal do SDK compartilhado em vez de implementar lógica local proprietária.  
> **Arquitetura de Entrega:** O catálogo oficial diagramado reside no Google Drive sob o ID `GOOGLE_DRIVE_CATALOG_PDF_FILE_ID`. O agente utiliza o `GoogleDrivePdfManager` do pacote `paralax-agents-common` para sincronizar o arquivo binário no bucket de storage do CRM (`paralax-prod-prod-crm-storage`), e o CRM serve a URL pública sob a rota do ActiveStorage Proxy (`https://crm.paralax.ia.br/rails/active_storage/blobs/proxy/.../catalogo_anero.pdf`). O arquivo é entregue como **anexo nativo de documento (PDF)** no WhatsApp pela API Oficial da Meta.  

---

## 1. Contexto e Motivação

Durante o primeiro contato com a torrefação **Anero Café** no WhatsApp oficial, grande parte dos clientes pergunta de forma aberta sobre:
- Os cafés disponíveis;
- Preços dos cafés e tabelas de valor;
- Catálogo de produtos e cardápio geral.

Na arquitetura anterior (estabelecida pela **SPEC-018**), a resposta era gerada por meio de templates Jinja2 que montavam cards de texto com todos os cafés cadastrados. Embora tenha resolvido o problema de fatiamento indevido no WhatsApp, a listagem completa em texto ainda gera mensagens muito extensas e sobrecarregadas de informação para clientes que desejam apenas folhear o portfólio visual da cafeteria.

A cafeteria possui um **catálogo oficial diagramado em formato PDF**, mantido e atualizado de forma centralizada em uma pasta do **Google Drive**.

> [!IMPORTANT]
> **Diretriz de Negócio e Entrega como Anexo Nativo:**  
> **Não é para enviar o link do Google Drive para o cliente**, e sim **enviar o arquivo PDF como anexo nativo de documento** diretamente na conversa do WhatsApp.  
> 
> **Mecanismo de Publicação e Entrega (Generalizado via SPEC-022):**  
> 1. O **Google Drive** permanece como a fonte de verdade (SSOT) de edição para o time comercial.  
> 2. O **Agente (`anero-cafe-support`)** utiliza o **`GoogleDrivePdfManager`** provido pelo pacote compartilhado `paralax-agents-common` (conforme especificado na **SPEC-022**), lendo o binário do Google Drive via Service Account e salvando o arquivo no **bucket de storage do CRM** no Google Cloud Storage (GCS) sob o padrão do ActiveStorage do Rails.  
> 3. O **CRM (`crm.paralax.ia.br`)** serve a URL pública do arquivo sob o caminho `/rails/active_storage/blobs/proxy/:signed_id/catalogo_anero.pdf` (ou rota dedicada sob `/rails/` ou `/api/`), roteada pelo GKE Gateway diretamente para o pod `evo-crm` com `Content-Type: application/pdf` e terminação `.pdf`.  
> 4. O **`evo-bot-runtime`** e o **CRM** identificam o arquivo como anexo nativo (`fileType: "file"`), o serviço `RemoteMediaAttacher` do CRM faz o download do binário PDF real (sem interceptação do Nginx/SPA) e a **API Oficial do WhatsApp (Meta Graph API)** baixa o documento diretamente a partir da URL do CRM, entregando o PDF nativo na conversa sem atrito de redirecionamentos ou necessidade de login no Google.

Esta especificação define:
1. As **permissões de infraestrutura no Terraform** para permitir que o agente grave no bucket de storage do CRM.
2. Aderência estrita ao **12-Factor**: o agente consome declarativamente as variáveis de ambiente sem credenciais ou nomes de recursos arbitrários em código.
3. O fluxo conversacional determinístico de atendimento (Tríade Determinística):
   - Mensagem inicial: `"Deixa eu te mandar o nosso catálogo aqui"`
   - Disparo do **PDF do catálogo como anexo** na conversa (via ferramenta `send_catalog_pdf`).
   - Mensagem de fechamento: `"Dá uma olhada, eu tiro suas dúvidas e a gente monta o seu pedido"`
4. A manutenção das ferramentas de consulta pontual (`coffee_search`, `get_coffee_details`) para sanar dúvidas específicas (notas sensoriais, torra, moagens) após o cliente consultar o PDF anexo.

---

## 2. Escopo e Repositórios Afetados (Ondas Topológicas)

- [ ] **Sub-tarefa 1 (`paralax-ia/terraform`):** [Onda 1] Concessão de permissão IAM `roles/storage.objectUser` no bucket `google_storage_bucket.crm_storage` para a Service Account do agente `anero-cafe-support`.
- [ ] **Sub-tarefa 2 (`paralax-ia/anero-cafe-support`):** [Onda 2] Implementação da sincronização do PDF do Google Drive para o bucket do CRM, disponibilização da URL pública oficial do CRM via tool `send_catalog_pdf`, atualização dos prompts governados no Langfuse e suíte de testes unitários com TDD.
- [ ] **Sub-tarefa 3 (`paralax-ia/argocd`):** [Onda 3] Declaração declarativa 12-Factor das variáveis de ambiente (`GOOGLE_DRIVE_CATALOG_PDF_FILE_ID`, `CRM_STORAGE_BUCKET_NAME`, `CRM_PUBLIC_URL`, `CATALOG_PDF_FILE_NAME`) no overlay `prod/anero-cafe-support` (`patch-env.yaml`).

```
┌────────────────────────────────────────────────────────────────────────┐
│                        ONDA 1: INFRAESTRUTURA                          │
│                         paralax-ia/terraform                           │
│  • IAM: roles/storage.objectUser no bucket crm_storage para o agente   │
│  • Validação: make validate ENV=prod && make fmt                       │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                        ONDA 2: AGENTE DE IA                            │
│                    paralax-ia/anero-cafe-support                       │
│  • Download do Drive e persistência no bucket GCS do CRM               │
│  • Tool `send_catalog_pdf` (retorna URL pública oficial do CRM)        │
│  • Prompts governados: `anero_cafe/instruction` e `atendimento_normal` │
│  • Testes TDD com docstrings `Business Rule:`                          │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                          ONDA 3: GITOPS                                │
│                         paralax-ia/argocd                              │
│  • Injeção de variáveis 12-Factor no overlay de produção               │
│  • Permissão Leitor para a Service Account do agente no Google Drive   │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Contratos de Arquitetura e Engenharia

### 3.1. Viabilidade Técnica e Mecanismo de Disparo do PDF como Anexo

1. **Repositório Central no Google Drive (SSOT de Negócio):**
   - O arquivo PDF do catálogo oficial diagramado é mantido e editado pela equipe no Google Drive.
   - O ID do arquivo no Google Drive é injetado via variável de ambiente `GOOGLE_DRIVE_CATALOG_PDF_FILE_ID`.
2. **Armazenamento e Servimento Público no CRM:**
   - O agente salva o arquivo binário no bucket de storage do CRM (`paralax-prod-prod-crm-storage`).
   - **Causa Raiz do Bug de Conteúdo HTML (RCA):** No GKE Gateway (`HTTPRoute crm-route`), qualquer requisição para URLs que não casam com os prefixos `/api/`, `/rails/`, `/cable`, `/auth/`, `/core/`, `/processor/` cai na regra default `PathPrefix: /`, que encaminha para o pod do frontend SPA em Nginx (`evo-frontend`). O `evo-frontend` possui a diretriz `try_files $uri $uri/ /index.html;`, respondendo HTTP 200 com o `index.html` (468 bytes, `Content-Type: text/html`) em vez do PDF real.
   - **Correção Arquitetural do Roteamento:** O CRM (`crm.paralax.ia.br`) expõe a rota pública de download do arquivo sob o prefixo `/rails/active_storage/blobs/proxy/` (ou rota sob `/rails/` / `/api/`), roteada nativamente para o backend Rails (`evo-crm`). O Rails atende via ActiveStorage Proxy servindo o binário PDF genuíno com `Content-Type: application/pdf` e terminação `.pdf` (ex: `https://crm.paralax.ia.br/rails/active_storage/blobs/proxy/:signed_id/catalogo_anero.pdf`).
3. **Detecção e Entrega no WhatsApp (API Oficial da Meta):**
   - O `evo-bot-runtime` identifica a URL com extensão `.pdf` via `mediaFileType()` e envia o anexo estruturado (`fileType: "file"`) ao CRM.
   - O CRM ingere o documento no ActiveStorage (baixando o PDF real através do `RemoteMediaAttacher`) e invoca `WhatsappCloudService#send_attachment_via_link`.
   - A Meta Graph API recebe a URL pública servida pelo CRM, baixa o binário diretamente via HTTP 200 (sem redirecionamentos) e entrega o documento PDF perfeitamente anexado na conversa do WhatsApp.

---

### 3.2. Estratégia de Cache, Invalidação e Resiliência (Cache-Aside em Duas Camadas)

Para otimizar a performance, eliminar latência no atendimento ao cliente (evitando baixar repetidamente arquivos pesados em cada turno de conversa) e prevenir o esgotamento de cotas da Google Drive API:

1. **Camada 1: Cache em Memória no Agente (Metadados e URL Pública)**
   - O agente mantém em memória os metadados do catálogo: `last_checked_at` (timestamp Unix da última checagem), `last_modified_time` (string ISO de modificação remota no Drive) e a URL pública servida pelo CRM.
   - **TTL Configurável (`CATALOG_PDF_CACHE_TTL_SECONDS`):** Definido via variável de ambiente (padrão: `3600` segundos / 1 hora). Durante essa janela de tempo, qualquer chamada à ferramenta `send_catalog_pdf` responde instantaneamente com a URL em cache sem consultar a API do Drive nem acessar o bucket.

2. **Camada 2: Invalidação por Polling Leve (`files.get`)**
   - Ao expirar o TTL (ou na inicialização do pod), o agente não faz download do arquivo inteiro; realiza apenas uma chamada leve de metadados:
     `drive_service.files().get(fileId=..., fields="modifiedTime,md5Checksum").execute()`
   - Se o `modifiedTime` do Drive coincidir com o `last_modified_time` do cache e o objeto já existir no bucket:
     - O agente apenas atualiza `last_checked_at = now()` e mantém a URL sem gastar banda de rede.
   - Se o `modifiedTime` for diferente (indica que a cafeteria atualizou o catálogo) ou se for o primeiro provisionamento:
     - O agente realiza o download binário via `files.get_media()`.
     - Executa o upload atômico para o bucket do CRM (`paralax-prod-prod-crm-storage`) com `content_type="application/pdf"`.
     - Atualiza `last_modified_time = remote_modified`, `last_checked_at = now()` e o registro da URL pública.

3. **Resiliência e Fallback para Contingência:**
   - Se a Google Drive API apresentar indisponibilidade temporária (falha de rede, timeout, HTTP 429 ou 5xx):
     - O agente captura a falha e registra aviso em log (`logger.warning`).
     - Continua servindo a URL do arquivo já persistido no bucket do CRM (último cache válido).
     - O atendimento ao cliente nunca é interrompido por instabilidades externas do Google Drive.

---

### 3.3. Regras de Negócio Conversacionais e Fluxo de Atendimento

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
   Invocação da ferramenta `send_catalog_pdf`, entregando a URL pública oficial servida pelo CRM para que a esteira despache o anexo nativo.
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

### 3.4. Configuração de Infraestrutura no Terraform (`paralax-ia/terraform`)

No repositório `terraform`, no arquivo `main.tf`:

```hcl
# Concede permissão para a Service Account do agente anero-cafe-support
# gravar o catálogo PDF no bucket de storage do CRM
resource "google_storage_bucket_iam_member" "anero_cafe_catalog_pdf_crm_storage_access" {
  bucket = google_storage_bucket.crm_storage.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${module.iam.agent_sa_emails["anero-cafe-anero-cafe-support"]}"
}
```

- **Bucket Alvo:** `google_storage_bucket.crm_storage` (`paralax-prod-prod-crm-storage`)
- **Service Account Beneficiária:** `module.iam.agent_sa_emails["anero-cafe-anero-cafe-support"]` (`prod-agent-anero-cafe-support@paralax-prod.iam.gserviceaccount.com`)
- **Papel:** `roles/storage.objectUser` (leitura, escrita e atualização de objetos no bucket)
- **Criptografia CMEK:** A chave KMS do CRM (`google_kms_crypto_key.crm_key`) já possui concessão automática para o Service Agent do GCS (`roles/cloudkms.cryptoKeyEncrypterDecrypter`), permitindo a criptografia transparente dos objetos salvos pelo agente.

---

### 3.5. Configuração GitOps no ArgoCD (`paralax-ia/argocd`)

No repositório `argocd`, no manifesto `prod/anero-cafe-support/patch-env.yaml`:
```yaml
- name: GOOGLE_DRIVE_CATALOG_PDF_FILE_ID
  value: "1ORQJaJjceD9DqU4ZLR_jAOqtrR9vGWlB"
- name: CRM_STORAGE_BUCKET_NAME
  value: "paralax-prod-prod-crm-storage"
- name: CRM_PUBLIC_URL
  value: "https://crm.paralax.ia.br"
- name: CATALOG_PDF_FILE_NAME
  value: "catalogo_anero.pdf"
- name: CATALOG_PDF_CACHE_TTL_SECONDS
  value: "3600"
```

**Conta de Serviço GCP (Workload Identity) que necessita de acesso Leitor (Viewer) no Google Drive:**
- **`prod-agent-anero-cafe-support@paralax-prod.iam.gserviceaccount.com`**
- *Nota de Operação:* O proprietário do arquivo no Google Drive deve compartilhar o PDF com este e-mail concedendo permissão de **Leitor (Viewer)**.

---

### 3.6. Governança de Prompts (SPEC-PROMPT-01 & Langfuse SSOT)

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
Funcionalidade: Disparo de Catálogo em PDF como Anexo via Bucket do CRM no Anero Café

  Contexto:
    Dado que a Service Account "prod-agent-anero-cafe-support@paralax-prod.iam.gserviceaccount.com" possui permissão "roles/storage.objectUser" no bucket "paralax-prod-prod-crm-storage"
    E que a Service Account possui permissão de leitura no arquivo "1ORQJaJjceD9DqU4ZLR_jAOqtrR9vGWlB" no Google Drive
    E que a variável "CRM_PUBLIC_URL" está configurada com "https://crm.paralax.ia.br"

  Cenário: Sincronização do catálogo e salvamento no bucket do CRM
    Dado que o arquivo diagramado no Google Drive possui nova versão ou inicialização do serviço
    Quando o serviço de catálogo do agente processar o arquivo
    Então o binário do PDF deve ser salvo no bucket "paralax-prod-prod-crm-storage"
    E deve estar acessível sob a URL pública servida pelo CRM sob o prefixo "/rails/active_storage/blobs/proxy/.../catalogo_anero.pdf"
    E a URL não deve ser interceptada pelo fallback de SPA do Nginx, retornando HTTP 200 com "Content-Type: application/pdf".

  Cenário: Cliente pergunta sobre catálogo geral de produtos
    Dado um cliente no canal WhatsApp iniciando atendimento
    Quando o cliente enviar a mensagem "Vocês têm catálogo de cafés? Pode me mandar?"
    Então o agente deve responder com a frase inicial "Deixa eu te mandar o nosso catálogo aqui"
    E deve invocar a tool "send_catalog_pdf" entregando a URL pública oficial do CRM
    E o canal WhatsApp deve enviar o arquivo PDF diagramado como anexo nativo de documento
    E o agente não deve enviar link cru de navegação externa do Google Drive
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

  Cenário: Reutilização de cache dentro da janela de TTL
    Dado que o catálogo já foi sincronizado e armazenado no bucket do CRM
    E que a última checagem ocorreu há menos tempo que "CATALOG_PDF_CACHE_TTL_SECONDS"
    Quando o cliente solicitar o catálogo ou a lista de preços
    Então o agente deve invocar a tool "send_catalog_pdf"
    E a tool deve retornar imediatamente a URL pública em cache
    E nenhuma chamada de download ou verificação de metadados deve ser feita ao Google Drive ou GCS.

  Cenário: Verificação de metadados após expiração de TTL sem alteração no Drive
    Dado que a janela de TTL do cache expirou
    E que o arquivo no Google Drive não teve seu "modifiedTime" alterado
    Quando o agente consultar o catálogo
    Então o agente deve executar apenas a chamada de metadados "files.get"
    E não deve realizar download do binário nem upload para o bucket do CRM
    E deve renovar o timestamp de checagem mantendo a URL servida pelo CRM.

  Cenário: Atualização dinâmica do catálogo no Google Drive
    Dado que o catálogo diagramado foi atualizado no Google Drive com novo "modifiedTime"
    E que a janela de TTL do cache expirou
    Quando o agente for consultado
    Então o agente deve detectar o novo "modifiedTime" via "files.get"
    E baixar o novo binário do Google Drive
    E sobrescrever o arquivo no bucket "paralax-prod-prod-crm-storage"
    E atualizar os metadados de cache.

  Cenário: Resiliência em caso de falha de conexão com a API do Google Drive
    Dado que o catálogo já se encontra salvo no bucket do CRM
    E que a Google Drive API apresenta indisponibilidade transitória
    Quando o agente invocar a tool "send_catalog_pdf"
    Então o agente deve registrar um aviso no log
    E retornar normalmente a URL pública do bucket do CRM
    E o atendimento ao cliente não deve ser interrompido.
```

---

## 5. Plano de Rollout e Compatibilidade

1. **Onda 1 (`terraform`):**
   - Branch de trabalho no repositório `terraform`.
   - Adicionar recurso `google_storage_bucket_iam_member.anero_cafe_catalog_pdf_crm_storage_access` concedendo `roles/storage.objectUser` no bucket `google_storage_bucket.crm_storage`.
   - Validar com `make validate ENV=prod` e `make fmt`.
   - Submeter PR via `gh pr create`.
   - *Nota:* O humano executa `make plan` e `make apply` interativamente.
2. **Onda 2 (`anero-cafe-support`):**
   - Integrar download do Drive e persistência no bucket GCS do CRM.
   - Atualizar tool `send_catalog_pdf` para retornar a URL pública do CRM.
   - Testes unitários com TDD em `tests/unit/test_catalog_pdf.py` e validação canônica com `just verify`.
   - Submeter PR via `gh pr create`.
3. **Onda 3 (`argocd`):**
   - Injetar variáveis de ambiente 12-Factor no overlay `prod/anero-cafe-support/patch-env.yaml`.
   - Testes de validação de manifestos e `just verify`.
   - Submeter PR via `gh pr create`.
4. **Fechamento e Promoção:**
   - Promover os prompts no Langfuse SSOT para `production`.
   - Validação ponta a ponta no canal WhatsApp oficial.
