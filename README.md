# Labs Auction GoExpert

API de leiloes em Go com Gin e MongoDB. O projeto permite:

- Criar leiloes
- Listar e consultar leiloes
- Registrar lances
- Consultar lances por leilao
- Consultar usuario por ID
- Consultar lance vencedor de um leilao

## Stack

- Go 1.20
- Gin
- MongoDB
- Docker / Docker Compose

## Estrutura principal

- `cmd/auction/main.go`: bootstrap da aplicacao e rotas HTTP
- `internal/infra/api/web/controller`: controllers HTTP
- `internal/usecase`: regras de negocio
- `internal/infra/database`: repositorios MongoDB
- `configuration/database/mongodb`: conexao com o banco

## Variaveis de ambiente

Arquivo: `cmd/auction/.env`

Variaveis usadas pela aplicacao:

- `BATCH_INSERT_INTERVAL`: intervalo de flush do lote de lances (ex: `20s`)
- `MAX_BATCH_SIZE`: quantidade maxima de lances por lote (ex: `4`)
- `AUCTION_INTERVAL`: janela de tempo usada na validacao de lances (ex: `20s`)
- `MONGODB_URL`: string de conexao do MongoDB
- `MONGODB_DB`: nome do banco

## Como executar

### Opcao 1: Docker Compose (recomendado)

```bash
make up
```

Para acompanhar logs da API:

```bash
make logs
```

Para derrubar:

```bash
make down
```

API disponivel em: `http://localhost:8080`

### Script automatizado de teste dos endpoints

O projeto possui um script que executa os endpoints na ordem correta:

1. Cria usuarios de teste no MongoDB
2. Cria um leilao
3. Cria varios lances para o mesmo leilao
4. Consulta os dados e valida o vencedor

Executar:

```bash
./scripts/test_endpoints.sh
```

Variaveis opcionais:

- `BASE_URL` (padrao: `http://localhost:8080`)
- `COMPOSE_CMD` (padrao: `docker compose`)
- `MONGO_URI` (padrao: `mongodb://admin:admin@localhost:27017/auctions?authSource=admin`)
- `SLEEP_AFTER_BIDS` (padrao: `2` segundos)

### Opcao 2: Local (sem Docker)

1. Suba um MongoDB acessivel pela URL configurada em `MONGODB_URL`.
2. Garanta o arquivo `cmd/auction/.env` preenchido.
3. Rode:

```bash
go run cmd/auction/main.go
```

## Endpoints e exemplos com curl

Base URL:

```bash
BASE_URL="http://localhost:8080"
```

### 1) Criar leilao

`POST /auction`

```bash
curl -i -X POST "$BASE_URL/auction" \
  -H "Content-Type: application/json" \
  -d '{
    "product_name": "iPhone 14 Pro",
    "category": "smartphone",
    "description": "Aparelho em excelente estado, 256GB, sem riscos.",
    "condition": 1
  }'
```

Resposta esperada: `201 Created` (sem body).

Campos do body:

- `product_name` (string, obrigatorio)
- `category` (string, obrigatorio)
- `description` (string, obrigatorio)
- `condition` (numero)

### 2) Listar leiloes

`GET /auction?status={status}&category={category}&productName={productName}`

```bash
curl -s "$BASE_URL/auction?status=0&category=smartphone&productName=iphone"
```

Observacoes:

- O parametro `status` precisa ser numerico.
- Valores usuais de status: `0` (ativo), `1` (concluido).

### 3) Buscar leilao por ID

`GET /auction/:auctionId`

```bash
curl -s "$BASE_URL/auction/SEU_AUCTION_ID"
```

### 4) Buscar lance vencedor por leilao

`GET /auction/winner/:auctionId`

```bash
curl -s "$BASE_URL/auction/winner/SEU_AUCTION_ID"
```

### 5) Criar lance

`POST /bid`

```bash
curl -i -X POST "$BASE_URL/bid" \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "SEU_USER_ID",
    "auction_id": "SEU_AUCTION_ID",
    "amount": 3500.50
  }'
```

Resposta esperada: `201 Created` (sem body).

### 6) Listar lances por leilao

