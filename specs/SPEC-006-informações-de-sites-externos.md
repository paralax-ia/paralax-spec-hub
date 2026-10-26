---
spec_id: SPEC-006
title: Leitura de Anúncios em Plataformas Externas (Mercado Livre, OLX) com Fallback
  por LLM na URL e Busca no Estoque da Concessionária
product:
- customer-support-vehicles
- paralax-platform
capability: conversational-ai-agent
scope: product-specific
bounded_context: Atendimento Automotivo & Busca de Veículos (Core Subdomain)
origin_module: customer-support-vehicles
target_repositories:
- repo: paralax-ia/customer-support-vehicles
  wave: 1
  role: ai-agent
status: APPROVED
---

# SPEC-006: Leitura de Anúncios em Plataformas Externas (Mercado Livre, OLX) com Fallback por LLM na URL e Busca no Estoque da Concessionária

> **Product:** [`customer-support-vehicles`](../products/customer-support-vehicles.yaml) | [`paralax-platform`](../products/paralax-platform.yaml)  
> **Business Capability:** [`conversational-ai-agent`](../capabilities/conversational-ai-agent/capability.yaml)  
> **Scope:** Product-Specific (Atendimento Concessionária Brasília Automóveis)  
> **Bounded Context:** Atendimento Automotivo & Busca de Veículos (Core Subdomain)  
> **Status:** DRAFT  
> **Autor:** Eduardo F. Santos  
> **Data de Criação:** 2026-10-25  
> **Arquitetura 12-Factor:** Zero arquivos de configuração salvos no Git; toda configuração é gerada exclusivamente a partir de variáveis de ambiente  
> **Diretriz de Prompts:** Prompts de sistema e templates de instrução para LLM devem ser estritamente redigidos em inglês  
> **Repositórios Impactados:**  
> - `paralax-ia/customer-support-vehicles` (Onda 1 - Inspeção de Anúncios Externos com Fallback LLM de URL Amigável, Integração de Busca no Estoque e Instruções da Agente)

---

## 1. Contexto e Motivação

No atendimento digital de concessionárias e revendas de veículos (como a **Brasília Automóveis** via WhatsApp e canais digitais), é extremamente comum que clientes em potencial enviem links de anúncios encontrados em plataformas externas de vendas (como **Mercado Livre**, **OLX**, **Webmotors**, **iCarros**, redes sociais ou agregadores) acompanhados de dúvidas comerciais como:
- *"Oi, vi esse anúncio aqui: https://df.olx.com.br/... Vocês ainda têm esse carro no estoque?"*
- *"Qual o menor valor que vocês fazem nesse carro do anúncio? https://carro.mercadolivre.com.br/MLB-..."*
- *"Vocês pegam o meu usado na troca desse carro aqui? [link]"*

### O Desafio Arquitetural e de Domínio
1. **Divergência entre o Site Hospedeiro do Anúncio e o Site de Inventário:**
   O site onde o anúncio está hospedado (plataformas de marketplace como Mercado Livre e OLX) **não é o mesmo** site onde o estoque e o catálogo oficial da loja estão publicados (`https://brasiliaautomoveis.com.br`).
2. **Limitação da Ferramenta Atual (`get_vehicle_details`):**
   Atualmente, o agente `customer-support-vehicles` possui apenas a ferramenta `get_vehicle_details(url: str)`, que possui validação rígida de domínio (`if not url.startswith("https://brasiliaautomoveis.com.br"): return "❌ URL fornecida é inválida ou não permitida."`). Ao receber um link do Mercado Livre ou OLX, o agente rejeita a URL, impossibilitando a compreensão da demanda do cliente e prejudicando a conversão de vendas.
3. **Bloqueios Anti-Bot e Páginas Dinâmicas nas Plataformas Externas:**
   Marketplaces como Mercado Livre e OLX frequentemente implementam proteções anti-bot (Cloudflare, Akamai, DataDome, desafios CAPTCHA) ou desativam anúncios expirados (HTTP 404/410), o que pode impedir o download do HTML completo do anúncio por requisições HTTP automatizadas.
