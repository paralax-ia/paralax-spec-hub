---
spec_id: SPEC-016
title: "Integração Universal com Google Drive para Bases de Conhecimento e Catálogos de Agentes de IA"
product:
  - paralax-platform
  - anero-cafe-support
  - customer-support-vehicles
  - duo-dermato-support
  - paralax-support
capability: conversational-ai-agent
scope: platform
bounded_context: "Knowledge Base & Document Integration (Supporting Subdomain)"
origin_module: paralax-agents-common
target_repositories:
  - repo: paralax-ia/terraform
    wave: 1
    role: infrastructure
  - repo: paralax-ia/paralax-agents-common
    wave: 2
    role: sdk
  - repo: paralax-ia/argocd
    wave: 3
    role: gitops
  - repo: paralax-ia/anero-cafe-support
    wave: 3
    role: ai-agent
status: DRAFT
---

# SPEC-016: Integração Universal com Google Drive para Bases de Conhecimento e Catálogos de Agentes de IA

> **Product:** [`paralax-platform`](../products/paralax-platform.yaml) | [`anero-cafe-support`](../products/anero-cafe-support.yaml) | [`customer-support-vehicles`](../products/customer-support-vehicles.yaml) | [`duo-dermato-support`](../products/duo-dermato-support.yaml) | [`paralax-support`](../products/paralax-support.yaml)  
> **Business Capability:** [`conversational-ai-agent`](../capabilities/conversational-ai-agent/capability.yaml)  
> **Scope:** Platform (Transversal a todos os agentes conversacionais da Paralax IA)  
> **Bounded Context:** Knowledge Base & Document Integration (Supporting Subdomain)  
> **Status:** DRAFT  
> **Autor:** Eduardo F. Santos  
> **Data de Criação:** 2026-11-16  
> **Arquitetura 12-Factor:** Zero arquivos de configuração ou credenciais no Git; IDs de arquivos/pastas parametrizados via variáveis de ambiente centralizadas no ArgoCD.  
> **Diretriz de Prompts (SPEC-PROMPT-01):** Prompts de sumarização e extração estritamente em inglês.  
> **Repositórios Impactados (Ondas Topológicas):**  
> - `paralax-ia/terraform` (Onda 1 - Infraestrutura: Habilitação da API Google Drive e governança de SAs)  
> - `paralax-ia/paralax-agents-common` (Onda 2 - Biblioteca Compartilhada: Cliente Google Drive com Workload Identity, Cache Inteligente e suporte a Docs, Sheets e Markdown)  
> - `paralax-ia/argocd` (Onda 3 - GitOps: Declaração 12-Factor dos IDs de documentos do Drive)  
> - `paralax-ia/anero-cafe-support` (Onda 3 - Agente Piloto: Adoção das bases de dados PF e PJ via Google Drive, substituindo web scraping)  

---

## 1. Contexto e Motivação

Os agentes conversacionais autônomos da Paralax IA necessitam de fontes dinâmicas de conhecimento operacional: cardápios, tabelas de preços de atacado/varejo, catálogos de produtos, políticas comerciais e regras de frete.

Historicamente, duas abordagens vinham sendo utilizadas:
1. **Dados embutidos no repositório Git:** Qualquer alteração em preços de café ou veículos exige commit, review, testes e novo deploy de imagem de container.
2. **Raspagem web em tempo real (Web Scraping):** Implementada inicialmente no `anero-cafe-support`, revelou graves fragilidades arquiteturais:
   - **Latência excessiva:** Cada busca ou extração no site do cliente adiciona 5 a 20 segundos de espera ao webhook HTTP do CRM.
   - **Fragilidade de layout:** Mudanças no HTML da loja virtual ou atualizações de plataforma quebram as ferramentas de parsing.
   - **Insegurança de precificação:** Risco de cotar preços de varejo do site para clientes corporativos de atacado.

### A Solução Moderna: Google Drive como Knowledge Base Centralizada

No ecossistema corporativo, proprietários de negócios, gerentes comerciais e equipes de operação gerenciam seus dados em planilhas (Google Sheets), documentos (Google Docs) ou arquivos Markdown/PDF no **Google Drive**.