`GET /bid/:auctionId`

```bash
curl -s "$BASE_URL/bid/SEU_AUCTION_ID"
```

### 7) Buscar usuario por ID

`GET /user/:userId`

```bash
curl -s "$BASE_URL/user/SEU_USER_ID"
```

### 8) Criar usuario

`POST /user`

```bash
curl -i -X POST "$BASE_URL/user" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Joao da Silva"
  }'
```

Resposta esperada: `201 Created` (sem body).

## Fluxo rapido de teste

1. Crie um leilao com `POST /auction`.
2. Liste com `GET /auction?status=0` para obter o `id`.
3. Garanta que existe um usuario no MongoDB (na colecao `users`) e use o `id` dele.
4. Crie lances com `POST /bid`.
5. Consulte os lances com `GET /bid/:auctionId`.
6. Consulte o vencedor com `GET /auction/winner/:auctionId`.

## Formato de erro

A API retorna erros no formato:

```json
{
  "message": "mensagem de erro",
  "err": "bad_request",
  "code": 400,
  "causes": [
    {
      "field": "Campo",
      "message": "descricao"
    }
  ]
}
```

Tipos comuns em `err`:

- `bad_request`
- `not_found`
- `internal_server`

## Para testar via sh

```
make e2e

[18:49:18] Resumo final (resultado esperado)
Leilao........: 60862d7f-f50f-4462-a046-1c8d2e7ae3ad
Produto.......: Produto Script 1773697752
Vencedor......: 3ce78637-73a4-440d-809e-b165d5aecae8
Valor vencedor: 500
Usuarios teste: 3ce78637-73a4-440d-809e-b165d5aecae8, 562558ab-fe53-4474-810a-ddf0b739e203, e7853526-0cce-4607-9ef1-9c73fe5af381

```

## Mermaid

```mermaid
flowchart LR
  Client[Client / Test Script]

  subgraph HTTP
    Client -->|POST /auction| AuctionController[AuctionController]
    Client -->|"GET /auction*"| AuctionsController[AuctionsController]
    Client -->|POST /bid| BidController[BidController]
    Client -->|"GET /auction/winner/:id"| WinnerEndpoint[Winner Endpoint]
  end

  AuctionController -->|calls| AuctionUseCase[AuctionUseCase]
  AuctionsController -->|calls| AuctionUseCase
  BidController -->|calls| BidUseCase[BidUseCase]
  WinnerEndpoint -->|calls| AuctionUseCase

  AuctionUseCase -->|create & validate| AuctionEntity[Auction Entity]
  AuctionUseCase -->|persist with duration| AuctionRepo[AuctionRepository]
  AuctionRepo -->|insert doc| MongoAuctions[(MongoDB: auctions)]

  %% Correção aqui: Aspas para permitir parênteses e caracteres especiais
  AuctionRepo -->|spawn goroutine| AutoCloseGoroutine["goroutine: sleep(AUCTION_DURATION) -> UpdateAuctionStatus(Completed)"]
  AutoCloseGoroutine --> AuctionRepo

  BidUseCase -->|validate| BidEntity[Bid Entity]
  BidUseCase -->|enqueue| BidRepo["BidRepository (batching)"]
  BidRepo -->|flush batch| MongoBids[(MongoDB: bids)]
  BidRepo -->|check| AuctionRepo
  AuctionRepo -->|read status| BidRepo

  AuctionUseCase -->|query winner| BidRepo
  BidRepo -->|return winning bid| AuctionUseCase

  subgraph ENV[Environment]
    AUCTION_DURATION[AUCTION_DURATION]
    AUCTION_INTERVAL[AUCTION_INTERVAL]
    BATCH_INSERT_INTERVAL["BATCH_INSERT_INTERVAL / MAX_BATCH_SIZE"]
  end

  ENV --> AuctionUseCase
  ENV --> BidRepo
  ENV --> BidUseCase

  %% race condition arrow
  MongoBids -.->|race: bid arrives vs auto-close| AutoCloseGoroutine

  classDef repo fill:#f9f,stroke:#333,stroke-width:1px
  class AuctionRepo,BidRepo repo

```
