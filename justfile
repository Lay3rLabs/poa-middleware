# Default profile
profile := "ecdsa"

# Build contracts
build:
    FOUNDRY_PROFILE={{profile}} forge build

# Build all profiles
build-all:
    FOUNDRY_PROFILE=bls forge build
    FOUNDRY_PROFILE=ecdsa forge build

# Run tests
test:
    FOUNDRY_PROFILE={{profile}} forge test -vv

# Run all profile tests
test-all:
    FOUNDRY_PROFILE=bls forge test -vv
    FOUNDRY_PROFILE=ecdsa forge test -vv

# Run a single test by name
test-match name:
    FOUNDRY_PROFILE={{profile}} forge test --match-test {{name}} -vv

# Gas report
gas:
    FOUNDRY_PROFILE={{profile}} forge test --gas-report

# Contract sizes
size:
    FOUNDRY_PROFILE={{profile}} forge build --sizes

# Inspect storage layout
inspect contract:
    FOUNDRY_PROFILE={{profile}} forge inspect {{contract}} storage-layout --pretty

# Snapshot
snapshot:
    FOUNDRY_PROFILE={{profile}} forge snapshot -vv

# Format
format:
    forge fmt

# Check formatting
format-check:
    forge fmt --check

# Coverage HTML report
coverage-html:
    FOUNDRY_PROFILE={{profile}} forge build
    FOUNDRY_PROFILE={{profile}} forge coverage --report lcov
    lcov --remove lcov.info 'contracts/script/*' 'node_modules/*' --output-file lcov.info
    genhtml -o coverage-report-{{profile}} lcov.info

# Lint
lint:
    npm run lint

# Lint fix
lint-fix:
    npm run lint:fix

# Clean
clean:
    forge clean

# Update dependencies
update:
    forge update