Esta especificação define um mecanismo universal, desacoplado e nativo de nuvem para permitir que os agentes de IA consumam dados do Google Drive:
- **Autenticação Nativa sem Segredos (Workload Identity):** O pod no GKE acessa a Google Drive API v3 utilizando a identidade da Service Account do GCP, sem arquivos de chave `.json` versionados.
- **Compartilhamento Simples:** O operador humano precisa apenas compartilhar a pasta ou documento com o e-mail da Service Account do agente (permissão de Leitor / Viewer).
- **Cache-Aside com Detecção por `modifiedTime`:** O agente mantém o conteúdo em cache local e só realiza novos downloads quando a data de modificação (`modifiedTime`) ou checksum do arquivo for alterada no Drive.
- **Suporte Multiformato Transparente:**
  - Google Docs (`application/vnd.google-apps.document`) são exportados automaticamente para texto limpo/markdown.
  - Google Sheets (`application/vnd.google-apps.spreadsheet`) são exportados automaticamente para formato tabular estruturado (CSV).
  - Arquivos normais (Markdown `.md`, TXT, JSON, PDF) são lidos diretamente via download binário.

---

## 2. Escopo e Repositórios Afetados (Ondas Topológicas)

- [ ] **Sub-tarefa 1 (`paralax-ia/terraform`):** [Onda 1] Habilitação da API `drive.googleapis.com` em `workload_project_apis` e exportação dos e-mails de Service Account dos agentes.
- [ ] **Sub-tarefa 2 (`paralax-ia/paralax-agents-common`):** [Onda 2] Implementação do módulo `GoogleDriveContentManager` em `paralax.agents.common.drive` com suporte a Workload Identity, multiformato (Docs, Sheets, Markdown) e Cache-Aside por `modifiedTime`.
- [ ] **Sub-tarefa 3 (`paralax-ia/argocd`):** [Onda 3] Declaração declarativa 12-Factor dos IDs de documentos do Google Drive (`GOOGLE_DRIVE_PF_FILE_ID` e `GOOGLE_DRIVE_PJ_FILE_ID`).
- [ ] **Sub-tarefa 4 (`paralax-ia/anero-cafe-support`):** [Onda 3] Adoção piloto das ferramentas de catálogo baseadas no Drive, substituindo o web scraping e isolando bases PF e PJ.

```
┌────────────────────────────────────────────────────────────────────────┐
│                      ONDA 1: INFRAESTRUTURA GCP                        │
│                         paralax-ia/terraform                           │
│  • Habilitação da API `drive.googleapis.com` em `workload_project_apis` │
│  • Validação do mapeamento de Workload Identity para leitura do Drive │
│  • Exportação estruturada dos e-mails das SAs dos agentes              │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                   ONDA 2: BIBLIOTECA COMPARTILHADA                     │
│                  paralax-ia/paralax-agents-common                      │
│  • Novo módulo `paralax.agents.common.drive`:                          │
│    - `GoogleDriveContentManager`: Gerenciador com cache TTL e polling  │
│    - Detecção de formato (Docs, Sheets, Markdown, PDF)                 │
│    - Resiliência: fallback para último cache válido em caso de falha   │
│  • Publicação da versão minor no Artifact Registry (`prod-python`)    │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                 ONDA 3: GITOPS & ADOÇÃO NOS AGENTES                    │
│                                                                        │
│ 1. paralax-ia/argocd                                                   │
│    • Injeção de variáveis 12-Factor em `prod/anero-cafe-support`:      │
│      `GOOGLE_DRIVE_PF_FILE_ID` e `GOOGLE_DRIVE_PJ_FILE_ID`             │
│                                                                        │
│ 2. paralax-ia/anero-cafe-support                                       │
│    • Substituição do scraping do site pelas ferramentas locais do Drive│
│    • Agente 1: Consulta base PJ do Drive com preços de atacado         │
│    • Agente 2: Consulta base PF do Drive com preços de varejo          │
│    • Agente 3: Consulta base PJ do Drive com omissão estrita de preços │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Contratos de Arquitetura e Engenharia

### 3.1. Onda 1: Terraform (`paralax-ia/terraform`)

#### Alteração em `terraform/environments/prod/terraform.tfvars`:
Adição da API do Google Drive na lista `workload_project_apis`:
```hcl
workload_project_apis = [
  "run.googleapis.com",
  "sqladmin.googleapis.com",
  "redis.googleapis.com",
  "cloudresourcemanager.googleapis.com",
  "iam.googleapis.com",
  "aiplatform.googleapis.com",
  "secretmanager.googleapis.com",
  "monitoring.googleapis.com",
  "logging.googleapis.com",
  "cloudtrace.googleapis.com",
  "storage.googleapis.com",
  "discoveryengine.googleapis.com",
  "servicenetworking.googleapis.com",
  "cloudbuild.googleapis.com",
  "vpcaccess.googleapis.com",
  "certificatemanager.googleapis.com",
  "cloudbilling.googleapis.com",
  "calendar-json.googleapis.com",
  "drive.googleapis.com" # SPEC-016: Habilitação da Google Drive API v3
]
```

#### Modelo de Permissões IAM:
- **Workload Identity:** O Service Account Kubernetes (K8s SA) do agente já está vinculado ao Google Service Account (GSA) `prod-agent-<engine>-<agent>@paralax-prod.iam.gserviceaccount.com`.
- **ACL do Google Drive:** O acesso aos arquivos não exige permissões administrativas de projeto. O proprietário do arquivo no Google Drive simplesmente compartilha o arquivo/pasta com o e-mail da GSA com o papel de **Leitor (Viewer)**.

---

### 3.2. Onda 2: Biblioteca Compartilhada (`paralax-agents-common`)

#### Módulo: `paralax.agents.common.drive`

```python
"""Google Drive integration module for agent knowledge bases."""