4. **Fallback Inteligente via LLM para URLs Amigáveis:**
   Os anúncios em plataformas de classificados utilizam invariavelmente **URLs amigáveis (slugs semânticos)** estruturados para SEO, tais como:
   - `https://carro.mercadolivre.com.br/MLB-123456789-toyota-corolla-20-xei-2021-_JM`
   - `https://df.olx.com.br/distrito-federal-e-regiao/autos-e-pecas/carros-vans-e-utilitarios/toyota-corolla-xei-2-0-flex-aut-2021-123456789`
   - `https://www.webmotors.com.br/comprar/honda/civic/20-16v-gasolina-touring-4p-cvt/4-portas/2020/12345678`
   Mesmo quando o conteúdo HTML da página não puder ser lido diretamente, o sistema deve acionar um **fallback por LLM** especializado em inferir marca (`make`), modelo (`model`), ano (`year`) e versão (`version`) a partir dos tokens contidos na URL amigável.
5. **Necessidade de Extração e Busca Orquestrada:**
   O agente deve ser capaz de:
   - Tentar acessar e extrair o conteúdo do anúncio externo (Mercado Livre, OLX, etc.).
   - Caso a leitura do HTML falhe (bloqueio, CAPTCHA, 403, 404, timeout), acionar imediatamente o fallback LLM na URL amigável para identificar o veículo.
   - Sintetizar o termo de pesquisa comercialmente ideal (ex: `"Corolla 2021"` ou `"Civic Touring 2020"`).
   - Executar a busca no site de estoque da loja (`vehicle_search` em `brasiliaautomoveis.com.br`).
   - Apresentar as informações oficiais da concessionária (`get_vehicle_details`), ou oferecer modelos similares caso a unidade exata não esteja disponível no estoque.

### Diretrizes de Engenharia e Arquitetura
- **Prompts Estritamente em Inglês (English-Only Prompts):** Todos os prompts de sistema (`vehicles/prompts.py`), instruções para agentes Google ADK e templates de prompt para invocação direta de modelos LLM (como `URL_VEHICLE_EXTRACTION_PROMPT_TEMPLATE` em `vehicles/tools/ad_reader.py`) devem ser redigidos exclusivamente em inglês. A utilização do inglês como idioma dos prompts assegura máxima fidelidade às instruções de sistema, menor ambiguidade na extração de atributos estruturados Pydantic e consistência com os padrões de engenharia da plataforma Paralax IA.
- **Princípio 12-Factor (Zero Config no Git):** Qualquer parâmetro de infraestrutura (timeouts de requisição, lista de plataformas suportadas, domínio base de estoque) deve ser configurável exclusivamente via variáveis de ambiente (`os.environ` / Pydantic Settings), com bloqueio estrito em `.gitignore` para proibir arquivos `.env` ou `.yaml` versionados no Git.
- **Resiliência e Proteção Contra Bloqueios:** Requisições a sites externos devem utilizar rotação de cabeçalhos HTTP legítimos (`User-Agent`, `Accept-Language`), timeouts curtos configuráveis (padrão de 10s) e tratamento de falhas sem gerar exceções não tratadas no agente.
- **Segurança contra SSRF (Server-Side Request Forgery):** A ferramenta deve validar esquemas permitidos (`http`/`https`) e bloquear explicitamente requisições para endereços de rede local/privada (ex: `127.0.0.1`, `localhost`, `10.0.0.0/8`, `192.168.0.0/16`, `169.254.169.254`).
- **Padrões de Código Python (PEP 8, Google Docstrings, Sem Funções Aninhadas):** O código deve seguir estritamente as diretrizes corporativas, sem funções internas/aninhadas, sem blocos `try...except` aninhados ou em imports, e com docstrings Google em todas as funções e classes.

---

## 2. Escopo e Repositórios Afetados

```
┌────────────────────────────────────────────────────────────────────────┐
│                       ONDA 1 (PENDENTE - TASK-1)                       │
│                 paralax-ia/customer-support-vehicles                   │
│  • Módulo de inspeção de anúncios externos `vehicles/tools/ad_reader.py`│
│  • Modelos Pydantic tipados: `ExternalAdVehicleInfo`,                  │
│    `ExternalAdInspectionResult` e `AdPlatformType`                     │
│  • Função ferramenta ADK `inspect_external_vehicle_ad(url: str)`       │
│  • Pipeline de 2 camadas: Extração HTML ➔ Fallback LLM em URL amigável │
│  • Prompt `URL_VEHICLE_EXTRACTION_PROMPT_TEMPLATE` em inglês estrito  │
│  • Validação de SSRF e extração resiliente (JSON-LD, OpenGraph e DOM) │
│  • Integração e registro da ferramenta em `vehicles/agent.py`          │
│  • Parametrização 12-Factor em `vehicles/config.py`                    │
│  • Atualização das instruções da agente Isa em `vehicles/prompts.py`   │
│    (em inglês)                                                         │
│  • Suíte completa de testes unitários em `tests/unit/`                 │
└────────────────────────────────────────────────────────────────────────┘
```

