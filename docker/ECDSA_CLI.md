# TODO: .

## Setup

```bash
npm install
docker build -t poa-middleware .
```

```bash docci-if-not-exists="docker/.env"
CHAIN=holesky
cp docker/env.example.$CHAIN docker/.env
```

## Test

Terminal 1

```bash docci-background
source docker/.env
anvil --fork-url $FORK_RPC_URL --host 0.0.0.0 --port 8545
```

Terminal 2

<!-- Ensures that the last command outputs operator 1 (i.e. they were registered) -->

```bash
cd docker/

docker run --rm --network host -v ./.nodes:/root/.nodes \
   --env-file .env \
   poa-middleware deploy

OPERATOR_KEY=$(cast wallet new --json | jq -r '.[0].private_key')
OPERATOR_ADDRESS=$(cast wallet addr --private-key "$OPERATOR_KEY")
echo "Operator address: $OPERATOR_ADDRESS"
SIGNING_KEY=$(cast wallet new --json | jq -r '.[0].private_key')
SIGNING_ADDRESS=$(cast wallet addr --private-key "$SIGNING_KEY")
echo "signing address: $SIGNING_ADDRESS"

docker run --rm --network host -v ./.nodes:/root/.nodes \
   --env-file .env \
   poa-middleware owner_operation registerOperator $OPERATOR_ADDRESS 10000

docker run --rm --network host -v ./.nodes:/root/.nodes \
   --env-file .env \
   poa-middleware owner_operation updateOperatorWeight $OPERATOR_ADDRESS 1000

docker run --rm --network host -v ./.nodes:/root/.nodes \
   --env-file .env \
   poa-middleware update_signing_key $OPERATOR_KEY $SIGNING_KEY

docker run --rm --network host -v ./.nodes:/root/.nodes \
   --env-file .env \
   poa-middleware owner_operation deregisterOperator $OPERATOR_ADDRESS

docker run --rm --network host -v ./.nodes:/root/.nodes \
   --env-file .env \
   poa-middleware owner_operation updateStakeThreshold 100

docker run --rm --network host -v ./.nodes:/root/.nodes \
   --env-file .env \
   poa-middleware owner_operation updateQuorum 3 5
```