import io
import logging
import os
import time
from typing import Any
from dataclasses import dataclass

import google.auth
from googleapiclient.discovery import build, Resource
from googleapiclient.http import MediaIoBaseDownload
from googleapiclient.errors import HttpError

logger = logging.getLogger(__name__)

DRIVE_SCOPES = ["https://www.googleapis.com/auth/drive.readonly"]


@dataclass
class DriveFileMetadata:
    """Metadados relevantes de um arquivo no Google Drive."""
    file_id: str
    name: str
    mime_type: str
    modified_time: str
    size_bytes: int | None = None


class GoogleDriveContentManager:
    """Gerenciador de leitura e cache inteligente de documentos do Google Drive.
    
    Implementa o padrão Cache-Aside com validação por modifiedTime:
    - Retorna o conteúdo a partir do cache local se o TTL ainda estiver válido.
    - Ao expirar o TTL, faz uma requisição leve de metadados (`files.get`).
    - Se a data de modificação for idêntica, renova o TTL sem baixar novamente.
    - Se o arquivo foi modificado, baixa a nova versão e atualiza o cache.
    - Em caso de falha de rede/API, atua com resiliência retornando o último cache válido.
    """

    def __init__(
        self,
        file_id: str,
        cache_ttl_seconds: int = 120,
        drive_service: Resource | None = None,
    ) -> None:
        self.file_id = file_id
        self.cache_ttl_seconds = cache_ttl_seconds
        self._drive_service = drive_service
        self._cached_content: str | None = None
        self._last_modified_time: str | None = None
        self._last_checked_at: float = 0.0

    def _get_service(self) -> Resource:
        """Inicializa o cliente autenticado da Google Drive API v3."""
        if self._drive_service is not None:
            return self._drive_service
        credentials, _ = google.auth.default(scopes=DRIVE_SCOPES)
        self._drive_service = build("drive", "v3", credentials=credentials, cache_discovery=False)
        return self._drive_service

    def get_content(self, force_refresh: bool = False) -> str:
        """Recupera o conteúdo atualizado do arquivo como texto puro/markdown.

        Args:
            force_refresh: Força revalidação imediata contra a Google Drive API.

        Returns:
            Conteúdo textual do documento.
        """
        now = time.time()
        if (
            not force_refresh
            and self._cached_content is not None
            and (now - self._last_checked_at) < self.cache_ttl_seconds
        ):
            return self._cached_content

        service = self._get_service()
        try:
            metadata = service.files().get(
                fileId=self.file_id,
                fields="id, name, mimeType, modifiedTime"
            ).execute()

            remote_modified = metadata.get("modifiedTime", "")
            mime_type = metadata.get("mimeType", "")

            # Se a versão remota não mudou e já temos cache, renova o timestamp
            if (
                not force_refresh
                and self._cached_content is not None
                and self._last_modified_time == remote_modified
            ):
                self._last_checked_at = now
                return self._cached_content

            # Executa exportação ou download conforme o tipo de mídia
            content = self._fetch_file_content(service, self.file_id, mime_type)
            self._cached_content = content
            self._last_modified_time = remote_modified
            self._last_checked_at = now
            return content

        except Exception as exc:
            logger.error("Erro ao sincronizar arquivo %s do Google Drive: %s", self.file_id, exc)
            if self._cached_content is not None:
                logger.warning("Utilizando último cache válido como contingência para %s", self.file_id)
                return self._cached_content
            raise

    def _fetch_file_content(self, service: Resource, file_id: str, mime_type: str) -> str:
        """Trata a conversão de Google Docs, Sheets ou arquivos binários."""
        if mime_type == "application/vnd.google-apps.document":
            # Exporta Google Doc como texto puro
            request = service.files().export_media(fileId=file_id, mimeType="text/plain")
        elif mime_type == "application/vnd.google-apps.spreadsheet":
            # Exporta Google Sheet como CSV
            request = service.files().export_media(fileId=file_id, mimeType="text/csv")
        else:
            # Baixa arquivo regular (Markdown, TXT, etc.)
            request = service.files().get_media(fileId=file_id)

        fh = io.BytesIO()
        downloader = MediaIoBaseDownload(fh, request)
        done = False
        while not done:
            _, done = downloader.next_chunk()

        return fh.getvalue().decode("utf-8", errors="replace")
