# SPEC-002: Mensageria e Gestão de Expediente do CRM

> **Business Capability:** [`customer-relationship-management`](../capabilities/customer-relationship-management/capability.yaml)  
> **Bounded Context:** CRM (Supporting Subdomain)  
> **Status:** MERGED  
> **Autor:** Eduardo F. Santos  
> **Data de Criação:** 2026-10-12  
> **Repositórios Impactados:**  
> - `paralax-ia/paralax-evo-crm`  
> - `paralax-ia/customer-support-vehicles`

---

## 1. Visão Geral e Intenção (The "Why")

Garantir o envio confiável de mensagens geradas por agentes de IA para conversas do CRM via VPC interna e regular o atendimento ao cliente com base nos horários de funcionamento (working hours) configurados nas caixas de entrada (inboxes) do CRM.

---

## 2. Casos de Uso & Requisitos de Negócio

### Caso de Uso 1: Envio de Mensagem pelo Agente de IA
* **Ator:** Agente de Atendimento (`customer-support-vehicles`).
* **Pré-condição:** Conversa ativa no CRM com `context_id`.
* **Fluxo Principal:**
  1. O agente de IA invoca `CRMAPIClient.send_message()`.
  2. A requisição é despachada para `/api/v1/conversations/{context_id}/messages` com cabeçalho `X-Service-Token`.
  3. O payload inclui `sender_type: AgentBot` e o `sender_id` numérico correspondente.
* **Critério de Aceitação:**
  - O CRM deve atribuir a autoria ao bot do agente, evitando confusão com atendentes humanos.
  - Se o token não estiver configurado, um aviso é logado sem quebrar a execução.

### Caso de Uso 2: Avaliação de Expediente Comercial (Out of Office)
* **Ator:** Agente de Atendimento (`customer-support-vehicles`).
* **Pré-condição:** Metadados da caixa de entrada obtidos via CRM API.
* **Fluxo Principal:**
  1. O cliente invoca `check_out_of_office(inbox_data)`.
  2. Se `working_hours_enabled` for `False`, retorna `is_out_of_office = False`.
  3. Se habilitado e o horário atual estiver dentro da janela do dia, retorna `is_out_of_office = False`.
  4. Se estiver fora da janela ou fechado o dia todo, retorna `is_out_of_office = True`, horário atual e sumário textual do expediente.
* **Critério de Aceitação:**
  - Horários são interpretados no fuso horário configurado na inbox (ex: America/Sao_Paulo).
  - O sumário de expediente lista dias e intervalos abertos ordenados de domingo a sábado.

---

## 3. Modelo de Dados e Contratos de Interface

### Modelo Pydantic e Assinatura de Métodos (em `paralax-evo-crm`):
```python
class CRMAPIClient:
    async def send_message(
        self,
        context_id: str,
        text: str,
        sender_id: int | str | None,
        sender_type: str = "AgentBot",
    ) -> None: ...

    def check_out_of_office(
        self,
        inbox_data: dict[str, Any],
    ) -> tuple[bool, str, str]: ...

    def get_schedule_summary(
        self,
        working_hours: list,
    ) -> str: ...
```

---

## 4. Plano de Decomposição (Sub-Tarefas)

- [x] **Sub-tarefa 1 (`paralax-evo-crm`):**
  - Implementar método assíncrono `send_message()` com suporte a `AgentBot`.
  - Implementar métodos de cálculo de expediente `check_out_of_office()` e `get_schedule_summary()`.
  - Criar testes unitários em `tests/paralax/evo/crm/test_client.py`.

- [x] **Sub-tarefa 2 (`customer-support-vehicles`):**
  - Integrar envio de mensagens e verificação de horário comercial nos fluxos de atendimento do agente de veículos.