- [ ] **[Onda 1] `paralax-ia/customer-support-vehicles` (`task-1`):**
  - Implementar o módulo `vehicles/tools/ad_reader.py`:
    - Modelos de dados Pydantic: `AdPlatformType`, `ExternalAdVehicleInfo` e `ExternalAdInspectionResult`.
    - Função de validação de segurança `validate_external_url(url: str) -> bool` prevenindo SSRF contra IPs privados ou esquemas não permitidos.
    - Parsers de metadados para plataformas reconhecidas:
      - **Mercado Livre:** Extração via JSON-LD (`Product`/`Vehicle`), meta tags Open Graph e seletores CSS estruturados (`ui-pdp-title`, `ui-pdp-specs__table`, ficha técnica).
      - **OLX:** Extração via Schema.org JSON-LD, meta tags Open Graph e seletores de características do anúncio.
      - **Classificados Genéricos / Portais Externos:** Extração fallback via Open Graph (`og:title`, `og:description`) e busca semântica de padrões veiculares (marca, modelo e ano de 4 dígitos).
    - **Fallback de Extração de URL Amigável via LLM (`identify_vehicle_from_url_with_llm`):**
      - Quando a requisição HTTP falhar (403, 404, WAF, CAPTCHA, timeout) ou não retornar dados suficientes, submeter a URL normalizada ao LLM (`gemini-3.7-flash` ou modelo configurado).
      - O template de prompt `URL_VEHICLE_EXTRACTION_PROMPT_TEMPLATE` deve ser **obrigatoriamente redigido em inglês**.
      - O LLM extrai marca, modelo, ano e versão diretamente dos segmentos da URL amigável e sintetiza o `search_query`.
    - Função ferramenta ADK `@safe_tool` e `@observe`: `inspect_external_vehicle_ad(url: str) -> dict[str, Any]`.
  - Atualizar `vehicles/config.py`:
    - Adicionar `INVENTORY_BASE_URL: str = Field(default="https://brasiliaautomoveis.com.br", validation_alias="INVENTORY_BASE_URL")`.
    - Adicionar `AD_REQUEST_TIMEOUT_SECONDS: float = Field(default=10.0, validation_alias="AD_REQUEST_TIMEOUT_SECONDS")`.
    - Garantir geração estrita via variáveis de ambiente sem arquivos de configuração versionados no Git.
  - Atualizar `vehicles/tools/vehicle.py`:
    - Fazer com que `get_vehicle_details` utilize `config.INVENTORY_BASE_URL` em vez de URL hardcoded.
    - Se uma URL informada for de anúncio externo reconhecido (ex: Mercado Livre ou OLX), retornar mensagem orientando o modelo a utilizar `inspect_external_vehicle_ad`.
  - Atualizar `vehicles/agent.py`:
    - Importar e registrar `inspect_external_vehicle_ad` na lista de ferramentas (`tools`) do `root_agent`.
  - Atualizar `vehicles/prompts.py`:
    - Documentar na seção `<tools_and_search>` a nova ferramenta `inspect_external_vehicle_ad` estritamente em inglês.
    - Instruir a agente Isa sobre o fluxo em 3 passos quando o cliente fornecer link de anúncio externo:
      1. Executar `inspect_external_vehicle_ad(url)` para extrair marca, modelo e ano do carro anunciado (com suporte a fallback automático de URL amigável).
      2. Executar `vehicle_search(query=search_query)` no catálogo oficial da Brasília Automóveis.
      3. Se encontrado, detalhar as opções com `get_vehicle_details(url)` da loja; se não encontrado, informar com cordialidade que a unidade exata não está no estoque atual e apresentar similares.
  - Criar testes unitários em `tests/unit/test_ad_reader.py`:
    - Testes com mocks de HTML do Mercado Livre e da OLX.
    - Testes de extração via JSON-LD e OpenGraph.
    - Testes do **fallback de URL amigável via LLM** simulando respostas HTTP 403, 404, Cloudflare e timeout, assegurando que o prompt enviado ao LLM está em inglês.
    - Testes de proteção contra SSRF (bloqueio de `127.0.0.1`, `192.168.1.1`, `localhost`, `169.254.169.254`).
    - Testes do prompt e da integração da ferramenta no `root_agent`.