```

---

### 3.3. Onda 3: Adoção no Agente `anero-cafe-support`

1. **Variáveis de Ambiente 12-Factor:**
   - `GOOGLE_DRIVE_PF_FILE_ID`: ID do documento de catálogo e condições para Consumidores Finais (PF).
   - `GOOGLE_DRIVE_PJ_FILE_ID`: ID do documento confidencial de atacado para Clientes Corporativos (PJ).
2. **Arquitetura das Ferramentas Locais dos Agentes:**
   - **`coffee_search`:** Executa busca semântica ou por correspondência de termos diretamente sobre os textos sincronizados do Google Drive (sem requisições HTTP ao site).
   - **`get_coffee_details_retail` (Agente 2):** Retorna características e preços do arquivo PF.
   - **`get_coffee_details_wholesale` (Agente 1):** Retorna preços de atacado, moagens, caixas e condições de frete do arquivo PJ.
   - **`get_coffee_details_without_price` (Agente 3):** Retorna apenas as notas e tipos de cafés do arquivo PJ, removendo valores monetários.

---

## 4. Critérios de Aceitação (Gherkin)

```gherkin
Funcionalidade: Sincronização de Conhecimento dos Agentes via Google Drive

  Cenário: Sincronização inicial com cache inteligente
    Dado que a variável "GOOGLE_DRIVE_PJ_FILE_ID" está configurada com um ID de Google Doc válido
    E que o arquivo foi compartilhado com a Service Account do agente
    Quando o Agente 1 inicializar e consultar os cafés para um cliente PJ
    Então o conteúdo do documento deve ser carregado via Google Drive API v3
    E armazenado no cache local em memória pelo tempo configurado em TTL
    E as consultas subsequentes dentro da janela de TTL não devem gerar chamadas adicionais de download.

  Cenário: Atualização dinâmica de preços sem redeploy da aplicação
    Dado que o arquivo no Google Drive teve seus preços de café alterados pelo operador
    E que a janela de TTL do cache expirou
    Quando o agente receber uma nova mensagem de consulta
    Então a verificação de "modifiedTime" deve detectar a alteração
    E o novo conteúdo com preços atualizados deve ser baixado e servido imediatamente ao cliente.

  Cenário: Resiliência contra indisponibilidade temporária da API do Google Drive
    Dado que o agente já possui uma versão do catálogo em cache
    E que uma falha de rede temporária impede a comunicação com o endpoint da Google Drive API
    Quando o agente processar uma solicitação de consulta
    Então o sistema deve registrar o erro em log com nível WARNING
    E devolver o conteúdo do último cache válido sem interromper a conversa do usuário.

  Cenário: Habilitação de infraestrutura no Terraform
    Dado o arquivo "terraform/environments/prod/terraform.tfvars"
    Quando a validação do Terraform for executada ("make validate ENV=prod")
    Então a API "drive.googleapis.com" deve constar na lista de APIs habilitadas do projeto.
```

---

## 5. Plano de Rollout e Compatibilidade

1. **Rollout da Onda 1 (Terraform):**
   - Abrir PR no repositório `terraform` adicionando `drive.googleapis.com`.
   - Executar validação com `make validate ENV=prod` e `make fmt`.
   - Submeter PR para aprovação humana e posterior apply pelo operador.
2. **Rollout da Onda 2 (`paralax-agents-common`):**
   - Desenvolver o módulo `paralax.agents.common.drive` com suíte de testes unitários mockando o cliente `googleapiclient`.
   - Publicar versão com incremento SemVer (`v0.2.x`) no Artifact Registry corporativo.
3. **Rollout da Onda 3 (`argocd` e `anero-cafe-support`):**
   - Atualizar a dependência no `anero-cafe-support` via `uv add paralax-agents-common`.
   - Substituir as ferramentas de scraping pelas ferramentas baseadas no Drive.
   - Declarar as variáveis de ambiente `GOOGLE_DRIVE_PF_FILE_ID` e `GOOGLE_DRIVE_PJ_FILE_ID` nos manifests K8s do ArgoCD.
