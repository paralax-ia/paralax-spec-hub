# SPEC-001: Health Check Unificado e Consulta de Status via CRM

> **Product:** [`customer-support-vehicles`](../products/customer-support-vehicles.yaml) | [`paralax-platform`](../products/paralax-platform.yaml)  
> **Business Capability:** [`customer-relationship-management`](../capabilities/customer-relationship-management/capability.yaml)  
> **Scope:** Platform  
> **Bounded Context:** CRM (Supporting Subdomain)  
> **Status:** MERGED  
> **Autor:** Eduardo F. Santos  
> **Data de Criação:** 2026-10-11  
> **Repositórios Impactados:**  
> - `paralax-ia/paralax-evo-crm`  
> - `paralax-ia/customer-support-vehicles`

---

## 1. Visão Geral e Intenção (The "Why")

Padronizar a verificação de saúde e conectividade entre os agentes de atendimento (ADK) e o backend do CRM através de um endpoint comum e tipado. Atualmente, cada agente trata timeout ou falha de conexão de forma heterogênea.

---

## 2. Casos de Uso & Requisitos de Negócio

### Caso de Uso 1: Verificação Periódica de Conectividade
* **Ator:** Agente de Atendimento (`customer-support-vehicles`).
* **Pré-condição:** Instância CRM ativa ou simulada.
* **Fluxo Principal:**
  1. O agente invoca o cliente `CRMAPIClient.health_check()`.
  2. O CRM responde com status `200 OK` e metadados de versão/latência.
* **Critério de Aceitação:**
  - O método `health_check()` não deve lançar exceção em caso de timeout de 2 segundos; deve retornar objeto estruturado `HealthStatus(status="unhealthy")`.

---

## 3. Modelo de Dados e Contratos de Interface

### Modelo Pydantic (em `paralax-evo-crm`):
```python
class HealthStatus(BaseModel):
    status: str = Field(description="'healthy' ou 'unhealthy'")
    version: str = Field(description="Versão do CRM")
    timestamp: datetime
```

---

## 4. Plano de Decomposição (Sub-Tarefas)

- [x] **Sub-tarefa 1 (`paralax-evo-crm`):** [PR #8](https://github.com/paralax-ia/paralax-evo-crm/pull/8)
  - Adicionar método assíncrono `health_check()` na classe `CRMAPIClient`.
  - Adicionar modelo `HealthStatus`.
  - Criar testes unitários em `tests/`.

- [x] **Sub-tarefa 2 (`customer-support-vehicles`):** [PR #7](https://github.com/paralax-ia/customer-support-vehicles/pull/7)
  - Adicionar chamada de verificação de saúde na rota `/crm/health`.
  - Validar fallback seguro caso o CRM esteja indisponível.

