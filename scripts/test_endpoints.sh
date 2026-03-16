#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
COMPOSE_CMD="${COMPOSE_CMD:-docker compose}"
MONGO_URI="${MONGO_URI:-mongodb://admin:admin@localhost:27017/auctions?authSource=admin}"
SLEEP_AFTER_BIDS="${SLEEP_AFTER_BIDS:-2}"

HTTP_BODY=""
HTTP_CODE=""

log() {
  printf '\n[%s] %s\n' "$(date +"%H:%M:%S")" "$1"
}

fail() {
  echo "ERRO: $1" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Comando obrigatorio nao encontrado: $1"
}

perform_request() {
  local method="$1"
  local url="$2"
  local data="${3:-}"
  local response

  if [[ -n "$data" ]]; then
    response="$(curl -sS -w $'\n%{http_code}' -X "$method" "$url" -H "Content-Type: application/json" -d "$data")"
  else
    response="$(curl -sS -w $'\n%{http_code}' -X "$method" "$url")"
  fi

  HTTP_BODY="${response%$'\n'*}"
  HTTP_CODE="${response##*$'\n'}"
}

assert_status() {
  local expected="$1"
  local context="$2"

  if [[ "$HTTP_CODE" != "$expected" ]]; then
    echo "Falha em: $context" >&2
    echo "Status esperado: $expected" >&2
    echo "Status recebido: $HTTP_CODE" >&2
    echo "Body recebido: $HTTP_BODY" >&2
    exit 1
  fi
}

require_cmd curl
require_cmd jq
require_cmd uuidgen
require_cmd docker

log "Validando disponibilidade da API em $BASE_URL"
perform_request GET "$BASE_URL/auction?status=0"
if [[ "$HTTP_CODE" != "200" ]]; then
  fail "API indisponivel em $BASE_URL. Suba com: make up"
fi

log "Preparando usuarios no MongoDB para testar endpoint /user e criar lances"
USER_1="$(uuidgen | tr '[:upper:]' '[:lower:]')"
USER_2="$(uuidgen | tr '[:upper:]' '[:lower:]')"
USER_3="$(uuidgen | tr '[:upper:]' '[:lower:]')"

MONGO_SCRIPT=$(cat <<EOF
db.users.updateOne({_id: "$USER_1"}, {\$set: {name: "Bidder Script 1"}}, {upsert: true});
db.users.updateOne({_id: "$USER_2"}, {\$set: {name: "Bidder Script 2"}}, {upsert: true});
db.users.updateOne({_id: "$USER_3"}, {\$set: {name: "Bidder Script 3"}}, {upsert: true});
print("ok");
EOF
)

if ! $COMPOSE_CMD exec -T mongodb mongosh "$MONGO_URI" --quiet --eval "$MONGO_SCRIPT" >/dev/null 2>&1; then
  fail "Nao foi possivel inserir usuarios no MongoDB via docker compose. Verifique se os containers estao ativos."
fi

log "Criando leilao"
RUN_ID="$(date +%s)"
PRODUCT_NAME="Produto Script $RUN_ID"
AUCTION_PAYLOAD="$(jq -n --arg product "$PRODUCT_NAME" '{product_name: $product, category: "eletronicos", description: "Produto criado automaticamente para teste de varios lances.", condition: 1}')"

perform_request POST "$BASE_URL/auction" "$AUCTION_PAYLOAD"
assert_status 201 "POST /auction"

log "Buscando o ID do leilao criado"
perform_request GET "$BASE_URL/auction?status=0"
assert_status 200 "GET /auction?status=0"
AUCTION_ID="$(echo "$HTTP_BODY" | jq -r --arg product "$PRODUCT_NAME" 'map(select(.product_name == $product)) | last | .id // empty')"

if [[ -z "$AUCTION_ID" ]]; then
  fail "Nao foi possivel localizar o leilao criado na listagem"
fi

log "Leilao criado com ID: $AUCTION_ID"

log "Consultando leilao por ID"
perform_request GET "$BASE_URL/auction/$AUCTION_ID"
assert_status 200 "GET /auction/:auctionId"

declare -a BID_USERS=("$USER_1" "$USER_2" "$USER_3" "$USER_1")
declare -a BID_AMOUNTS=("100.00" "350.00" "250.00" "500.00")

log "Criando varios lances para o mesmo leilao"
for i in "${!BID_USERS[@]}"; do
  payload="$(jq -n --arg user_id "${BID_USERS[$i]}" --arg auction_id "$AUCTION_ID" --argjson amount "${BID_AMOUNTS[$i]}" '{user_id: $user_id, auction_id: $auction_id, amount: $amount}')"
  perform_request POST "$BASE_URL/bid" "$payload"
  assert_status 201 "POST /bid (lance $((i + 1)))"
  echo "Lance $((i + 1)) enviado: user=${BID_USERS[$i]} amount=${BID_AMOUNTS[$i]}"
done

log "Aguardando processamento dos lances"
sleep "$SLEEP_AFTER_BIDS"

log "Listando lances por leilao"
perform_request GET "$BASE_URL/bid/$AUCTION_ID"
assert_status 200 "GET /bid/:auctionId"
echo "$HTTP_BODY" | jq .

log "Buscando lance vencedor"
perform_request GET "$BASE_URL/auction/winner/$AUCTION_ID"
assert_status 200 "GET /auction/winner/:auctionId"
echo "$HTTP_BODY" | jq .

WINNER_USER_ID="$(echo "$HTTP_BODY" | jq -r '.bid.user_id // empty')"
WINNER_AMOUNT="$(echo "$HTTP_BODY" | jq -r '.bid.amount // empty')"

if [[ -z "$WINNER_USER_ID" ]]; then
  fail "Nao foi possivel identificar vencedor no retorno de /auction/winner"
fi

log "Consultando usuario vencedor"
perform_request GET "$BASE_URL/user/$WINNER_USER_ID"
assert_status 200 "GET /user/:userId"
echo "$HTTP_BODY" | jq .

log "Resumo final"
echo "Leilao........: $AUCTION_ID"
echo "Produto.......: $PRODUCT_NAME"
echo "Vencedor......: $WINNER_USER_ID"
echo "Valor vencedor: $WINNER_AMOUNT"
echo "Usuarios teste: $USER_1, $USER_2, $USER_3"

log "Script finalizado com sucesso"
