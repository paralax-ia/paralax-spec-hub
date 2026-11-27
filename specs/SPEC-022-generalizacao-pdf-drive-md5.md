---
spec_id: SPEC-022
title: "Generalização de Entrega de Documentos PDF via Google Drive e Storage Central com Validação Criptográfica MD5"
product:
  - paralax-platform
  - paralax-agents-common
  - anero-cafe-support
capability: conversational-ai-agent
scope: multi-repo
bounded_context: "Common Agent Core / Gestão e Entrega de Mídias e Documentos"
origin_module: paralax-spec-hub
target_repositories:
  - repo: paralax-ia/paralax-agents-common
    wave: 1
    role: shared-library
  - repo: paralax-ia/anero-cafe-support
    wave: 2
    role: ai-agent
  - repo: paralax-ia/argocd
    wave: 3
    role: gitops
status: DRAFT
---

# SPEC-022: Generalização de Entrega de Documentos PDF via Google Drive e Storage Central com Validação Criptográfica MD5

> **Product:** [`paralax-platform`](../products/paralax-platform.yaml) | [`paralax-agents-common`](../products/paralax-agents-common.yaml) | [`anero-cafe-support`](../products/anero-cafe-support.yaml)  
> **Business Capability:** [`conversational-ai-agent`](../capabilities/conversational-ai-agent/capability.yaml)  
> **Scope:** Shared Library (`paralax-agents-common`), Agentes Consumidores (`anero-cafe-support` e outros) e GitOps (`argocd`)  
> **Bounded Context:** Common Agent Core / Gestão e Entrega de Mídias e Documentos  
> **Status:** DRAFT  
> **Autor:** Eduardo F. Santos  
> **Data de Criação:** 2026-11-27  
> **Parent Spec:** [`SPEC-021`](./SPEC-021-disparo-catalogo-pdf-via-google-drive-anero-cafe.md) (Disparo de catálogo em PDF Anero Café)  

---

## 1. Contexto e Motivação

Na `SPEC-021`, foi implementado o fluxo de entrega de catálogo PDF para o agente `anero-cafe-support`. No entanto, a lógica de sincronização entre o Google Drive e o Google Cloud Storage (GCS) com cache inteligente foi desenvolvida de forma acoplada dentro do repositório do agente (`anero_cafe/services/catalog_pdf.py`).

Além disso, a URL resolvida utilizava caminhos internos ou chaves assinadas que não devem ser tratadas de forma estática no código do agente nem duplicadas a cada novo bot.

Diversos agentes da plataforma Paralax (concessionárias de veículos, clínicas dermatológicas, cafeterias, etc.) necessitam enviar documentos oficiais (catálogos, tabelas de preços, termos de consentimento, propostas comerciais) que residem no Google Drive.

### 1.1. Objetivos Estratégicos
1. **Generalização no Core (`paralax-agents-common`)**: Prover um gerenciador universal (`GoogleDrivePdfManager`) na biblioteca compartilhada, permitindo que qualquer agente de IA obtenha a URL canônica de entrega de um documento PDF apenas fornecendo o `file_id` do Google Drive e metadados básicos.
2. **Desacoplamento e 12-Factor**: Nenhum agente deve manter strings hardcoded de storage ou assinaturas internas no código.
3. **Resiliência e Cache em Duas Camadas**:
   - **Camada 1 (Memória / TTL)**: Evita consultas repetitivas a APIs externas.
   - **Camada 2 (Polling de Metadados / `modifiedTime` / `md5Checksum`)**: Sincroniza um novo download apenas quando o arquivo no Google Drive for efetivamente alterado.
4. **Verificação de Integridade Criptográfica (MD5)**: Criação de testes de integração ponta a ponta que comprovem matematicamente, através do cálculo de hash MD5 (`hashlib.md5`), que o binário entregue pelo webhook/canal é rigorosamente idêntico ao arquivo original mantido no Google Drive.

---

## 2. Arquitetura da Solução

