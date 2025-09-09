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

```bash docci-delay-before="3" docci-delay-per-cmd=0.1 docci-output-contains="Operator 1:"
cd docker/

docker run --rm --network host -v ./.nodes:/root/.nodes \
   --env-file .env \
   poa-middleware deploy

OPERATOR_KEY=$(cast wallet new --json | jq -r '.[0].private_key')
OPERATOR_ADDRESS=$(cast wallet addr --private-key "$OPERATOR_KEY")
echo "Operator address: $OPERATOR_ADDRESS"
AVS_KEY=$(cast wallet new --json | jq -r '.[0].private_key')
AVS_SIGNING_ADDRESS=$(cast wallet addr --private-key "$AVS_KEY")
echo "AVS signing address: $AVS_SIGNING_ADDRESS"

docker run --rm --network host -v ./.nodes:/root/.nodes \
   --env-file .env \
   -e OPERATOR_KEY=${OPERATOR_KEY} \
   -e WAVS_SIGNING_KEY=${AVS_SIGNING_ADDRESS} \
   poa-middleware register WAVS_DELEGATE_AMOUNT=1000000000000000

docker run --rm --network host -v ./.nodes:/root/.nodes \
   --env-file .env \
   poa-middleware update_quorum QUORUM_NUMERATOR=3 QUORUM_DENOMINATOR=5

docker run --rm --network host -v ./.nodes:/root/.nodes \
   --env-file .env \
   poa-middleware list_operators
```