---

## 3. Contratos de Interface

### 3.1. Modelos de Domínio (`vehicles/tools/ad_reader.py`)

```python
from typing import Any, Literal
from pydantic import BaseModel, ConfigDict, Field

AdPlatformType = Literal["mercadolivre", "olx", "webmotors", "icarros", "generic"]
ExtractionSourceType = Literal["page_content", "url_slug_llm", "none"]


class ExternalAdVehicleInfo(BaseModel):
    """Informações estruturadas do veículo extraídas de um anúncio externo."""

    title: str = Field(
        default="",
        description="Título completo anunciado na plataforma externa.",
    )
    make: str = Field(
        default="",
        description="Marca ou montadora do veículo (ex: Toyota, Volkswagen, Fiat, Chevrolet, Honda).",
    )
    model: str = Field(
        default="",
        description="Modelo principal do veículo (ex: Corolla, Gol, Onix, Civic, Compass).",
    )
    year: int | None = Field(
        default=None,
        description="Ano de fabricação ou modelo identificado (ex: 2021).",
    )
    version: str = Field(
        default="",
        description="Versão, acabamento ou motorização identificada (ex: '2.0 XEi', '1.0 Turbo').",
    )
    price: str = Field(
        default="",
        description="Preço anunciado no link original, se disponível (ex: 'R$ 115.000').",
    )
    mileage: str = Field(
        default="",
        description="Quilometragem informada no anúncio externo, se disponível.",
    )
    fuel: str = Field(
        default="",
        description="Combustível informado no anúncio (ex: Flex, Gasolina, Diesel).",
    )
    transmission: str = Field(
        default="",
        description="Câmbio informado no anúncio (ex: Automático, Manual).",
    )
    search_query: str = Field(
        default="",
        description="Termo sintetizado otimizado para busca no inventário da concessionária (ex: 'Corolla 2021').",
    )
    raw_specs: dict[str, Any] = Field(
        default_factory=dict,
        description="Dicionário de características brutas complementares extraídas da página.",
    )
    model_config = ConfigDict(extra="allow")


class ExternalAdInspectionResult(BaseModel):
    """Resultado da inspeção de um anúncio veicular externo."""

    success: bool = Field(
        description="Indica se o veículo foi identificado com sucesso (via conteúdo da página ou fallback de URL).",
    )
    url: str = Field(
        description="URL do anúncio externo inspecionado.",
    )
    platform: AdPlatformType = Field(
        description="Plataforma de anúncio detectada a partir da URL.",
    )
    extraction_source: ExtractionSourceType = Field(
        default="none",
        description="Origem da extração dos dados: 'page_content' (HTML) ou 'url_slug_llm' (fallback na URL amigável).",
    )
    fallback_used: bool = Field(
        default=False,
        description="True caso tenha sido necessário recorrer ao fallback por LLM na URL amigável.",
    )
    vehicle: ExternalAdVehicleInfo = Field(
        default_factory=ExternalAdVehicleInfo,
        description="Dados do veículo identificado a partir do anúncio.",
    )
    search_query: str = Field(
        default="",
        description="Sugestão de query para busca imediata no site da loja (`vehicle_search`).",
    )
    message: str = Field(
        default="",
        description="Mensagem descritiva do resultado da leitura ou instrução em caso de falha.",
    )
    model_config = ConfigDict(extra="allow")
```

---

### 3.2. Contrato de Fallback via LLM na URL Amigável com Prompt em Inglês (`vehicles/tools/ad_reader.py`)

Função responsável por processar slugs semânticos quando a requisição HTTP da página for bloqueada ou indisponível, utilizando **template de prompt estritamente em inglês**:

```python
from typing import Any, Optional
from google import genai
from google.genai.types import GenerateContentConfig

URL_VEHICLE_EXTRACTION_PROMPT_TEMPLATE = """You are an expert specialist in the Brazilian automotive vehicle market.
A customer sent a link to a vehicle advertisement, but the web page could not be accessed directly due to technical restrictions, anti-bot protections, or an expired listing.
Online marketplaces and automotive platforms (such as Mercado Livre, OLX, Webmotors, and iCarros) use SEO-friendly, semantic URLs containing vehicle make, model, trim/version, and year within the path segments (slug).

Analyze the provided friendly URL and accurately extract the vehicle information into the structured schema:
- make: Manufacturer or brand of the vehicle (e.g. Toyota, Honda, Volkswagen, Chevrolet, Fiat, Hyundai, Jeep).
- model: Main vehicle model name (e.g. Corolla, Civic, Gol, Onix, Compass, Creta, HB20).
- year: Manufacturing or model year as an integer (e.g. 2021), if identified in the URL slug.
- version: Vehicle trim level, engine specification, or version (e.g. '2.0 XEi', 'Touring', '1.0 Turbo', 'Flex Aut'), if identified.
- search_query: Concise, normalized search query optimized for searching the dealership inventory catalog (e.g. 'Corolla 2021' or 'Civic Touring').

Advertisement URL:
{url}"""


def identify_vehicle_from_url_with_llm(
    url: str,
    app_config: Any = None,
    llm_client: Optional[genai.Client] = None,
) -> Optional[ExternalAdVehicleInfo]:
    """Extrai informações do veículo a partir de uma URL amigável utilizando o LLM com prompt em inglês.

    Atua como mecanismo de contingência (fallback) quando a página do anúncio
    não puder ser lida por HTTP (bloqueio 403/CAPTCHA, 404 ou timeout). O prompt
    submetido ao modelo é redigido estritamente em inglês para maximizar precisão
    e conformidade estruturada.

    Args:
        url: URL amigável do anúncio fornecida pelo cliente.
        app_config: Instância de configuração da aplicação.
        llm_client: Cliente opcional do Google GenAI para injeção em testes.

    Returns:
        Instância de ExternalAdVehicleInfo com make, model, year e search_query
        preenchidos pelo LLM, ou None se a URL for opaca ou não contiver dados veiculares.
    """
    ...
```

---

### 3.3. Contrato da Ferramenta ADK (`vehicles/tools/ad_reader.py`)

A função deve ser decorada com `@safe_tool` e `@observe` e registrada no agente Google ADK:

```python
from typing import Any
from langfuse import observe
from paralax.agents.common.tools import safe_tool


@observe(capture_input=False, capture_output=False)
@safe_tool
def inspect_external_vehicle_ad(url: str) -> dict[str, Any]:
    """Inspeciona um anúncio de veículo em links externos (Mercado Livre, OLX, Webmotors, etc.).

    Esta ferramenta lê o conteúdo da página do anúncio fornecida pelo cliente ou, caso
    a página esteja bloqueada/indisponível, executa um fallback via LLM analisando a URL
    amigável para identificar marca, modelo, ano e versão do carro anunciado.
    Em seguida, gera o termo de busca ideal para localizar o veículo correspondente no
    estoque oficial da Brasília Automóveis através da ferramenta `vehicle_search`.

    Args:
        url: URL completa do anúncio externo enviada pelo cliente.

    Returns:
        Dicionário com o resultado da inspeção contendo:
        - 'success' (bool): True se o anúncio ou URL foi interpretado com sucesso.
        - 'platform' (str): Plataforma identificada ('mercadolivre', 'olx', 'generic').
        - 'extraction_source' (str): 'page_content' ou 'url_slug_llm'.
        - 'fallback_used' (bool): True se foi utilizado o fallback na URL amigável.
        - 'vehicle' (dict): Atributos do carro (make, model, year, version, price).
        - 'search_query' (str): Termo sugerido para buscar em `vehicle_search`.
        - 'message' (str): Mensagem amigável com o resumo do que foi identificado.
    """
    ...
```

---

### 3.4. Configurações 12-Factor (`vehicles/config.py`)

Configurações geradas dinamicamente exclusivamente a partir de variáveis de ambiente:

```python
class Config(BaseSettings):
    # Configurações de Inventário e Inspeção de Anúncios Externos
    INVENTORY_BASE_URL: str = Field(
        default="https://brasiliaautomoveis.com.br",
        validation_alias="INVENTORY_BASE_URL",
    )
    AD_REQUEST_TIMEOUT_SECONDS: float = Field(
        default=10.0,
        validation_alias="AD_REQUEST_TIMEOUT_SECONDS",
    )
```

---

### 3.5. Instruções da Agente Isa (`vehicles/prompts.py`)

Atualização na seção `<tools_and_search>`, estritamente redigida em inglês:

```markdown
<tools_and_search>
You have three tools available:
- `inspect_external_vehicle_ad`: Receives a link from an external ad platform (such as Mercado Livre, OLX, Webmotors, etc.), reads its content, or automatically falls back to an LLM analysis of the friendly URL slug if the ad page is blocked or offline, returning vehicle data and a `search_query`.
- `vehicle_search`: Searches for vehicle ads in the official Brasília Automóveis inventory (https://brasiliaautomoveis.com.br) by terms (brand, model, year, category).
- `get_vehicle_details`: Receives an ad URL from Brasília Automóveis and extracts the complete data from the page.

HANDLING EXTERNAL AD LINKS (MERCADO LIVRE, OLX, ETC.):
When a customer sends a link to an ad (e.g., Mercado Livre, OLX, or external website):
1. ALWAYS call `inspect_external_vehicle_ad(url)` first to extract and identify which car the customer is looking at.
2. If `inspect_external_vehicle_ad` succeeds (whether extracted from the page content or via URL slug fallback):
   - Use the returned `search_query` (or the identified make/model/year) to search Brasília Automóveis inventory using `vehicle_search(query=search_query)`.
   - If matches are found on Brasília Automóveis:
     - Call `get_vehicle_details(url)` on the matching inventory link(s).
     - Inform the customer: "Identifiquei o anúncio que você enviou: [Carro]. Temos opções desse modelo disponíveis no nosso estoque!" and present the official store details.
   - If NO matches are found on Brasília Automóveis:
     - Politely inform: "Vi que você tem interesse no [Carro do anúncio]. No momento não temos essa unidade exata no estoque da Brasília Automóveis, mas posso te mostrar opções semelhantes ou verificar com nossos consultores se há previsão de entrada!"
3. If both the page reading and the URL slug analysis fail (e.g., an opaque or shortened link with no recognizable vehicle data):
   - Politely ask: "Não consegui identificar o veículo desse link no momento. Você poderia me dizer qual é o modelo, marca e ano do carro para eu buscar no nosso estoque?"
</tools_and_search>
```

---

## 4. Critérios de Aceitação (Gherkin)

### Cenário 1: Leitura Direta de Anúncio do Mercado Livre via Conteúdo HTML
- **Dado** que o cliente envia no chat um link de anúncio do Mercado Livre (`https://carro.mercadolivre.com.br/MLB-123456789-toyota-corolla-20-xei-2021-_JM`)
- **E** a página HTML é acessada com sucesso (HTTP 200)
- **Quando** a ferramenta `inspect_external_vehicle_ad` for executada
- **Então** o resultado deve ter `success=True`, `platform="mercadolivre"`, `extraction_source="page_content"` e `fallback_used=False`
- **E** o veículo identificado deve conter `make="Toyota"`, `model="Corolla"` e `year=2021`
- **E** a sugestão `search_query` deve conter `"Corolla 2021"`
- **E** o agente deve invocar `vehicle_search(query="Corolla 2021")` no site da concessionária.

### Cenário 2: Fallback por LLM na URL Amigável com Prompt em Inglês em Anúncio com Bloqueio Anti-Bot
- **Dado** que o cliente envia um link de anúncio da OLX com URL amigável (`https://df.olx.com.br/distrito-federal-e-regiao/autos-e-pecas/carros-vans-e-utilitarios/toyota-corolla-xei-2-0-flex-aut-2021-123456789`)
- **E** a requisição HTTP da página retorna erro 403, desafio de WAF/CAPTCHA ou timeout
- **Quando** a ferramenta `inspect_external_vehicle_ad` acionar a função de fallback `identify_vehicle_from_url_with_llm`
- **Então** o prompt submetido ao modelo LLM deve estar integralmente redigido em inglês (`URL_VEHICLE_EXTRACTION_PROMPT_TEMPLATE`)
- **E** o LLM deve analisar os tokens da URL amigável e extrair `make="Toyota"`, `model="Corolla"`, `year=2021` e `version="2.0 XEi"`
- **E** o resultado da inspeção deve retornar `success=True`, `fallback_used=True` e `extraction_source="url_slug_llm"`
- **E** o agente deve utilizar o `search_query` obtido para consultar o estoque da loja sem exigir que o cliente digite o nome do carro manualmente.