```
 ┌────────────────────────────────────────────────────────────────────────┐
 │                    GOOGLE DRIVE (SSOT DE NEGÓCIO)                      │
 │    Arquivo PDF mantido pelo operador comercial (ex: Catálogo)          │
 └───────────────────────────────────┬────────────────────────────────────┘
                                     │ (Service Account / Workload Identity)
                                     ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │              SHARED LIBRARY: paralax-agents-common                     │
 │                 class GoogleDrivePdfManager                            │
 │  • Consulta metadados no Drive (modifiedTime, md5Checksum)             │
 │  • Cache TTL em memória                                                │
 │  • Download do binário original                                        │
 │  • Upload idempotente para o GCS (Storage do CRM/Público)              │
 │  • Retorno da URL canônica para despacho                               │
 └───────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │                   AGENTE DE IA (Ex: anero-cafe-support)                │
 │  • Tool send_catalog_pdf():                                            │
 │    manager.get_pdf_url(file_id=config.DRIVE_FILE_ID, filename=...)     │
 │  • Retorna a URL terminada em .pdf                                     │
 └───────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │            EVO-BOT-RUNTIME + CRM CORE (RemoteMediaAttacher)            │
 │  • Detecta a extensão .pdf na resposta                                 │
 │  • Baixa o binário do GCS/Proxy                                        │
 │  • Anexa nativamente na mensagem (WhatsApp Document Attachment)        │
 └────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Especificação do Componente `GoogleDrivePdfManager`

Localização no pacote: `paralax.agents.common.drive.GoogleDrivePdfManager`

### 3.1. Interface e Assinatura
```python
class GoogleDrivePdfManager:
    """Universal manager for downloading PDF documents from Google Drive and publishing to public storage."""

    def __init__(
        self,
        file_id: str,
        storage_bucket_name: str,
        public_base_url: str,
        filename: str,
        cache_ttl_seconds: int = 3600,
        drive_service: Any = None,
        storage_client: Any = None,
    ) -> None:
        ...

    def get_pdf_url(self, force_refresh: bool = False) -> str:
        """Returns the public URL of the synced PDF document, applying two-layer cache and integrity checks."""
        ...

    def verify_integrity(self, expected_md5: str | None = None) -> bool:
        """Validates that the remote storage object matches the Google Drive file hash."""
        ...
```

### 3.2. Regras de Negócio e Comportamento
1. **Content-Type Estrito**: Todo upload no GCS deve registrar explicitamente `content_type="application/pdf"`.
2. **Controle de Versão Transparente**: Se o `md5Checksum` ou `modifiedTime` do Drive não mudou, o manager não realiza novo download nem re-upload, poupando tráfego de rede e CPU.
3. **Fallback Resiliente**: Em caso de indisponibilidade transitória do Google Drive, se o arquivo já foi previamente sincronizado e reside em cache ou no storage público, a URL existente é devolvida sem interromper o atendimento ao cliente.
4. **Respeito ao 12-Factor**: Os parâmetros são injetados pelos agentes via variáveis de ambiente configuradas no ArgoCD.

---

## 4. Testes de Integração com Validação Criptográfica MD5

Para validar a integridade sem mocks parciais:
1. **Download do Google Drive**: O teste baixa os bytes do arquivo de homologação/produção e extrai o `md5_original` via `hashlib.md5(drive_bytes).hexdigest()`.
2. **Execução do Manager / Agente**: O teste aciona `get_pdf_url()` e efetua o download HTTP GET na URL resultante.
3. **Validação Rigorosa**:
   - `HTTP status == 200`
   - Cabeçalho `Content-Type: application/pdf`
   - Prefixo binário `%PDF-`
   - `hashlib.md5(downloaded_bytes).hexdigest() == md5_original`

---

## 5. Ondas Topológicas de Execução

- [ ] **Onda 1 (`paralax-ia/paralax-agents-common`)**:
  - Implementação de `GoogleDrivePdfManager` em `paralax.agents.common.drive`.
  - Suíte de testes unitários com TDD cobrindo cache, TTL, upload, fallback e checagem de MD5.
  - Publicação de release patch no Artifact Registry via CI/CD.
- [ ] **Onda 2 (`paralax-ia/anero-cafe-support`)**:
  - Atualização da dependência `paralax-agents-common` no `pyproject.toml` e `uv.lock`.
  - Refatoração do `anero_cafe/services/catalog_pdf.py` para utilizar o `GoogleDrivePdfManager` da biblioteca comum.
  - Implementação do teste de integração com verificação real de hash MD5 em `tests/integration/test_catalog_pdf_integrity.py`.
- [ ] **Onda 3 (`paralax-ia/argocd`)**:
  - Homologação das variáveis de ambiente em `prod/anero-cafe-support/patch-env.yaml`.