### Cenário 3: Fallback por LLM na URL Amigável para Anúncio Expirado ou Removido (HTTP 404 / 410)
- **Dado** que o cliente envia uma URL amigável do Mercado Livre referente a um anúncio finalizado (`https://carro.mercadolivre.com.br/MLB-987654321-honda-civic-touring-2020-_JM`)
- **E** o servidor externo responde com status HTTP 404 Not Found
- **Quando** a ferramenta `inspect_external_vehicle_ad` executar a inspeção
- **Então** o fallback por LLM deve identificar com sucesso `make="Honda"`, `model="Civic"`, `year=2020` e `version="Touring"` a partir do slug
- **E** a ferramenta deve retornar `success=True`, permitindo que o agente verifique se a Brasília Automóveis possui o modelo equivalente em estoque.

### Cenário 4: Falha Completa em URL Sem Conteúdo Amigável e Bloqueada
- **Dado** que o cliente envia uma URL encurtada ou opaca sem slug semântico (ex: `https://bit.ly/3xpto12` ou `https://portal.exemplo.com.br/anuncio?id=9999`)
- **E** a requisição HTTP da página falha ou é bloqueada
- **Quando** a ferramenta tentar extrair dados do conteúdo e acionar o fallback por LLM
- **Então** o LLM deve indicar que a URL não contém dados veiculares discerníveis
- **E** a ferramenta deve retornar `success=False` com mensagem amigável
- **E** o agente deve solicitar cordialmente ao cliente o modelo, marca e ano do carro desejado.

### Cenário 5: Bloqueio de Segurança contra SSRF (Server-Side Request Forgery)
- **Dado** que uma URL direcionando para endereço de rede privada ou metadata de nuvem seja informada (ex: `http://127.0.0.1:8080`, `http://localhost`, `http://192.168.1.1` ou `http://169.254.169.254/latest/meta-data`)
- **Quando** a função `validate_external_url` for chamada
- **Então** ela deve retornar `False`
- **E** a ferramenta `inspect_external_vehicle_ad` deve abortar a execução imediatamente com erro de segurança, sem disparar requisições HTTP e sem acionar o LLM.

### Cenário 6: Conformidade 12-Factor e Ausência de Configurações no Git
- **Dado** o repositório `customer-support-vehicles`
- **Quando** a classe `Config` for instanciada
- **Então** `INVENTORY_BASE_URL` e `AD_REQUEST_TIMEOUT_SECONDS` devem ser inicializadas a partir de variáveis de ambiente
- **E** nenhum arquivo `.env`, `.yaml` ou `.json` com configurações deve estar rastreado no Git.

---

## 5. Plano de Rollout e Compatibilidade

1. **Sequência de Implementação por Ondas:**
   - **Onda 1 (`paralax-ia/customer-support-vehicles`):**
     1. Criação do módulo `vehicles/tools/ad_reader.py` contendo os modelos Pydantic, validação anti-SSRF, parsers de HTML e a função de fallback `identify_vehicle_from_url_with_llm` com prompt em inglês.
     2. Parametrização de `vehicles/config.py` e atualização de `vehicles/tools/vehicle.py` para usar `config.INVENTORY_BASE_URL`.
     3. Registro da ferramenta em `vehicles/agent.py` e atualização das instruções em `vehicles/prompts.py` (em inglês).
     4. Suíte de testes unitários cobrindo extração direta de HTML, fallback de URL amigável por LLM, proteção SSRF e tratamento de erros.
     5. Validação integral com `just verify`.
2. **Compatibilidade e Rollback:**
   - A alteração é 100% aditiva.
   - Ferramentas existentes (`vehicle_search` e `get_vehicle_details`) preservam sua assinatura e comportamento.
   - Caso a nova ferramenta necessite ser desabilitada, basta removê-la da lista de `tools` em `vehicles/agent.py`, retornando ao comportamento prévio sem impacto ao sistema.
